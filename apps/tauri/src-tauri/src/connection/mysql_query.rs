//! MySQL execute + batched row streaming (sqlx).

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use super::mysql::MySqlPool;
use super::query::QueryEvent;
use super::runtime;
use chrono::{NaiveDate, NaiveDateTime, NaiveTime};
use futures_util::TryStreamExt;
use rust_decimal::Decimal;
use sqlx::mysql::{MySqlRow, MySqlTypeInfo, MySqlValueRef};
use sqlx::{Column, Decode, Executor, Row, TypeInfo, ValueRef};
use std::time::Instant;

const DEFAULT_BATCH: usize = 256;
const DEFAULT_LIMIT: usize = 5_000;

/// Run SQL and emit column / row-batch / done events.
pub fn execute_streaming(
    pool: &MySqlPool,
    sql: &str,
    limit: Option<usize>,
    batch_size: Option<usize>,
    mut emit: impl FnMut(QueryEvent) -> ConnectionResult<()>,
) -> ConnectionResult<()> {
    let sql = sql.trim();
    if sql.is_empty() {
        return Err(ConnectionError::invalid_config("sql is empty"));
    }

    let limit = limit.unwrap_or(DEFAULT_LIMIT);
    let batch_size = batch_size.unwrap_or(DEFAULT_BATCH).max(1);
    let started = Instant::now();

    runtime::block_on(async {
        let mut conn = pool
            .acquire()
            .await
            .map_err(|e| ConnectionError::driver(DriverKind::Mysql, e.to_string()))?;

        let desc = conn
            .describe(sql)
            .await
            .map_err(|e| ConnectionError::driver(DriverKind::Mysql, e.to_string()))?;

        let columns = desc.columns();
        if columns.is_empty() {
            let result = sqlx::query(sql)
                .execute(&mut *conn)
                .await
                .map_err(|e| ConnectionError::driver(DriverKind::Mysql, e.to_string()))?;
            emit(QueryEvent::Done {
                row_count: 0,
                truncated: false,
                affected_rows: Some(result.rows_affected()),
                elapsed_ms: elapsed_ms(started),
            })?;
            return Ok(());
        }

        let decoders: Vec<CellKind> = columns
            .iter()
            .map(|c| CellKind::from_type_info(c.type_info()))
            .collect();
        let names: Vec<String> = columns.iter().map(|c| c.name().to_owned()).collect();
        emit(QueryEvent::Columns { names })?;

        let mut stream = sqlx::query(sql).fetch(&mut *conn);
        let mut batch: Vec<Vec<serde_json::Value>> = Vec::with_capacity(batch_size);
        let mut offset: u64 = 0;
        let mut row_count: u64 = 0;
        let mut truncated = false;

        while let Some(row) = stream
            .try_next()
            .await
            .map_err(|e| ConnectionError::driver(DriverKind::Mysql, e.to_string()))?
        {
            if row_count as usize >= limit {
                truncated = true;
                break;
            }
            batch.push(mysql_row_to_json(&row, &decoders));
            row_count += 1;
            if batch.len() >= batch_size {
                let rows_out = std::mem::replace(&mut batch, Vec::with_capacity(batch_size));
                let n = rows_out.len() as u64;
                emit(QueryEvent::Rows {
                    rows: rows_out,
                    offset,
                })?;
                offset += n;
            }
        }

        if !batch.is_empty() {
            emit(QueryEvent::Rows {
                rows: batch,
                offset,
            })?;
        }

        emit(QueryEvent::Done {
            row_count,
            truncated,
            affected_rows: None,
            elapsed_ms: elapsed_ms(started),
        })?;
        Ok(())
    })
}

#[derive(Clone, Copy, Debug)]
enum CellKind {
    Bool,
    I64,
    U64,
    F64,
    Decimal,
    Text,
    Bytes,
    Date,
    Time,
    DateTime,
    Json,
    Unknown,
}

impl CellKind {
    fn from_type_info(info: &MySqlTypeInfo) -> Self {
        let name = info.name();
        match name {
            "TINYINT" | "BOOLEAN" | "BOOL" => Self::Bool,
            "SMALLINT" | "MEDIUMINT" | "INT" | "INTEGER" | "BIGINT" | "YEAR" => Self::I64,
            "TINYINT UNSIGNED"
            | "SMALLINT UNSIGNED"
            | "MEDIUMINT UNSIGNED"
            | "INT UNSIGNED"
            | "INTEGER UNSIGNED"
            | "BIGINT UNSIGNED" => Self::U64,
            "FLOAT" | "DOUBLE" | "REAL" => Self::F64,
            "DECIMAL" | "NUMERIC" | "NEWDECIMAL" => Self::Decimal,
            "CHAR" | "VARCHAR" | "TINYTEXT" | "TEXT" | "MEDIUMTEXT" | "LONGTEXT" | "ENUM"
            | "SET" => Self::Text,
            "BINARY" | "VARBINARY" | "TINYBLOB" | "BLOB" | "MEDIUMBLOB" | "LONGBLOB" | "BIT" => {
                Self::Bytes
            }
            "DATE" => Self::Date,
            "TIME" => Self::Time,
            "DATETIME" | "TIMESTAMP" => Self::DateTime,
            "JSON" => Self::Json,
            _ => Self::Unknown,
        }
    }
}

fn mysql_row_to_json(row: &MySqlRow, decoders: &[CellKind]) -> Vec<serde_json::Value> {
    decoders
        .iter()
        .enumerate()
        .map(|(i, kind)| mysql_cell(row, i, *kind))
        .collect()
}

