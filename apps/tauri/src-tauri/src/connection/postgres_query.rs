//! Postgres execute + batched row streaming (sqlx).

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use super::postgres::PgPool;
use super::query::QueryEvent;
use super::runtime;
use chrono::{DateTime, NaiveDate, NaiveDateTime, Utc};
use futures_util::TryStreamExt;
use sqlx::postgres::PgRow;
use sqlx::{Column, Executor, Row, TypeInfo, ValueRef};
use std::time::Instant;

const DEFAULT_BATCH: usize = 256;
const DEFAULT_LIMIT: usize = 5_000;

/// Run SQL and emit column / row-batch / done events. Does not buffer the full grid.
pub fn execute_streaming(
    pool: &PgPool,
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
            .map_err(|e| ConnectionError::driver(DriverKind::Postgres, e.to_string()))?;

        let desc = conn
            .describe(sql)
            .await
            .map_err(|e| ConnectionError::driver(DriverKind::Postgres, e.to_string()))?;

        let columns = desc.columns();
        if columns.is_empty() {
            let result = sqlx::query(sql)
                .execute(&mut *conn)
                .await
                .map_err(|e| ConnectionError::driver(DriverKind::Postgres, e.to_string()))?;
            emit(QueryEvent::Done {
                row_count: 0,
                truncated: false,
                affected_rows: Some(result.rows_affected()),
                elapsed_ms: elapsed_ms(started),
            })?;
            return Ok(());
        }

        let names: Vec<String> = columns.iter().map(|c| c.name().to_owned()).collect();
        let col_count = names.len();
        emit(QueryEvent::Columns { names })?;

        let mut stream = sqlx::query(sql).fetch(&mut *conn);
        let mut batch: Vec<Vec<serde_json::Value>> = Vec::with_capacity(batch_size);
        let mut offset: u64 = 0;
        let mut row_count: u64 = 0;
        let mut truncated = false;

        while let Some(row) = stream
            .try_next()
            .await
            .map_err(|e| ConnectionError::driver(DriverKind::Postgres, e.to_string()))?
        {
            if row_count as usize >= limit {
                truncated = true;
                break;
            }
            batch.push(pg_row_to_json(&row, col_count));
            row_count += 1;
            if batch.len() >= batch_size {
                let rows_out = std::mem::take(&mut batch);
                let n = rows_out.len() as u64;
                emit(QueryEvent::Rows {
                    rows: rows_out,
                    offset,
                })?;
                offset += n;
                batch.reserve(batch_size);
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

fn pg_row_to_json(row: &PgRow, col_count: usize) -> Vec<serde_json::Value> {
    (0..col_count).map(|i| pg_cell(row, i)).collect()
}

fn pg_cell(row: &PgRow, i: usize) -> serde_json::Value {
    let Ok(raw) = row.try_get_raw(i) else {
        return serde_json::Value::Null;
    };
    if raw.is_null() {
        return serde_json::Value::Null;
    }

    let type_info = raw.type_info();
    let type_name = type_info.name();

    // Typed attempts — first match wins.
    if type_name == "BOOL" {
        if let Ok(v) = row.try_get::<bool, _>(i) {
            return serde_json::Value::Bool(v);
        }
    }
    if matches!(type_name, "INT2" | "INT4" | "INT8") {
        if let Ok(v) = row.try_get::<i64, _>(i) {
            return serde_json::json!(v);
        }
    }
    if matches!(type_name, "FLOAT4" | "FLOAT8") {
        if let Ok(v) = row.try_get::<f64, _>(i) {
            return serde_json::Number::from_f64(v)
                .map(serde_json::Value::Number)
                .unwrap_or(serde_json::Value::Null);
        }
    }
    if matches!(type_name, "JSON" | "JSONB") {
        if let Ok(v) = row.try_get::<serde_json::Value, _>(i) {
            return v;
        }
    }
    if type_name == "TIMESTAMPTZ" {
        if let Ok(v) = row.try_get::<DateTime<Utc>, _>(i) {
            return serde_json::Value::String(v.to_rfc3339());
        }
    }
    if type_name == "TIMESTAMP" {
        if let Ok(v) = row.try_get::<NaiveDateTime, _>(i) {
            return serde_json::Value::String(v.format("%Y-%m-%dT%H:%M:%S%.f").to_string());
        }
    }
    if type_name == "DATE" {
        if let Ok(v) = row.try_get::<NaiveDate, _>(i) {
            return serde_json::Value::String(v.to_string());
        }
    }
    if type_name == "BYTEA" {
        if let Ok(v) = row.try_get::<Vec<u8>, _>(i) {
            return serde_json::Value::String(bytes_to_hex(&v));
        }
    }

    if let Ok(v) = row.try_get::<String, _>(i) {
        return serde_json::Value::String(v);
    }
    if let Ok(v) = row.try_get::<Vec<u8>, _>(i) {
        return serde_json::Value::String(bytes_to_hex(&v));
    }
    serde_json::Value::String(format!("<{type_name}>"))
}

fn bytes_to_hex(bytes: &[u8]) -> String {
    const HEX: &[u8] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0xf) as usize] as char);
    }
    out
}

