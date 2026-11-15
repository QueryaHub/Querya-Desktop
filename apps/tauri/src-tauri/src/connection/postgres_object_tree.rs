//! Postgres object tree: schemas → tables/views → columns.

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use super::introspect::{ColumnMeta, TableSchema};
use super::object_tree::{
    column_id, parse_object_id, relation_id, schema_id, ObjectTreeProvider, ParsedObjectId,
    SqlObjectKind, SqlObjectNode,
};
use super::postgres::PostgresSession;
use super::runtime;
use sqlx::Row;

pub struct PostgresObjectTree {
    session: PostgresSession,
}

impl PostgresObjectTree {
    pub fn new(session: PostgresSession) -> Self {
        Self { session }
    }
}

impl ObjectTreeProvider for PostgresObjectTree {
    fn list_children(&self, parent_id: Option<&str>) -> ConnectionResult<Vec<SqlObjectNode>> {
        match parent_id {
            None => self.list_schemas(),
            Some(pid) => match parse_object_id(pid)? {
                ParsedObjectId::Schema { schema, .. } => self.list_relations(&schema),
                ParsedObjectId::Relation {
                    kind,
                    schema,
                    name,
                    ..
                } => self.list_columns_nodes(kind, &schema, &name),
                ParsedObjectId::Column { .. } => Ok(vec![]),
            },
        }
    }

    fn describe(&self, object_id: &str) -> ConnectionResult<TableSchema> {
        match parse_object_id(object_id)? {
            ParsedObjectId::Relation { schema, name, .. } => self.describe_relation(&schema, &name),
            _ => Err(ConnectionError::invalid_config(
                "describe expects table or view id",
            )),
        }
    }
}

impl PostgresObjectTree {
    fn list_schemas(&self) -> ConnectionResult<Vec<SqlObjectNode>> {
        self.session.with_pool(|pool| {
            runtime::block_on(async {
                let rows = sqlx::query(
                    "SELECT nspname
                     FROM pg_namespace
                     WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
                       AND nspname NOT LIKE 'pg\\_temp%' ESCAPE '\\'
                       AND nspname NOT LIKE 'pg\\_toast\\_temp%' ESCAPE '\\'
                     ORDER BY nspname",
                )
                .fetch_all(pool)
                .await
                .map_err(|e| ConnectionError::driver(DriverKind::Postgres, e.to_string()))?;

                Ok(rows
                    .into_iter()
                    .map(|r| {
                        let name: String = r.get(0);
                        SqlObjectNode::new(
                            schema_id(DriverKind::Postgres, &name),
                            name,
                            SqlObjectKind::Schema,
                            None,
                            None,
                        )
                    })
                    .collect())
            })
        })
    }

    fn list_relations(&self, schema: &str) -> ConnectionResult<Vec<SqlObjectNode>> {
        let schema_owned = schema.to_owned();
        self.session.with_pool(|pool| {
            runtime::block_on(async {
                let rows = sqlx::query(
                    "SELECT c.relname,
                            CASE c.relkind WHEN 'v' THEN 'view' WHEN 'm' THEN 'view' ELSE 'table' END
                     FROM pg_class c
                     JOIN pg_namespace n ON n.oid = c.relnamespace
                     WHERE n.nspname = $1
                       AND c.relkind IN ('r', 'p', 'v', 'm')
                       AND NOT c.relispartition
                     ORDER BY c.relname",
                )
                .bind(&schema_owned)
                .fetch_all(pool)
                .await
                .map_err(|e| ConnectionError::driver(DriverKind::Postgres, e.to_string()))?;

                let parent = schema_id(DriverKind::Postgres, &schema_owned);
                Ok(rows
                    .into_iter()
                    .map(|r| {
                        let name: String = r.get(0);
                        let kind_s: String = r.get(1);
                        let kind = if kind_s == "view" {
                            SqlObjectKind::View
                        } else {
                            SqlObjectKind::Table
                        };
                        SqlObjectNode::new(
                            relation_id(DriverKind::Postgres, kind, &schema_owned, &name),
                            name,
                            kind,
                            Some(schema_owned.clone()),
                            Some(parent.clone()),
                        )
                    })
                    .collect())
            })
        })
    }

