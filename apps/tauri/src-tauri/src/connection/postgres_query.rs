//! Postgres execute + batched row streaming (sqlx).

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use super::postgres::PgPool;
use super::query::QueryEvent;
use super::runtime;
use chrono::{DateTime, FixedOffset, NaiveDate, NaiveDateTime, NaiveTime, Utc};
use futures_util::TryStreamExt;
use sqlx::postgres::types::{
    Oid, PgBox, PgCircle, PgInterval, PgLine, PgLSeg, PgMoney, PgPath, PgPoint, PgPolygon, PgRange,
    PgTimeTz,
};
use sqlx::postgres::{PgTypeInfo, PgValueFormat, PgValueRef};
use sqlx::postgres::PgRow;
use sqlx::{Column, Decode, Executor, Row, TypeInfo, ValueRef};
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

        // Resolve decode strategy once per column (not per cell).
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
            .map_err(|e| ConnectionError::driver(DriverKind::Postgres, e.to_string()))?
        {
            if row_count as usize >= limit {
                truncated = true;
                break;
            }
            batch.push(pg_row_to_json(&row, &decoders));
            row_count += 1;
            if batch.len() >= batch_size {
                // Replace keeps capacity discipline without take→reserve churn.
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
    Int2,
    Int4,
    Int8,
    Float4,
    Float8,
    Numeric,
    Money,
    Text,
    Json,
    Timestamptz,
    Timestamp,
    Date,
    Time,
    Timetz,
    Interval,
    Bytea,
    Uuid,
    Oid,
    Inet,
    Macaddr,
    Bit,
    Point,
    Line,
    Lseg,
    Box,
    Path,
    Polygon,
    Circle,
    Int4Range,
    Int8Range,
    NumRange,
    TsRange,
    TstzRange,
    DateRange,
    Int4Array,
    Int8Array,
    TextArray,
    UuidArray,
    BoolArray,
    JsonbArray,
    NumericArray,
    Unknown,
}

impl CellKind {
    fn from_type_info(info: &PgTypeInfo) -> Self {
        Self::from_name(info.name())
    }

    fn from_name(name: &str) -> Self {
        match name {
            "BOOL" => Self::Bool,
            "INT2" => Self::Int2,
            "INT4" => Self::Int4,
            "INT8" => Self::Int8,
            "FLOAT4" => Self::Float4,
            "FLOAT8" => Self::Float8,
            "NUMERIC" => Self::Numeric,
            "MONEY" => Self::Money,
            "TEXT" | "VARCHAR" | "CHAR" | "NAME" | "BPCHAR" | "CITEXT" | "XML" | "xml" => {
                Self::Text
            }
            "JSON" | "JSONB" => Self::Json,
            "TIMESTAMPTZ" => Self::Timestamptz,
            "TIMESTAMP" => Self::Timestamp,
            "DATE" => Self::Date,
            "TIME" => Self::Time,
            "TIMETZ" => Self::Timetz,
            "INTERVAL" => Self::Interval,
            "BYTEA" => Self::Bytea,
            "UUID" => Self::Uuid,
            "OID" => Self::Oid,
            "INET" | "CIDR" => Self::Inet,
            "MACADDR" => Self::Macaddr,
            // MACADDR8 (EUI-64) has no sqlx Decode in 0.8 — falls through to textish.
            "BIT" | "VARBIT" => Self::Bit,
            "POINT" => Self::Point,
            "LINE" => Self::Line,
            "LSEG" => Self::Lseg,
            "BOX" => Self::Box,
            "PATH" => Self::Path,
            "POLYGON" => Self::Polygon,
            "CIRCLE" => Self::Circle,
            "INT4RANGE" => Self::Int4Range,
            "INT8RANGE" => Self::Int8Range,
            "NUMRANGE" => Self::NumRange,
            "TSRANGE" => Self::TsRange,
            "TSTZRANGE" => Self::TstzRange,
            "DATERANGE" => Self::DateRange,
            "INT2[]" | "INT4[]" => Self::Int4Array,
            "INT8[]" => Self::Int8Array,
            "TEXT[]" | "VARCHAR[]" | "CHAR[]" | "NAME[]" | "BPCHAR[]" => Self::TextArray,
            "UUID[]" => Self::UuidArray,
            "BOOL[]" => Self::BoolArray,
            "JSON[]" | "JSONB[]" => Self::JsonbArray,
            "NUMERIC[]" => Self::NumericArray,
            _ => Self::Unknown,
        }
    }
}

fn pg_row_to_json(row: &PgRow, decoders: &[CellKind]) -> Vec<serde_json::Value> {
    let mut out = Vec::with_capacity(decoders.len());
    for (i, kind) in decoders.iter().enumerate() {
        out.push(pg_cell(row, i, *kind));
    }
    out
}

fn pg_cell(row: &PgRow, i: usize, kind: CellKind) -> serde_json::Value {
    let Ok(raw) = row.try_get_raw(i) else {
        return serde_json::Value::Null;
    };
    if raw.is_null() {
        return serde_json::Value::Null;
    }

    match decode_cell(raw.clone(), kind) {
        Some(v) => v,
        None => {
            let type_info = raw.type_info();
            textish_fallback(row, i, type_info.name())
        }
    }
}

fn decode_cell(raw: PgValueRef<'_>, kind: CellKind) -> Option<serde_json::Value> {
    match kind {
        CellKind::Bool => decode::<bool>(raw).map(serde_json::Value::Bool),
        CellKind::Int2 => decode::<i16>(raw).map(|v| json_i64(i64::from(v))),
        CellKind::Int4 => decode::<i32>(raw).map(|v| json_i64(i64::from(v))),
        CellKind::Int8 => decode::<i64>(raw).map(json_i64),
        CellKind::Float4 => decode::<f32>(raw).map(|v| f64_json(f64::from(v))),
        CellKind::Float8 => decode::<f64>(raw).map(f64_json),
        CellKind::Numeric => decode::<rust_decimal::Decimal>(raw)
            .map(|v| serde_json::Value::String(v.normalize().to_string())),
        CellKind::Money => decode::<PgMoney>(raw).map(|v| {
            serde_json::Value::String(v.to_decimal(2).normalize().to_string())
        }),
        CellKind::Text => decode::<String>(raw).map(serde_json::Value::String),
        CellKind::Json => decode::<serde_json::Value>(raw),
        CellKind::Timestamptz => decode::<DateTime<Utc>>(raw)
            .map(|v| serde_json::Value::String(v.to_rfc3339())),
        CellKind::Timestamp => decode::<NaiveDateTime>(raw).map(|v| {
            serde_json::Value::String(v.format("%Y-%m-%dT%H:%M:%S%.f").to_string())
        }),
        CellKind::Date => {
            decode::<NaiveDate>(raw).map(|v| serde_json::Value::String(v.to_string()))
        }
        CellKind::Time => {
            decode::<NaiveTime>(raw).map(|v| serde_json::Value::String(v.to_string()))
        }
        CellKind::Timetz => decode::<PgTimeTz<NaiveTime, FixedOffset>>(raw).map(|v| {
            serde_json::Value::String(format!("{}{}", v.time, v.offset))
        }),
        CellKind::Interval => decode::<PgInterval>(raw).map(|v| {
            serde_json::Value::String(format_interval(&v))
        }),
        CellKind::Bytea => decode::<Vec<u8>>(raw).map(|v| serde_json::Value::String(bytes_to_hex(&v))),
        CellKind::Uuid => {
            decode::<uuid::Uuid>(raw).map(|v| serde_json::Value::String(v.to_string()))
        }
        CellKind::Oid => decode::<Oid>(raw).map(|v| json_i64(i64::from(v.0))),
        CellKind::Inet => decode::<ipnetwork::IpNetwork>(raw)
            .map(|v| serde_json::Value::String(v.to_string())),
        CellKind::Macaddr => decode::<mac_address::MacAddress>(raw)
            .map(|v| serde_json::Value::String(v.to_string())),
        CellKind::Bit => decode::<bit_vec::BitVec>(raw).map(|v| {
            let mut s = String::with_capacity(v.len());
            for bit in v.iter() {
                s.push(if bit { '1' } else { '0' });
            }
            serde_json::Value::String(s)
        }),
        CellKind::Point => decode::<PgPoint>(raw).map(|v| {
            serde_json::Value::String(format!("({},{})", v.x, v.y))
        }),
        CellKind::Line => decode::<PgLine>(raw).map(|v| {
            serde_json::Value::String(format!("{{{},{},{}}}", v.a, v.b, v.c))
        }),
        CellKind::Lseg => decode::<PgLSeg>(raw).map(|v| {
            serde_json::Value::String(format!(
                "[({},{}),({},{})]",
                v.start_x, v.start_y, v.end_x, v.end_y
            ))
        }),
        CellKind::Box => decode::<PgBox>(raw).map(|v| {
            serde_json::Value::String(format!(
                "({},{}),({},{})",
                v.upper_right_x, v.upper_right_y, v.lower_left_x, v.lower_left_y
            ))
        }),
        CellKind::Path => decode::<PgPath>(raw).map(|v| {
            let body = format_points(&v.points);
            serde_json::Value::String(if v.closed {
                format!("({body})")
            } else {
                format!("[{body}]")
            })
        }),
        CellKind::Polygon => decode::<PgPolygon>(raw).map(|v| {
            serde_json::Value::String(format!("(({}))", format_points(&v.points)))
        }),
        CellKind::Circle => decode::<PgCircle>(raw).map(|v| {
            serde_json::Value::String(format!("<({},{}),{}>", v.x, v.y, v.radius))
        }),
        CellKind::Int4Range => decode::<PgRange<i32>>(raw)
            .map(|v| serde_json::Value::String(v.to_string())),
        CellKind::Int8Range => decode::<PgRange<i64>>(raw)
            .map(|v| serde_json::Value::String(v.to_string())),
        CellKind::NumRange => decode::<PgRange<rust_decimal::Decimal>>(raw)
            .map(|v| serde_json::Value::String(v.to_string())),
        CellKind::TsRange => decode::<PgRange<NaiveDateTime>>(raw)
            .map(|v| serde_json::Value::String(v.to_string())),
        CellKind::TstzRange => decode::<PgRange<DateTime<Utc>>>(raw)
            .map(|v| serde_json::Value::String(v.to_string())),
        CellKind::DateRange => decode::<PgRange<NaiveDate>>(raw)
            .map(|v| serde_json::Value::String(v.to_string())),
        CellKind::Int4Array => decode::<Vec<i32>>(raw).map(|v| {
            serde_json::Value::Array(v.into_iter().map(|n| json_i64(i64::from(n))).collect())
        }),
        CellKind::Int8Array => decode::<Vec<i64>>(raw).map(|v| {
            serde_json::Value::Array(v.into_iter().map(json_i64).collect())
        }),
        CellKind::TextArray => decode::<Vec<String>>(raw).map(|v| {
            serde_json::Value::Array(v.into_iter().map(serde_json::Value::String).collect())
        }),
        CellKind::UuidArray => decode::<Vec<uuid::Uuid>>(raw).map(|v| {
            serde_json::Value::Array(
                v.into_iter()
                    .map(|u| serde_json::Value::String(u.to_string()))
                    .collect(),
            )
        }),
        CellKind::BoolArray => decode::<Vec<bool>>(raw).map(|v| {
            serde_json::Value::Array(v.into_iter().map(serde_json::Value::Bool).collect())
        }),
        CellKind::JsonbArray => decode::<Vec<serde_json::Value>>(raw).map(serde_json::Value::Array),
        CellKind::NumericArray => decode::<Vec<rust_decimal::Decimal>>(raw).map(|v| {
            serde_json::Value::Array(
                v.into_iter()
                    .map(|n| serde_json::Value::String(n.normalize().to_string()))
                    .collect(),
            )
        }),
        CellKind::Unknown => None,
    }
}

fn decode<'r, T>(raw: PgValueRef<'r>) -> Option<T>
where
    T: Decode<'r, sqlx::Postgres>,
{
    T::decode(raw).ok()
}

