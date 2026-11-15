//! SQLite catalog queries — mirrors Flutter `sqlite_connection.dart`.

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use super::introspect::{ColumnMeta, SchemaObject, SchemaObjectKind, TableSchema};
use rusqlite::Connection;

/// SQLite has no real schemas; expose the default attached DB name.
pub fn list_schemas(_conn: &Connection) -> ConnectionResult<Vec<String>> {
    Ok(vec!["main".into()])
}

/// Tables and views from `sqlite_master` (excludes internal `sqlite_%`).
pub fn list_tables(conn: &Connection) -> ConnectionResult<Vec<SchemaObject>> {
    let mut stmt = conn
        .prepare(
            "SELECT name, type FROM sqlite_master \
             WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' \
             ORDER BY type ASC, name ASC",
        )
        ?;

    let rows = stmt
        .query_map([], |row| {
            let name: String = row.get(0)?;
            let type_str: String = row.get(1)?;
            Ok((name, type_str))
        })
        ?;

    let mut out = Vec::new();
    for row in rows {
        let (name, type_str) =
            row?;
        let kind = match type_str.as_str() {
            "view" => SchemaObjectKind::View,
            _ => SchemaObjectKind::Table,
        };
        out.push(SchemaObject {
            name,
            kind,
            schema: Some("main".into()),
        });
    }
    Ok(out)
}

/// Column meta via `PRAGMA table_info`.
pub fn list_columns(conn: &Connection, table: &str) -> ConnectionResult<TableSchema> {
    let table = table.trim();
    if table.is_empty() {
        return Err(ConnectionError::invalid_config("table name is empty"));
    }
    if table.contains('\0') {
        return Err(ConnectionError::invalid_config(
            "table name contains NUL",
        ));
    }

    let sql = format!("PRAGMA table_info({})", quote_ident(table));
    let mut stmt = conn
        .prepare(&sql)
        ?;

    let rows = stmt
        .query_map([], |row| {
            let name: String = row.get(1)?;
            let data_type: String = row.get::<_, Option<String>>(2)?.unwrap_or_default();
            let notnull: i32 = row.get(3)?;
            let dflt: Option<String> = row.get(4)?;
            let pk: i32 = row.get(5)?;
            Ok((name, data_type, notnull, dflt, pk))
        })
        ?;

    let mut columns = Vec::new();
    let mut primary_keys = Vec::new();
    for row in rows {
        let (name, data_type, notnull, dflt, pk) =
            row?;
        let is_pk = pk > 0;
        if is_pk {
            primary_keys.push(name.clone());
        }
        columns.push(ColumnMeta {
            name,
            data_type,
            is_nullable: notnull == 0,
            is_primary_key: is_pk,
            primary_key_position: if is_pk { Some(pk) } else { None },
            default_value: dflt,
        });
    }

    if columns.is_empty() {
        // Distinguish missing table from empty (SQLite returns 0 rows for unknown).
        let exists: bool = conn
            .query_row(
                "SELECT 1 FROM sqlite_master WHERE name = ?1 AND type IN ('table','view') LIMIT 1",
                [table],
                |_| Ok(true),
            )
            .unwrap_or(false);
        if !exists {
            return Err(ConnectionError::driver(
                DriverKind::Sqlite,
                format!("no such table: {table}"),
            ));
        }
    }

    Ok(TableSchema {
        table_name: table.to_owned(),
        schema: Some("main".into()),
        columns,
        primary_keys,
    })
}

fn quote_ident(name: &str) -> String {
    format!("\"{}\"", name.replace('"', "\"\""))
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    fn fixture() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                email TEXT NOT NULL UNIQUE,
                bio TEXT DEFAULT ''
             );
             CREATE VIEW user_emails AS SELECT id, email FROM users;",
        )
        .unwrap();
        conn
    }

    #[test]
    fn schemas_is_main() {
        let conn = fixture();
        assert_eq!(list_schemas(&conn).unwrap(), vec!["main".to_string()]);
    }

    #[test]
    fn lists_tables_and_views() {
        let conn = fixture();
        let objs = list_tables(&conn).unwrap();
        assert_eq!(objs.len(), 2);
        assert_eq!(objs[0].name, "users");
        assert_eq!(objs[0].kind, SchemaObjectKind::Table);
        assert_eq!(objs[1].name, "user_emails");
        assert_eq!(objs[1].kind, SchemaObjectKind::View);
    }

    #[test]
    fn lists_columns_with_pk() {
        let conn = fixture();
        let schema = list_columns(&conn, "users").unwrap();
        assert_eq!(schema.table_name, "users");
        assert_eq!(schema.primary_keys, vec!["id".to_string()]);
        assert_eq!(schema.columns.len(), 3);
        let id = &schema.columns[0];
        assert!(id.is_primary_key);
        assert_eq!(id.primary_key_position, Some(1));
        let email = &schema.columns[1];
        assert!(!email.is_nullable);
        assert_eq!(email.data_type.to_uppercase(), "TEXT");
        let bio = &schema.columns[2];
        assert!(bio.is_nullable);
        assert_eq!(bio.default_value.as_deref(), Some("''"));
    }

    #[test]
    fn missing_table_errors() {
        let conn = fixture();
        let err = list_columns(&conn, "nope").unwrap_err();
        assert!(matches!(err, ConnectionError::Driver { .. }));
    }

    #[test]
    fn quoted_weird_name_round_trips() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(r#"CREATE TABLE "weird""name" (id INTEGER PRIMARY KEY);"#)
            .unwrap();
        let schema = list_columns(&conn, "weird\"name").unwrap();
        assert_eq!(schema.columns.len(), 1);
    }

    #[test]
    fn rejects_nul_in_table_name() {
        let conn = fixture();
        let err = list_columns(&conn, "users\0x").unwrap_err();
        assert!(matches!(err, ConnectionError::InvalidConfig { .. }));
    }
}
