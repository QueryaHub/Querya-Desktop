//! SQLite execute + batched row streaming (rusqlite).

use super::error::{ConnectionError, ConnectionResult};
use super::query::QueryEvent;
use rusqlite::{types::ValueRef, Connection, Statement};
use std::time::Instant;

const DEFAULT_BATCH: usize = 256;
const DEFAULT_LIMIT: usize = 5_000;

/// Run SQL and emit column / row-batch / done events. Does not buffer the full grid.
pub fn execute_streaming(
    conn: &Connection,
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

    let mut stmt = conn.prepare(sql)?;

    let col_count = stmt.column_count();
    if col_count == 0 {
        // Non-SELECT (DDL/DML): execute and report changes.
        let affected = stmt.execute([])? as u64;
        emit(QueryEvent::Done {
            row_count: 0,
            truncated: false,
            affected_rows: Some(affected),
            elapsed_ms: elapsed_ms(started),
        })?;
        return Ok(());
    }

    let names: Vec<String> = (0..col_count)
        .map(|i| stmt.column_name(i).unwrap_or("").to_owned())
        .collect();
    emit(QueryEvent::Columns { names })?;

    stream_rows(&mut stmt, col_count, limit, batch_size, started, &mut emit)
}

fn stream_rows(
    stmt: &mut Statement<'_>,
    col_count: usize,
    limit: usize,
    batch_size: usize,
    started: Instant,
    emit: &mut impl FnMut(QueryEvent) -> ConnectionResult<()>,
) -> ConnectionResult<()> {
    let mut rows = stmt.query([])?;

    let mut batch: Vec<Vec<serde_json::Value>> = Vec::with_capacity(batch_size);
    let mut offset: u64 = 0;
    let mut row_count: u64 = 0;
    let mut truncated = false;

    loop {
        if row_count as usize >= limit {
            truncated = true;
            break;
        }

        let row = match rows.next() {
            Ok(Some(r)) => r,
            Ok(None) => break,
            Err(e) => return Err(e.into()),
        };

        let mut cells = Vec::with_capacity(col_count);
        for i in 0..col_count {
            let v = row.get_ref(i)?;
            cells.push(value_ref_to_json(v));
        }
        batch.push(cells);
        row_count += 1;

        if batch.len() >= batch_size {
            let rows_out = std::mem::take(&mut batch);
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
}

fn elapsed_ms(started: Instant) -> u64 {
    started.elapsed().as_millis() as u64
}

fn value_ref_to_json(v: ValueRef<'_>) -> serde_json::Value {
    match v {
        ValueRef::Null => serde_json::Value::Null,
        ValueRef::Integer(i) => serde_json::json!(i),
        ValueRef::Real(f) => {
            if f.is_finite() {
                serde_json::json!(f)
            } else {
                serde_json::Value::String(f.to_string())
            }
        }
        ValueRef::Text(bytes) => {
            let s = String::from_utf8_lossy(bytes);
            serde_json::Value::String(s.into_owned())
        }
        ValueRef::Blob(bytes) => {
            let mut hex = String::with_capacity(2 + bytes.len() * 2);
            hex.push_str("X'");
            for b in bytes {
                use std::fmt::Write;
                let _ = write!(hex, "{b:02x}");
            }
            hex.push('\'');
            serde_json::Value::String(hex)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    fn seed_nums() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("CREATE TABLE nums (n INTEGER);")
            .unwrap();
        for i in 1..=10 {
            conn.execute("INSERT INTO nums(n) VALUES (?1)", [i])
                .unwrap();
        }
        conn
    }

    fn collect(sql: &str, limit: Option<usize>) -> (Vec<QueryEvent>, bool) {
        let conn = seed_nums();
        let mut events = Vec::new();
        let result = execute_streaming(&conn, sql, limit, Some(3), |ev| {
            events.push(ev);
            Ok(())
        });
        (events, result.is_ok())
    }

    #[test]
    fn streams_columns_batches_done() {
        let (events, ok) = collect("SELECT n FROM nums ORDER BY n", None);
        assert!(ok);
        assert!(matches!(events.first(), Some(QueryEvent::Columns { .. })));
        let row_batches: Vec<_> = events
            .iter()
            .filter(|e| matches!(e, QueryEvent::Rows { .. }))
            .collect();
        assert!(row_batches.len() >= 3); // 10 rows / batch 3
        match events.last() {
            Some(QueryEvent::Done {
                row_count,
                truncated,
                ..
            }) => {
                assert_eq!(*row_count, 10);
                assert!(!*truncated);
            }
            other => panic!("expected Done, got {other:?}"),
        }
    }

    #[test]
    fn respects_limit_truncation() {
        let (events, ok) = collect("SELECT n FROM nums ORDER BY n", Some(4));
        assert!(ok);
        match events.last() {
            Some(QueryEvent::Done {
                row_count,
                truncated,
                ..
            }) => {
                assert_eq!(*row_count, 4);
                assert!(*truncated);
            }
            other => panic!("expected Done, got {other:?}"),
        }
    }

    #[test]
    fn dml_reports_affected() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("CREATE TABLE t(id INTEGER); INSERT INTO t VALUES (1),(2);")
            .unwrap();
        let mut events = Vec::new();
        execute_streaming(&conn, "DELETE FROM t", None, None, |ev| {
            events.push(ev);
            Ok(())
        })
        .unwrap();
        match events.as_slice() {
            [QueryEvent::Done {
                affected_rows: Some(2),
                row_count: 0,
                ..
            }] => {}
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn never_buffers_all_rows_in_one_event() {
        let (events, ok) = collect("SELECT n FROM nums ORDER BY n", None);
        assert!(ok);
        for ev in &events {
            if let QueryEvent::Rows { rows, .. } = ev {
                assert!(rows.len() <= 3);
            }
        }
    }

    #[test]
    fn empty_sql_is_invalid_config() {
        let conn = Connection::open_in_memory().unwrap();
        let err = execute_streaming(&conn, "   ", None, None, |_| Ok(())).unwrap_err();
        assert!(matches!(err, ConnectionError::InvalidConfig { .. }));
    }

    #[test]
    fn emit_failure_propagates() {
        let conn = seed_nums();
        let err = execute_streaming(&conn, "SELECT n FROM nums", Some(2), Some(1), |_| {
            Err(ConnectionError::io("channel closed"))
        })
        .unwrap_err();
        assert!(matches!(err, ConnectionError::Io { .. }));
    }
}