fn elapsed_ms(started: Instant) -> u64 {
    started.elapsed().as_millis() as u64
}

#[cfg(test)]
mod tests {
    use crate::connection::manager::ConnectionSession;
    use crate::connection::postgres::{open_postgres, PostgresConnectParams};
    use crate::connection::query::QueryEvent;

    fn live_params() -> Option<PostgresConnectParams> {
        if std::env::var_os("QUERYA_SKIP_PG").is_some() {
            return None;
        }
        let host = std::env::var("QUERYA_PG_HOST").unwrap_or_else(|_| "127.0.0.1".into());
        let port: u16 = std::env::var("QUERYA_PG_PORT")
            .ok()
            .and_then(|p| p.parse().ok())
            .unwrap_or(5432);
        let database = std::env::var("QUERYA_PG_DB").unwrap_or_else(|_| "querya".into());
        let user = std::env::var("QUERYA_PG_USER").unwrap_or_else(|_| "querya".into());
        let password = std::env::var("QUERYA_PG_PASSWORD").unwrap_or_else(|_| "querya".into());
        Some(PostgresConnectParams {
            host,
            port,
            database,
            user,
            password: Some(password),
            id: None,
        })
    }

    #[test]
    fn live_postgres_streams_shop_customers() {
        let Some(params) = live_params() else {
            eprintln!("skip postgres live test (QUERYA_SKIP_PG)");
            return;
        };
        let session = match open_postgres(params) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("skip postgres live test: {e}");
                return;
            }
        };

        let mut events = Vec::new();
        session
            .execute_streaming(
                "SELECT id, name FROM shop.customers ORDER BY id LIMIT 5",
                Some(5),
                |ev| {
                    events.push(ev);
                    Ok(())
                },
            )
            .expect("stream");

        assert!(matches!(events.first(), Some(QueryEvent::Columns { .. })));
        assert!(matches!(
            events.last(),
            Some(QueryEvent::Done {
                row_count: 5,
                truncated: false,
                ..
            })
        ));
        let rows: usize = events
            .iter()
            .filter_map(|e| match e {
                QueryEvent::Rows { rows, .. } => Some(rows.len()),
                _ => None,
            })
            .sum();
        assert_eq!(rows, 5);
        session.disconnect().unwrap();
    }

    #[test]
    fn live_postgres_dml_reports_affected() {
        let Some(params) = live_params() else {
            return;
        };
        let session = match open_postgres(params) {
            Ok(s) => s,
            Err(_) => return,
        };
        let mut events = Vec::new();
        session
            .execute_streaming(
                "UPDATE shop.customers SET name = name WHERE id = -1",
                None,
                |ev| {
                    events.push(ev);
                    Ok(())
                },
            )
            .expect("dml");
        assert!(matches!(
            events.last(),
            Some(QueryEvent::Done {
                affected_rows: Some(0),
                ..
            })
        ));
        session.disconnect().unwrap();
    }
}