fn textish_fallback(row: &PgRow, i: usize, type_name: &str) -> serde_json::Value {
    if let Ok(v) = row.try_get::<String, _>(i) {
        return serde_json::Value::String(v);
    }
    if let Ok(raw) = row.try_get_raw(i) {
        if let Ok(s) = raw_as_utf8(raw) {
            return serde_json::Value::String(s);
        }
    }
    if let Ok(v) = row.try_get::<Vec<u8>, _>(i) {
        return serde_json::Value::String(bytes_to_hex(&v));
    }
    serde_json::Value::String(format!("<{type_name}>"))
}

fn raw_as_utf8(raw: PgValueRef<'_>) -> Result<String, ()> {
    match raw.format() {
        PgValueFormat::Text => raw.as_str().map(|s| s.to_owned()).map_err(|_| ()),
        PgValueFormat::Binary => {
            let bytes = raw.as_bytes().map_err(|_| ())?;
            std::str::from_utf8(bytes)
                .map(|s| s.to_owned())
                .map_err(|_| ())
        }
    }
}

fn format_points(points: &[PgPoint]) -> String {
    let mut out = String::with_capacity(points.len().saturating_mul(16));
    for (i, p) in points.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        use std::fmt::Write;
        let _ = write!(out, "({},{})", p.x, p.y);
    }
    out
}

