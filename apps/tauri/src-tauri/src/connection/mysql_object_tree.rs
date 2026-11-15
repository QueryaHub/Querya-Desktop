//! MySQL [`ObjectTreeProvider`] — databases → tables/views → columns.

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use super::introspect::{ColumnMeta, TableSchema};
use super::mysql::MysqlSession;
use super::object_tree::{
    column_id, parse_object_id, relation_id, schema_id, ObjectTreeProvider, ParsedObjectId,
    SqlObjectKind, SqlObjectNode,
};
use super::runtime;
use sqlx::Row;

const DRIVER: DriverKind = DriverKind::Mysql;

pub struct MysqlObjectTree {
    session: MysqlSession,
}

impl MysqlObjectTree {
    pub fn new(session: MysqlSession) -> Self {
        Self { session }
    }
}

impl ObjectTreeProvider for MysqlObjectTree {
    fn list_children(&self, parent_id: Option<&str>) -> ConnectionResult<Vec<SqlObjectNode>> {
        match parent_id {
            None => self.list_schemas(),
            Some(id) => match parse_object_id(id)? {
                ParsedObjectId::Schema { schema, .. } => self.list_relations(&schema, id),
                ParsedObjectId::Relation { schema, name, .. } => {
                    self.list_columns(&schema, &name, id)
                }
                ParsedObjectId::Column { .. }
                | ParsedObjectId::Folder { .. }
                | ParsedObjectId::Named { .. }
                | ParsedObjectId::RelationChild { .. } => Ok(vec![]),
            },
        }
    }

    fn describe(&self, object_id: &str) -> ConnectionResult<TableSchema> {
        match parse_object_id(object_id)? {
            ParsedObjectId::Relation { schema, name, .. } => self.describe_relation(&schema, &name),
            _ => Err(ConnectionError::invalid_config(
                "describe requires a table or view id",
            )),
        }
    }
}

impl MysqlObjectTree {
    fn list_schemas(&self) -> ConnectionResult<Vec<SqlObjectNode>> {
        self.session.with_pool(|pool| {
            runtime::block_on(async {
                let rows = sqlx::query(
                    "SELECT SCHEMA_NAME
                     FROM information_schema.SCHEMATA
                     WHERE SCHEMA_NAME NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')
                     ORDER BY SCHEMA_NAME",
                )
                .fetch_all(pool)
                .await
                .map_err(mysql_err)?;

                Ok(rows
                    .into_iter()
                    .map(|r| {
                        let name: String = r.get(0);
                        SqlObjectNode::new(
                            schema_id(DRIVER, &name),
                            name.clone(),
                            SqlObjectKind::Schema,
                            Some(name),
                            None,
                        )
                    })
                    .collect())
            })
        })
    }

    fn list_relations(
        &self,
        schema: &str,
        parent_id: &str,
    ) -> ConnectionResult<Vec<SqlObjectNode>> {
        let schema = schema.to_owned();
        let parent_id = parent_id.to_owned();
        self.session.with_pool(|pool| {
            runtime::block_on(async {
                let rows = sqlx::query(
                    "SELECT TABLE_NAME, TABLE_TYPE
                     FROM information_schema.TABLES
                     WHERE TABLE_SCHEMA = ?
                     ORDER BY TABLE_TYPE, TABLE_NAME",
                )
                .bind(&schema)
                .fetch_all(pool)
                .await
                .map_err(mysql_err)?;

                Ok(rows
                    .into_iter()
                    .filter_map(|r| {
                        let name: String = r.get(0);
                        let table_type: String = r.get(1);
                        let kind = match table_type.as_str() {
                            "VIEW" | "SYSTEM VIEW" => SqlObjectKind::View,
                            "BASE TABLE" => SqlObjectKind::Table,
                            _ => return None,
                        };
                        Some(SqlObjectNode::new(
                            relation_id(DRIVER, kind, &schema, &name),
                            name,
                            kind,
                            Some(schema.clone()),
                            Some(parent_id.clone()),
                        ))
                    })
                    .collect())
            })
        })
    }

    fn list_columns(
        &self,
        schema: &str,
        table: &str,
        parent_id: &str,
    ) -> ConnectionResult<Vec<SqlObjectNode>> {
        let desc = self.describe_relation(schema, table)?;
        Ok(desc
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

    fn describe_relation(&self, schema: &str, table: &str) -> ConnectionResult<TableSchema> {
        let schema = schema.to_owned();
        let table = table.to_owned();
        self.session.with_pool(|pool| {
            runtime::block_on(async {
                let rows = sqlx::query(
                    "SELECT COLUMN_NAME,
                            COLUMN_TYPE,
                            IS_NULLABLE,
                            COLUMN_KEY,
                            COLUMN_DEFAULT,
                            ORDINAL_POSITION
                     FROM information_schema.COLUMNS
                     WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
                     ORDER BY ORDINAL_POSITION",
                )
                .bind(&schema)
                .bind(&table)
                .fetch_all(pool)
                .await
                .map_err(mysql_err)?;

                if rows.is_empty() {
                    return Err(mysql_err(format!("relation {schema}.{table} not found")));
                }

                let mut columns = Vec::with_capacity(rows.len());
                let mut primary_keys = Vec::new();
                let mut pk_pos = 0i32;
                for r in rows {
                    let name: String = r.get(0);
                    let data_type: String = r.get(1);
                    let nullable: String = r.get(2);
                    let key: String = r.get(3);
                    let default_value: Option<String> = r.get(4);
                    let is_primary_key = key == "PRI";
                    if is_primary_key {
                        pk_pos += 1;
                        primary_keys.push(name.clone());
                    }
                    columns.push(ColumnMeta {
                        name,
                        data_type,
                        is_nullable: nullable.eq_ignore_ascii_case("YES"),
                        is_primary_key,
                        primary_key_position: if is_primary_key { Some(pk_pos) } else { None },
                        default_value,
                    });
                }

                Ok(TableSchema {
                    table_name: table,
                    schema: Some(schema),
                    columns,
                    primary_keys,
                })
            })
        })
    }
}

fn mysql_err(e: impl ToString) -> ConnectionError {
    ConnectionError::driver(DriverKind::Mysql, e.to_string())
}