fn mysql_cell(row: &MySqlRow, i: usize, kind: CellKind) -> serde_json::Value {
    let Ok(raw) = row.try_get_raw(i) else {
        return serde_json::Value::Null;
    };
    if raw.is_null() {
        return serde_json::Value::Null;
    }
    decode_cell(raw.clone(), kind).unwrap_or(serde_json::Value::Null)
}

fn decode_cell(raw: MySqlValueRef<'_>, kind: CellKind) -> Option<serde_json::Value> {
    match kind {
        CellKind::Bool => decode::<i8>(raw.clone())
            .or_else(|| decode::<bool>(raw).map(i8::from))
            .map(|v| serde_json::Value::Bool(v != 0)),
        CellKind::I64 => decode::<i64>(raw.clone())
            .or_else(|| decode::<i32>(raw.clone()).map(i64::from))
            .or_else(|| decode::<i16>(raw).map(i64::from))
            .map(json_i64),
        CellKind::U64 => decode::<u64>(raw.clone())
            .or_else(|| decode::<u32>(raw).map(u64::from))
            .map(|v| serde_json::Number::from(v).into()),
        CellKind::F64 => decode::<f64>(raw.clone())
            .or_else(|| decode::<f32>(raw).map(f64::from))
            .and_then(|v| serde_json::Number::from_f64(v).map(serde_json::Value::Number)),
        CellKind::Decimal => decode::<Decimal>(raw)
            .map(|v| serde_json::Value::String(v.normalize().to_string())),
        CellKind::Text => decode::<String>(raw).map(serde_json::Value::String),
        CellKind::Bytes => {
            decode::<Vec<u8>>(raw).map(|v| serde_json::Value::String(bytes_to_hex(&v)))
        }
        CellKind::Date => {
            decode::<NaiveDate>(raw).map(|v| serde_json::Value::String(v.to_string()))
        }
        CellKind::Time => {
            decode::<NaiveTime>(raw).map(|v| serde_json::Value::String(v.to_string()))
        }
        CellKind::DateTime => decode::<NaiveDateTime>(raw)
            .map(|v| serde_json::Value::String(v.format("%Y-%m-%dT%H:%M:%S%.f").to_string())),
        CellKind::Json => decode::<serde_json::Value>(raw.clone()).or_else(|| {
            decode::<String>(raw).and_then(|s| serde_json::from_str(&s).ok())
        }),
        CellKind::Unknown => decode::<String>(raw.clone())
            .map(serde_json::Value::String)
            .or_else(|| {
                decode::<Vec<u8>>(raw).map(|v| serde_json::Value::String(bytes_to_hex(&v)))
            }),
    }
}

fn decode<'r, T>(raw: MySqlValueRef<'r>) -> Option<T>
where
    T: Decode<'r, sqlx::MySql>,
{
    T::decode(raw).ok()
}

fn json_i64(v: i64) -> serde_json::Value {
    serde_json::Value::Number(v.into())
}

fn bytes_to_hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(2 + bytes.len() * 2);
    s.push_str("0x");
    for b in bytes {
        use std::fmt::Write;
        let _ = write!(s, "{b:02x}");
    }
    s
}

fn elapsed_ms(started: Instant) -> u64 {
    started.elapsed().as_millis() as u64
}

#[cfg(test)]
mod tests {
    use crate::connection::manager::ConnectionSession;
    use crate::connection::mysql::{open_mysql, MysqlConnectParams};
    use crate::connection::query::QueryEvent;

    fn live_params() -> Option<MysqlConnectParams> {
        if std::env::var_os("QUERYA_SKIP_MYSQL").is_some() {
            return None;
        }
        let host = std::env::var("QUERYA_MYSQL_HOST").unwrap_or_else(|_| "127.0.0.1".into());
        let port: u16 = std::env::var("QUERYA_MYSQL_PORT")
            .ok()
            .and_then(|p| p.parse().ok())
            .unwrap_or(3306);
        let database = std::env::var("QUERYA_MYSQL_DB").unwrap_or_else(|_| "querya".into());
        let user = std::env::var("QUERYA_MYSQL_USER").unwrap_or_else(|_| "querya".into());
        let password =
            std::env::var("QUERYA_MYSQL_PASSWORD").unwrap_or_else(|_| "querya".into());
        Some(MysqlConnectParams {
            host,
            port,
            database,
            user,
            password: Some(password),
            id: None,
        })
    }

    #[test]
    fn live_mysql_streams_select_one() {
        let Some(params) = live_params() else {
            eprintln!("skip mysql live test (QUERYA_SKIP_MYSQL)");
            return;
        };
        let session = match open_mysql(params) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("skip mysql live test: {e}");
                return;
            }
        };

        let mut events = Vec::new();
        session
            .execute_streaming("SELECT 1 AS n, 'ok' AS label", Some(10), |ev| {
                events.push(ev);
                Ok(())
            })
            .expect("stream");

        assert!(
            events
                .iter()
                .any(|e| matches!(e, QueryEvent::Columns { .. })),
            "expected Columns"
        );
        assert!(
            events.iter().any(|e| matches!(e, QueryEvent::Rows { .. })),
            "expected Rows"
        );
        assert!(
            events.iter().any(|e| matches!(
                e,
                QueryEvent::Done {
                    row_count: 1,
                    ..
                }
            )),
            "expected Done row_count=1"
        );
        session.disconnect().ok();
    }
}
