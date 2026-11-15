//! SQLite ER catalog — mirrors Flutter `ErdCatalog` SQLite queries.

use super::erd::{ErdColumn, ErdRelation, ErdSchema, ErdTable};
use super::error::ConnectionResult;
use rusqlite::Connection;
use std::collections::HashSet;

/// Load tables + views + foreign keys for the ER canvas.
///
/// When `focus` is set, only the neighbourhood within `depth` FK hops is kept.
pub fn load_schema(
    conn: &Connection,
    focus: Option<&str>,
    depth: usize,
) -> ConnectionResult<ErdSchema> {
    let relations = load_foreign_keys(conn)?;
    let mut schema = ErdSchema {
        tables: load_tables(conn)?,
        relations,
        truncated: false,
    };
    schema.mark_foreign_keys();
    schema.annotate_relations();

    if let Some(focus) = focus {
        let names = super::erd::neighbourhood(&schema.relations, focus, depth);
        // Always include focus even with zero FKs.
        let mut names = names;
        names.insert(focus.to_owned());
        schema.filter_tables(&names);
    }

    Ok(schema)
}

fn load_tables(conn: &Connection) -> ConnectionResult<Vec<ErdTable>> {
    let mut stmt = conn.prepare(
        "SELECT name, type FROM sqlite_master \
         WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' \
         ORDER BY type ASC, name ASC",
    )?;
    let rows = stmt.query_map([], |row| {
        let name: String = row.get(0)?;
        let kind: String = row.get(1)?;
        Ok((name, kind))
    })?;

    let mut tables = Vec::new();
    for row in rows {
        let (name, kind) = row?;
        let is_view = kind == "view";
        let columns = load_columns(conn, &name, is_view)?;
        tables.push(ErdTable {
            name,
            schema: Some("main".into()),
            columns,
            is_view,
        });
    }
    Ok(tables)
}

fn load_columns(
    conn: &Connection,
    table: &str,
    is_view: bool,
) -> ConnectionResult<Vec<ErdColumn>> {
    let sql = format!("PRAGMA table_info({})", quote_ident(table));
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map([], |row| {
        let name: String = row.get(1)?;
        let data_type: String = row.get::<_, Option<String>>(2)?.unwrap_or_default();
        let notnull: i32 = row.get(3)?;
        let dflt: Option<String> = row.get(4)?;
        let pk: i32 = row.get(5)?;
        Ok((name, data_type, notnull, dflt, pk))
    })?;

    let mut columns = Vec::new();
    let mut pk_count = 0i32;
    let mut collected: Vec<(String, String, i32, Option<String>, i32)> = Vec::new();
    for row in rows {
        let tup = row?;
        if tup.4 > 0 {
            pk_count += 1;
        }
        collected.push(tup);
    }

    // Unique single-column indexes (non-PK) for 1:1 annotation.
    let unique_cols = if is_view {
        HashSet::new()
    } else {
        unique_column_names(conn, table)?
    };

    for (name, data_type, notnull, dflt, pk) in collected {
        let is_pk = !is_view && pk > 0;
        let is_identity = is_pk
            && pk_count == 1
            && data_type.eq_ignore_ascii_case("INTEGER");
        let is_unique = unique_cols.contains(&name);
        columns.push(ErdColumn {
            name,
            data_type,
            is_primary_key: is_pk,
            is_foreign_key: false,
            is_nullable: is_view || notnull == 0,
            is_unique,
            default_value: dflt,
            is_identity,
        });
    }
    Ok(columns)
}

fn unique_column_names(conn: &Connection, table: &str) -> ConnectionResult<HashSet<String>> {
    let sql = format!("PRAGMA index_list({})", quote_ident(table));
    let mut stmt = conn.prepare(&sql)?;
    let indexes: Vec<(String, i32, String)> = stmt
        .query_map([], |row| {
            let name: String = row.get(1)?;
            let unique: i32 = row.get(2)?;
            let origin: String = row.get(3)?;
            Ok((name, unique, origin))
        })?
        .collect::<Result<_, _>>()?;

    let mut out = HashSet::new();
    for (idx_name, unique, origin) in indexes {
        if unique != 1 || origin == "pk" {
            continue;
        }
        let info_sql = format!("PRAGMA index_info({})", quote_ident(&idx_name));
        let mut info = conn.prepare(&info_sql)?;
        let cols: Vec<String> = info
            .query_map([], |row| {
                let name: Option<String> = row.get(2)?;
                Ok(name.unwrap_or_default())
            })?
            .collect::<Result<_, _>>()?;
        if cols.len() == 1 && !cols[0].is_empty() {
            out.insert(cols[0].clone());
        }
    }
    Ok(out)
}

fn load_foreign_keys(conn: &Connection) -> ConnectionResult<Vec<ErdRelation>> {
    let mut stmt = conn.prepare(
        "SELECT name FROM sqlite_master \
         WHERE type = 'table' AND name NOT LIKE 'sqlite_%' \
         ORDER BY name",
    )?;
    let tables: Vec<String> = stmt
        .query_map([], |row| row.get(0))?
        .collect::<Result<_, _>>()?;

    let mut relations = Vec::new();
    for table in tables {
        let sql = format!("PRAGMA foreign_key_list({})", quote_ident(&table));
        let mut fk_stmt = conn.prepare(&sql)?;
        let rows = fk_stmt.query_map([], |row| {
            let from_col: String = row.get(3)?;
            let to_table: String = row.get(2)?;
            let to_col: String = row.get(4)?;
            Ok((from_col, to_table, to_col))
        })?;
        for row in rows {
            let (from_column, to_table, to_column) = row?;
            relations.push(ErdRelation {
                from_table: table.clone(),
                from_column,
                to_table,
                to_column,
                optional: false,
                one_to_one: false,
            });
        }
    }
    Ok(relations)
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
            "PRAGMA foreign_keys = ON;
             CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                email TEXT NOT NULL UNIQUE
             );
             CREATE TABLE orders (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id),
                total REAL
             );
             CREATE VIEW v_users AS SELECT id, email FROM users;",
        )
        .unwrap();
        conn
    }

    #[test]
    fn loads_tables_views_and_fks() {
        let conn = fixture();
        let schema = load_schema(&conn, None, 1).unwrap();
        assert_eq!(schema.tables.len(), 3);
        let orders = schema
            .tables
            .iter()
            .find(|t| t.name == "orders")
            .expect("orders");
        assert!(
            orders
                .columns
                .iter()
                .any(|c| c.name == "user_id" && c.is_foreign_key)
        );
        assert_eq!(schema.relations.len(), 1);
        assert_eq!(schema.relations[0].from_table, "orders");
        assert_eq!(schema.relations[0].to_table, "users");
    }

    #[test]
    fn neighbourhood_focus() {
        let conn = fixture();
        let schema = load_schema(&conn, Some("users"), 1).unwrap();
        let names: HashSet<_> = schema.tables.iter().map(|t| t.name.as_str()).collect();
        assert!(names.contains("users"));
        assert!(names.contains("orders"));
        assert!(!names.contains("v_users"));
    }
}
