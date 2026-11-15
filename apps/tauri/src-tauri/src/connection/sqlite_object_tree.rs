//! SQLite [`ObjectTreeProvider`] — schemas → tables/views → columns.

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use super::introspect::{SchemaObjectKind, TableSchema};
use super::object_tree::{
    column_id, parse_object_id, relation_id, schema_id, ObjectTreeProvider, ParsedObjectId,
    SqlObjectKind, SqlObjectNode,
};
use super::sqlite::SqliteSession;

const DRIVER: DriverKind = DriverKind::Sqlite;

/// Object tree backed by a cloned [`SqliteSession`] handle (registry lock already released).
pub struct SqliteObjectTree {
    session: SqliteSession,
}

impl SqliteObjectTree {
    pub fn new(session: SqliteSession) -> Self {
        Self { session }
    }
}

impl ObjectTreeProvider for SqliteObjectTree {
    fn list_children(&self, parent_id: Option<&str>) -> ConnectionResult<Vec<SqlObjectNode>> {
        match parent_id {
            None => self.list_schemas(),
            Some(id) => match parse_object_id(id)? {
                ParsedObjectId::Schema { schema, .. } => self.list_relations(&schema, id),
                ParsedObjectId::Relation { schema, name, .. } => {
                    self.list_columns(&schema, &name, id)
                }
                ParsedObjectId::Column { .. } => Ok(vec![]),
            },
        }
    }

    fn describe(&self, object_id: &str) -> ConnectionResult<TableSchema> {
        match parse_object_id(object_id)? {
            ParsedObjectId::Relation { name, .. } => self.session.list_columns(&name),
            ParsedObjectId::Schema { .. } | ParsedObjectId::Column { .. } => Err(
                ConnectionError::invalid_config("describe requires a table or view id"),
            ),
        }
    }
}

impl SqliteObjectTree {
    fn list_schemas(&self) -> ConnectionResult<Vec<SqlObjectNode>> {
        Ok(self
            .session
            .list_schemas()?
            .into_iter()
            .map(|name| {
                SqlObjectNode::new(
                    schema_id(DRIVER, &name),
                    name.clone(),
                    SqlObjectKind::Schema,
                    Some(name),
                    None,
                )
            })
            .collect())
    }

    fn list_relations(
        &self,
        schema: &str,
        parent_id: &str,
    ) -> ConnectionResult<Vec<SqlObjectNode>> {
        // SQLite only exposes `main` for now; attached DBs later.
        if schema != "main" {
            return Ok(vec![]);
        }
        Ok(self
            .session
            .list_tables()?
            .into_iter()
            .map(|o| {
                let kind = match o.kind {
                    SchemaObjectKind::View => SqlObjectKind::View,
                    SchemaObjectKind::Table => SqlObjectKind::Table,
                };
                let schema_name = o.schema.unwrap_or_else(|| "main".into());
                SqlObjectNode::new(
                    relation_id(DRIVER, kind, &schema_name, &o.name),
                    o.name,
                    kind,
                    Some(schema_name),
                    Some(parent_id.to_owned()),
                )
            })
            .collect())
    }

    fn list_columns(
        &self,
        schema: &str,
        table: &str,
        parent_id: &str,
    ) -> ConnectionResult<Vec<SqlObjectNode>> {
        Ok(self
            .session
            .list_columns(table)?
            .columns
            .into_iter()
            .map(|c| {
                SqlObjectNode::new(
                    column_id(DRIVER, schema, table, &c.name),
                    c.name,
                    SqlObjectKind::Column,
                    Some(schema.to_owned()),
                    Some(parent_id.to_owned()),
                )
            })
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::connection::manager::{ConnectionConfig, ConnectionManager, ConnectionRegistry};
    use rusqlite::Connection;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_db() -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("querya_obj_tree_{nanos}.db"))
    }

    #[test]
    fn sqlite_tree_schema_table_column() {
        let path = temp_db();
        {
            let conn = Connection::open(&path).unwrap();
            conn.execute_batch(
                "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
                 CREATE VIEW v_users AS SELECT id FROM users;",
            )
            .unwrap();
        }
        let reg = ConnectionRegistry::with_builtin_drivers();
        let id = reg
            .connect(ConnectionConfig::Sqlite {
                path: path.to_string_lossy().into(),
                id: None,
            })
            .unwrap();

        let schemas = reg.list_children(&id, None).unwrap();
        assert_eq!(schemas.len(), 1);
        assert_eq!(schemas[0].kind, SqlObjectKind::Schema);
        assert_eq!(schemas[0].id, "sqlite:schema:main");

        let relations = reg.list_children(&id, Some(&schemas[0].id)).unwrap();
        assert_eq!(relations.len(), 2);
        assert!(relations.iter().any(|n| n.id == "sqlite:table:main:users"));
        assert!(relations.iter().any(|n| n.id == "sqlite:view:main:v_users"));

        let users = relations
            .iter()
            .find(|n| n.name == "users")
            .expect("users");
        let cols = reg.list_children(&id, Some(&users.id)).unwrap();
        assert_eq!(cols.len(), 2);
        assert_eq!(cols[0].id, "sqlite:column:main:users:id");

        let schema = reg.describe_object(&id, &users.id).unwrap();
        assert_eq!(schema.primary_keys, vec!["id".to_string()]);

        reg.disconnect(&id).unwrap();
        let _ = std::fs::remove_file(&path);
    }
}
