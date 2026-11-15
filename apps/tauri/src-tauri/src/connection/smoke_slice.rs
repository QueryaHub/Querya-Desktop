//! Vertical-slice smoke against the checked-in fixture DB.
#![cfg(test)]

use crate::connection::manager::{ConnectionConfig, ConnectionManager, ConnectionRegistry};
use crate::connection::query::QueryEvent;
use crate::connection::sqlite_query::execute_streaming;
use std::path::PathBuf;

fn fixture_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../fixtures/smoke.db")
}

#[test]
fn connect_introspect_query_fixture() {
    let path = fixture_path();
    assert!(
        path.is_file(),
        "missing fixture at {} — commit apps/tauri/fixtures/smoke.db",
        path.display()
    );

    let reg = ConnectionRegistry::with_builtin_drivers();
    let id = reg
        .connect(ConnectionConfig::Sqlite {
            path: path.to_string_lossy().into_owned(),
        })
        .expect("connect fixture");

    let schemas = reg
        .with_sqlite(&id, |s| s.list_schemas())
        .expect("schemas");
    assert_eq!(schemas, vec!["main".to_string()]);

    let tables = reg.with_sqlite(&id, |s| s.list_tables()).expect("tables");
    let names: Vec<_> = tables.iter().map(|t| t.name.as_str()).collect();
    assert!(names.contains(&"users"));
    assert!(names.contains(&"user_emails"));

    let cols = reg
        .with_sqlite(&id, |s| s.list_columns("users"))
        .expect("columns");
    assert_eq!(cols.primary_keys, vec!["id".to_string()]);
    assert!(cols.columns.iter().any(|c| c.name == "email"));

    let mut events = Vec::new();
    reg.with_sqlite(&id, |s| {
        s.with_connection(|conn| {
            execute_streaming(
                conn,
                "SELECT id, email FROM users ORDER BY id",
                Some(10),
                Some(1),
                |ev| {
                    events.push(ev);
                    Ok(())
                },
            )
        })
    })
    .expect("query");

    assert!(matches!(
        events.first(),
        Some(QueryEvent::Columns { names })
            if names == &["id".to_string(), "email".to_string()]
    ));
    let row_events: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, QueryEvent::Rows { .. }))
        .collect();
    assert_eq!(
        row_events.len(),
        2,
        "batch_size=1 should yield one event per row"
    );
    match events.last() {
        Some(QueryEvent::Done {
            row_count,
            truncated,
            ..
        }) => {
            assert_eq!(*row_count, 2);
            assert!(!*truncated);
        }
        other => panic!("expected Done, got {other:?}"),
    }

    reg.disconnect(&id).expect("disconnect");
}
