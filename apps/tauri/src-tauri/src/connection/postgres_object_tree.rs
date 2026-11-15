//! Postgres object tree: schemas → folders → objects (Flutter pg tree parity).

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use super::introspect::{ColumnMeta, TableSchema};
use super::object_tree::{
    column_id, folder_id, named_object_id, parse_object_id, relation_child_id, relation_id,
    schema_id, ObjectTreeProvider, ParsedObjectId, SchemaFolderKind, SqlObjectKind, SqlObjectNode,
};
use super::postgres::PostgresSession;
use super::runtime;
use sqlx::Row;
use std::fmt::Display;

fn postgres_err(e: impl Display) -> ConnectionError {
    ConnectionError::driver(DriverKind::Postgres, e.to_string())
}

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
                ParsedObjectId::Schema { schema, .. } => self.list_schema_folders(&schema),
                ParsedObjectId::Folder { schema, folder, .. } => {
                    self.list_folder_children(&schema, folder)
                }
                ParsedObjectId::Relation {
                    kind,
                    schema,
                    name,
                    ..
                } => self.list_columns_nodes(kind, &schema, &name),
                ParsedObjectId::Column { .. }
                | ParsedObjectId::Named { .. }
                | ParsedObjectId::RelationChild { .. } => Ok(vec![]),
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
                .map_err(postgres_err)?;

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

    fn list_schema_folders(&self, schema: &str) -> ConnectionResult<Vec<SqlObjectNode>> {
        let parent = schema_id(DriverKind::Postgres, schema);
        Ok(SchemaFolderKind::ALL
            .into_iter()
            .map(|folder| {
                SqlObjectNode::new(
                    folder_id(DriverKind::Postgres, schema, folder),
                    folder.label().to_owned(),
                    SqlObjectKind::Folder,
                    Some(schema.to_owned()),
                    Some(parent.clone()),
                )
            })
            .collect())
    }

    fn list_folder_children(
        &self,
        schema: &str,
        folder: SchemaFolderKind,
    ) -> ConnectionResult<Vec<SqlObjectNode>> {
        match folder {
            SchemaFolderKind::Tables => self.list_relations(schema, RelationFilter::Tables),
            SchemaFolderKind::Views => self.list_relations(schema, RelationFilter::Views),
            SchemaFolderKind::MaterializedViews => {
                self.list_relations(schema, RelationFilter::MaterializedViews)
            }
            SchemaFolderKind::Functions => self.list_named_objects(
                schema,
                "SELECT DISTINCT p.proname
                 FROM pg_proc p
                 JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = $1
                   AND p.prokind IN ('f', 'a', 'w')
                 ORDER BY p.proname",
                SchemaFolderKind::Functions,
                SqlObjectKind::Function,
            ),
            SchemaFolderKind::Sequences => self.list_named_objects(
                schema,
                "SELECT c.relname
                 FROM pg_class c
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = $1 AND c.relkind = 'S'
                 ORDER BY c.relname",
                SchemaFolderKind::Sequences,
                SqlObjectKind::Sequence,
            ),
            SchemaFolderKind::Indexes => self.list_relation_children(
                schema,
                "SELECT c.relname::text, i.relname::text
                 FROM pg_index x
                 JOIN pg_class c ON c.oid = x.indrelid
                 JOIN pg_class i ON i.oid = x.indexrelid
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = $1
                   AND c.relkind IN ('r', 'm', 'p')
                 ORDER BY c.relname, i.relname",
                SchemaFolderKind::Indexes,
                SqlObjectKind::Index,
            ),
            SchemaFolderKind::Triggers => self.list_relation_children(
                schema,
                "SELECT c.relname::text, t.tgname::text
                 FROM pg_trigger t
                 JOIN pg_class c ON c.oid = t.tgrelid
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = $1
                   AND NOT t.tgisinternal
                 ORDER BY c.relname, t.tgname",
                SchemaFolderKind::Triggers,
                SqlObjectKind::Trigger,
            ),
            SchemaFolderKind::Types => self.list_named_objects(
                schema,
                "SELECT t.typname::text
                 FROM pg_type t
                 JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE n.nspname = $1
                   AND t.typtype IN ('c', 'd', 'e', 'r', 'm')
                 ORDER BY t.typname",
                SchemaFolderKind::Types,
                SqlObjectKind::Type,
            ),
        }
    }

    fn list_relations(
        &self,
        schema: &str,
        filter: RelationFilter,
    ) -> ConnectionResult<Vec<SqlObjectNode>> {
        let schema_owned = schema.to_owned();
        let sql = match filter {
            RelationFilter::Tables => {
                "SELECT c.relname, c.relkind::text
                 FROM pg_class c
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = $1
                   AND c.relkind IN ('r', 'p')
                   AND NOT c.relispartition
                 ORDER BY c.relname"
            }
            RelationFilter::Views => {
                "SELECT c.relname, c.relkind::text
                 FROM pg_class c
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = $1
                   AND c.relkind = 'v'
                 ORDER BY c.relname"
            }
            RelationFilter::MaterializedViews => {
                "SELECT c.relname, c.relkind::text
                 FROM pg_class c
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = $1
                   AND c.relkind = 'm'
                 ORDER BY c.relname"
            }
        };
        self.session.with_pool(|pool| {
            runtime::block_on(async {
                let rows = sqlx::query(sql)
                    .bind(&schema_owned)
                    .fetch_all(pool)
                    .await
                    .map_err(postgres_err)?;

                let parent = folder_id(DriverKind::Postgres, &schema_owned, filter.folder());
                Ok(rows
                    .into_iter()
                    .map(|r| {
                        let name: String = r.get(0);
                        let relkind: String = r.get(1);
                        let kind = match relkind.as_str() {
                            "v" => SqlObjectKind::View,
                            "m" => SqlObjectKind::MaterializedView,
                            _ => SqlObjectKind::Table,
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

    fn list_named_objects(
        &self,
        schema: &str,
        sql: &str,
        folder: SchemaFolderKind,
        kind: SqlObjectKind,
    ) -> ConnectionResult<Vec<SqlObjectNode>> {
        let schema_owned = schema.to_owned();
        self.session.with_pool(|pool| {
            runtime::block_on(async {
                let rows = sqlx::query(sql)
                    .bind(&schema_owned)
                    .fetch_all(pool)
                    .await
                    .map_err(postgres_err)?;

                let parent = folder_id(DriverKind::Postgres, &schema_owned, folder);
                Ok(rows
                    .into_iter()
                    .map(|r| {
                        let name: String = r.get(0);
                        SqlObjectNode::new(
                            named_object_id(DriverKind::Postgres, kind, &schema_owned, &name),
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

    fn list_relation_children(
        &self,
        schema: &str,
        sql: &str,
        folder: SchemaFolderKind,
        kind: SqlObjectKind,
    ) -> ConnectionResult<Vec<SqlObjectNode>> {
        let schema_owned = schema.to_owned();
        self.session.with_pool(|pool| {
            runtime::block_on(async {
                let rows = sqlx::query(sql)
                    .bind(&schema_owned)
                    .fetch_all(pool)
                    .await
                    .map_err(postgres_err)?;

                let parent = folder_id(DriverKind::Postgres, &schema_owned, folder);
                Ok(rows
                    .into_iter()
                    .map(|r| {
                        let table: String = r.get(0);
                        let name: String = r.get(1);
                        let label = format!("{table}.{name}");
                        SqlObjectNode::new(
                            relation_child_id(
                                DriverKind::Postgres,
                                kind,
                                &schema_owned,
                                &table,
                                &name,
                            ),
                            label,
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
                .map_err(postgres_err)?;

                if rows.is_empty() {
                    return Err(postgres_err(format!("relation {schema}.{table} not found")));
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

enum RelationFilter {
    Tables,
    Views,
    MaterializedViews,
}

impl RelationFilter {
    fn folder(self) -> SchemaFolderKind {
        match self {
            Self::Tables => SchemaFolderKind::Tables,
            Self::Views => SchemaFolderKind::Views,
            Self::MaterializedViews => SchemaFolderKind::MaterializedViews,
        }
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

        let folders = tree.list_children(Some(&shop.id)).expect("folders");
        let names: Vec<_> = folders.iter().map(|f| f.name.as_str()).collect();
        assert!(names.contains(&"Tables"));
        assert!(names.contains(&"Functions"));
        assert!(names.contains(&"Indexes"));
        assert!(names.contains(&"Triggers"));
        assert!(folders.iter().all(|f| f.kind == SqlObjectKind::Folder));

        let tables_folder = folders.iter().find(|f| f.name == "Tables").unwrap();
        let tables = tree.list_children(Some(&tables_folder.id)).expect("tables");
        assert!(tables.iter().any(|r| r.name == "customers"));

        let customers = tables.iter().find(|r| r.name == "customers").unwrap();
        let cols = tree.list_children(Some(&customers.id)).expect("cols");
        assert!(cols.iter().any(|c| c.name == "id"));
        let desc = tree.describe(&customers.id).expect("describe");
        assert!(desc.primary_keys.iter().any(|k| k == "id"));

        let fn_folder = folders.iter().find(|f| f.name == "Functions").unwrap();
        let functions = tree.list_children(Some(&fn_folder.id)).expect("functions");
        assert!(
            !functions.is_empty(),
            "shop schema should expose functions in the tree"
        );
        assert!(functions.iter().all(|f| f.kind == SqlObjectKind::Function));

        let idx_folder = folders.iter().find(|f| f.name == "Indexes").unwrap();
        let indexes = tree.list_children(Some(&idx_folder.id)).expect("indexes");
        assert!(indexes.iter().any(|i| i.name.contains("customers")));
        assert!(indexes.iter().all(|i| i.kind == SqlObjectKind::Index));

        session.disconnect().ok();
    }
}