    fn list_columns_nodes(
        &self,
        kind: SqlObjectKind,
        schema: &str,
        table: &str,
    ) -> ConnectionResult<Vec<SqlObjectNode>> {
        let desc = self.describe_relation(schema, table)?;
        let parent = relation_id(DriverKind::Postgres, kind, schema, table);
        Ok(desc
            .columns
            .into_iter()
            .map(|c| {
                SqlObjectNode::new(
                    column_id(DriverKind::Postgres, schema, table, &c.name),
                    c.name,
                    SqlObjectKind::Column,
                    Some(schema.to_owned()),
                    Some(parent.clone()),
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
                    "SELECT a.attname,
                            pg_catalog.format_type(a.atttypid, a.atttypmod),
                            NOT a.attnotnull,
                            COALESCE(
                              (SELECT a2.attnum
                               FROM pg_index i
                               JOIN pg_attribute a2
                                 ON a2.attrelid = i.indrelid AND a2.attnum = ANY (i.indkey)
                               WHERE i.indrelid = c.oid AND i.indisprimary AND a2.attname = a.attname
                               LIMIT 1),
                              0
                            ) AS pk_pos,
                            pg_get_expr(ad.adbin, ad.adrelid)
                     FROM pg_attribute a
                     JOIN pg_class c ON c.oid = a.attrelid
                     JOIN pg_namespace n ON n.oid = c.relnamespace
                     LEFT JOIN pg_attrdef ad
                       ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
                     WHERE n.nspname = $1
                       AND c.relname = $2
                       AND a.attnum > 0
                       AND NOT a.attisdropped
                     ORDER BY a.attnum",
                )
                .bind(&schema)
                .bind(&table)
                .fetch_all(pool)
                .await
                .map_err(|e| ConnectionError::driver(DriverKind::Postgres, e.to_string()))?;

                if rows.is_empty() {
                    return Err(ConnectionError::driver(
                        DriverKind::Postgres,
                        format!("relation {schema}.{table} not found"),
                    ));
                }

                let mut columns = Vec::with_capacity(rows.len());
                let mut primary_keys = Vec::new();
                for r in rows {
                    let name: String = r.get(0);
                    let data_type: String = r.get(1);
                    let is_nullable: bool = r.get(2);
                    let pk_pos: i32 = r.get(3);
                    let default_value: Option<String> = r.get(4);
                    let is_primary_key = pk_pos > 0;
                    if is_primary_key {
                        primary_keys.push(name.clone());
                    }
                    columns.push(ColumnMeta {
                        name,
                        data_type,
                        is_nullable,
                        is_primary_key,
                        primary_key_position: if is_primary_key {
                            Some(pk_pos)
                        } else {
                            None
                        },
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::connection::manager::ConnectionSession;
    use crate::connection::postgres::{open_postgres, PostgresConnectParams};

    fn live_session() -> Option<PostgresSession> {
        if std::env::var_os("QUERYA_SKIP_PG").is_some() {
            return None;
        }
        open_postgres(PostgresConnectParams {
            host: "127.0.0.1".into(),
            port: 5432,
            database: "querya".into(),
            user: "querya".into(),
            password: Some("querya".into()),
            id: None,
        })
        .ok()
    }

    #[test]
    fn live_postgres_tree_shop_schema() {
        let Some(session) = live_session() else {
            return;
        };
        let tree = PostgresObjectTree::new(session.clone_handle());
        let schemas = tree.list_children(None).expect("schemas");
        assert!(schemas.iter().any(|s| s.name == "shop"));
        let shop = schemas.iter().find(|s| s.name == "shop").unwrap();
        let rels = tree.list_children(Some(&shop.id)).expect("rels");
        assert!(rels.iter().any(|r| r.name == "customers"));
        let customers = rels.iter().find(|r| r.name == "customers").unwrap();
        let cols = tree.list_children(Some(&customers.id)).expect("cols");
        assert!(cols.iter().any(|c| c.name == "id"));
        let desc = tree.describe(&customers.id).expect("describe");
        assert!(desc.primary_keys.iter().any(|k| k == "id"));
        session.disconnect().ok();
    }
}