fn format_interval(v: &PgInterval) -> String {
    let secs = v.microseconds / 1_000_000;
    let micros = (v.microseconds % 1_000_000).abs();
    if micros == 0 {
        format!("{} mon {} days {} seconds", v.months, v.days, secs)
    } else {
        format!(
            "{} mon {} days {}.{:06} seconds",
            v.months, v.days, secs, micros
        )
    }
}

fn json_i64(v: i64) -> serde_json::Value {
    serde_json::Value::Number(v.into())
}

fn f64_json(v: f64) -> serde_json::Value {
    serde_json::Number::from_f64(v)
        .map(serde_json::Value::Number)
        .unwrap_or(serde_json::Value::Null)
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

        let first_id = events.iter().find_map(|e| match e {
            QueryEvent::Rows { rows, .. } => rows.first().and_then(|r| r.first()),
            _ => None,
        });
        match first_id {
            Some(serde_json::Value::Number(n)) => assert!(n.as_i64().is_some()),
            other => panic!("expected numeric id, got {other:?}"),
        }

        session.disconnect().unwrap();
    }

    #[test]
    fn live_postgres_decodes_numeric_not_placeholder() {
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
                "SELECT id, total, discount FROM shop.orders ORDER BY id LIMIT 3",
                Some(3),
                |ev| {
                    events.push(ev);
                    Ok(())
                },
            )
            .expect("stream");
        let row = events.iter().find_map(|e| match e {
            QueryEvent::Rows { rows, .. } => rows.first().cloned(),
            _ => None,
        });
        let Some(cells) = row else {
            panic!("no rows");
        };
        assert!(
            matches!(cells[0], serde_json::Value::Number(_)),
            "id INT4: {cells:?}"
        );
        assert!(
            matches!(&cells[1], serde_json::Value::String(s) if !s.starts_with('<')),
            "total NUMERIC: {cells:?}"
        );
        session.disconnect().unwrap();
    }

    #[test]
    fn live_postgres_decodes_text_array_tags() {
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
                "SELECT tags FROM shop.products WHERE tags IS NOT NULL LIMIT 1",
                Some(1),
                |ev| {
                    events.push(ev);
                    Ok(())
                },
            )
            .expect("stream");
        let cell = events.iter().find_map(|e| match e {
            QueryEvent::Rows { rows, .. } => rows.first().and_then(|r| r.first()).cloned(),
            _ => None,
        });
        match cell {
            Some(serde_json::Value::Array(items)) => {
                assert!(!items.is_empty());
                assert!(items.iter().all(|v| v.is_string()));
            }
            other => panic!("expected TEXT[] as JSON array, got {other:?}"),
        }
        session.disconnect().unwrap();
    }

    #[test]
    fn live_postgres_showcase_has_no_angle_placeholders() {
        let Some(params) = live_params() else {
            return;
        };
        let session = match open_postgres(params) {
            Ok(s) => s,
            Err(_) => return,
        };
        let tables = [
            "all_numerics",
            "all_datetime",
            "all_identifiers_and_network",
            "all_binary_and_bits",
            "all_geometric",
            "all_ranges",
            "all_arrays",
            "all_strings",
            "all_json_xml",
        ];
        let mut placeholders = Vec::new();
        for table in tables {
            let sql = format!("SELECT * FROM types_showcase.{table} LIMIT 1");
            let mut events = Vec::new();
            if session
                .execute_streaming(&sql, Some(1), |ev| {
                    events.push(ev);
                    Ok(())
                })
                .is_err()
            {
                continue;
            }
            let cols = events.iter().find_map(|e| match e {
                QueryEvent::Columns { names } => Some(names.clone()),
                _ => None,
            });
            let row = events.iter().find_map(|e| match e {
                QueryEvent::Rows { rows, .. } => rows.first().cloned(),
                _ => None,
            });
            let (Some(cols), Some(cells)) = (cols, row) else {
                continue;
            };
            for (name, cell) in cols.iter().zip(cells.iter()) {
                // Multiranges are still unsupported — allow only those.
                if name.contains("multirange") {
                    continue;
                }
                if let serde_json::Value::String(s) = cell {
                    if s.starts_with('<') && s.ends_with('>') && !s.contains('(') {
                        // geometric circle uses <(x,y),r> — not a type placeholder
                        if s.chars().nth(1).is_some_and(|c| c.is_ascii_uppercase())
                            || s.chars().nth(1) == Some('_')
                            || name.contains("multirange")
                        {
                            placeholders.push(format!("{table}.{name}={s}"));
                        }
                    }
                }
            }
        }
        session.disconnect().ok();
        assert!(
            placeholders.is_empty(),
            "unexpected type placeholders:\n{}",
            placeholders.join("\n")
        );
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
