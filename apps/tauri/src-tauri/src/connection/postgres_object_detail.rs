//! Postgres object detail payloads (Flutter browser / routine / sequence parity).

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use super::object_tree::{
    parse_object_id, ParsedObjectId, SchemaFolderKind, SqlObjectKind,
};
use super::postgres::PostgresSession;
use super::runtime;
use serde::Serialize;
use sqlx::Row;
use std::fmt::Display;

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum PostgresObjectDetail {
    Function {
        schema: String,
        name: String,
        overloads: Vec<FunctionOverload>,
    },
    Sequence {
        schema: String,
        name: String,
        last_value: String,
        start_value: String,
        min_value: String,
        max_value: String,
        increment_by: String,
        cache_size: String,
        cycle: bool,
        ddl: String,
    },
    Index {
        schema: String,
        table: String,
        name: String,
        definition: String,
        size_bytes: i64,
    },
    Trigger {
        schema: String,
        table: String,
        name: String,
        definition: String,
    },
    Type {
        schema: String,
        name: String,
        type_kind: String,
    },
    SchemaIndexes {
        schema: String,
        rows: Vec<IndexListRow>,
    },
    SchemaTriggers {
        schema: String,
        rows: Vec<TriggerListRow>,
    },
    SchemaTypes {
        schema: String,
        rows: Vec<TypeListRow>,
    },
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct FunctionOverload {
    pub signature: String,
    pub definition: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct IndexListRow {
    pub table_name: String,
    pub index_name: String,
    pub definition: String,
    pub size_bytes: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct TriggerListRow {
    pub table_name: String,
    pub trigger_name: String,
    pub definition: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct TypeListRow {
    pub name: String,
    pub type_kind: String,
}

fn postgres_err(message: impl Display) -> ConnectionError {
    ConnectionError::driver(DriverKind::Postgres, message.to_string())
}

fn require_row<T>(row: Option<T>, message: impl Display) -> ConnectionResult<T> {
    row.ok_or_else(|| postgres_err(message))
}

/// Resolve a tree object id into a detail payload.
pub fn fetch_detail(
    session: &PostgresSession,
    object_id: &str,
) -> ConnectionResult<PostgresObjectDetail> {
    match parse_object_id(object_id)? {
        ParsedObjectId::Named {
            kind: SqlObjectKind::Function,
            schema,
            name,
            ..
        } => fetch_function(session, &schema, &name),
        ParsedObjectId::Named {
            kind: SqlObjectKind::Sequence,
            schema,
            name,
            ..
        } => fetch_sequence(session, &schema, &name),
        ParsedObjectId::Named {
            kind: SqlObjectKind::Type,
            schema,
            name,
            ..
        } => fetch_type(session, &schema, &name),
        ParsedObjectId::RelationChild {
            kind: SqlObjectKind::Index,
            schema,
            table,
            name,
            ..
        } => fetch_index(session, &schema, &table, &name),
        ParsedObjectId::RelationChild {
            kind: SqlObjectKind::Trigger,
            schema,
            table,
            name,
            ..
        } => fetch_trigger(session, &schema, &table, &name),
        ParsedObjectId::Folder {
            schema,
            folder: SchemaFolderKind::Indexes,
            ..
        } => fetch_schema_indexes(session, &schema),
        ParsedObjectId::Folder {
            schema,
            folder: SchemaFolderKind::Triggers,
            ..
        } => fetch_schema_triggers(session, &schema),
        ParsedObjectId::Folder {
            schema,
            folder: SchemaFolderKind::Types,
            ..
        } => fetch_schema_types(session, &schema),
        _ => Err(ConnectionError::invalid_config(
            "object detail expects function, sequence, type, index, trigger, or Indexes/Triggers/Types folder",
        )),
    }
}

fn fetch_function(
    session: &PostgresSession,
    schema: &str,
    name: &str,
) -> ConnectionResult<PostgresObjectDetail> {
    let schema = schema.to_owned();
    let name = name.to_owned();
    session.with_pool(|pool| {
        runtime::block_on(async {
            let rows = sqlx::query(
                "SELECT p.oid::regprocedure::text AS signature,
                        pg_get_functiondef(p.oid)::text AS definition
                 FROM pg_proc p
                 JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = $1 AND p.proname = $2
                 ORDER BY p.oid",
            )
            .bind(&schema)
            .bind(&name)
            .fetch_all(pool)
            .await
            .map_err(postgres_err)?;

            let overloads = rows
                .into_iter()
                .map(|r| FunctionOverload {
                    signature: r.get(0),
                    definition: r.get(1),
                })
                .collect::<Vec<_>>();
            if overloads.is_empty() {
                return Err(postgres_err(format!("function {schema}.{name} not found")));
            }
            Ok(PostgresObjectDetail::Function {
                schema,
                name,
                overloads,
            })
        })
    })
}

fn fetch_sequence(
    session: &PostgresSession,
    schema: &str,
    name: &str,
) -> ConnectionResult<PostgresObjectDetail> {
    let schema = schema.to_owned();
    let name = name.to_owned();
    session.with_pool(|pool| {
        runtime::block_on(async {
            let row = sqlx::query(
                "SELECT last_value::text, start_value::text, min_value::text, max_value::text,
                        increment_by::text, cycle, cache_size::text,
                        schemaname::text, sequencename::text
                 FROM pg_sequences
                 WHERE schemaname = $1 AND sequencename = $2",
            )
            .bind(&schema)
            .bind(&name)
            .fetch_optional(pool)
            .await
            .map_err(postgres_err)?;
            let row = require_row(row, format!("sequence {schema}.{name} not found"))?;

            let last_value: String = row.get(0);
            let start_value: String = row.get(1);
            let min_value: String = row.get(2);
            let max_value: String = row.get(3);
            let increment_by: String = row.get(4);
            let cycle: bool = row.get(5);
            let cache_size: String = row.get(6);
            let sc: String = row.get(7);
            let seq: String = row.get(8);
            let ddl = format!(
                "CREATE SEQUENCE {sc}.{seq}\n    INCREMENT BY {increment_by}\n    MINVALUE {min_value}\n    MAXVALUE {max_value}\n    START {start_value}\n    CACHE {cache_size}{}",
                if cycle { "\n    CYCLE" } else { "" }
            );
            Ok(PostgresObjectDetail::Sequence {
                schema: sc,
                name: seq,
                last_value,
                start_value,
                min_value,
                max_value,
                increment_by,
                cache_size,
                cycle,
                ddl,
            })
        })
    })
}

fn fetch_type(
    session: &PostgresSession,
    schema: &str,
    name: &str,
) -> ConnectionResult<PostgresObjectDetail> {
    let schema = schema.to_owned();
    let name = name.to_owned();
    session.with_pool(|pool| {
        runtime::block_on(async {
            let row = sqlx::query(
                "SELECT t.typname::text,
                        CASE t.typtype
                          WHEN 'b' THEN 'base'
                          WHEN 'c' THEN 'composite'
                          WHEN 'd' THEN 'domain'
                          WHEN 'e' THEN 'enum'
                          WHEN 'p' THEN 'pseudo'
                          WHEN 'r' THEN 'range'
                          WHEN 'm' THEN 'multirange'
                          ELSE t.typtype::text
                        END
                 FROM pg_type t
                 JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE n.nspname = $1 AND t.typname = $2",
            )
            .bind(&schema)
            .bind(&name)
            .fetch_optional(pool)
            .await
            .map_err(postgres_err)?;
            let row = require_row(row, format!("type {schema}.{name} not found"))?;
            Ok(PostgresObjectDetail::Type {
                schema,
                name: row.get(0),
                type_kind: row.get(1),
            })
        })
    })
}

fn fetch_index(
    session: &PostgresSession,
    schema: &str,
    table: &str,
    name: &str,
) -> ConnectionResult<PostgresObjectDetail> {
    let schema = schema.to_owned();
    let table = table.to_owned();
    let name = name.to_owned();
    session.with_pool(|pool| {
        runtime::block_on(async {
            let row = sqlx::query(
                "SELECT c.relname::text,
                        i.relname::text,
                        COALESCE(pg_relation_size(i.oid), 0)::bigint,
                        pg_get_indexdef(i.oid)::text
                 FROM pg_index x
                 JOIN pg_class c ON c.oid = x.indrelid
                 JOIN pg_class i ON i.oid = x.indexrelid
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = $1 AND c.relname = $2 AND i.relname = $3",
            )
            .bind(&schema)
            .bind(&table)
            .bind(&name)
            .fetch_optional(pool)
            .await
            .map_err(postgres_err)?;
            let row = require_row(row, format!("index {schema}.{table}.{name} not found"))?;
            Ok(PostgresObjectDetail::Index {
                schema,
                table: row.get(0),
                name: row.get(1),
                size_bytes: row.get(2),
                definition: row.get(3),
            })
        })
    })
}

fn fetch_trigger(
    session: &PostgresSession,
    schema: &str,
    table: &str,
    name: &str,
) -> ConnectionResult<PostgresObjectDetail> {
    let schema = schema.to_owned();
    let table = table.to_owned();
    let name = name.to_owned();
    session.with_pool(|pool| {
        runtime::block_on(async {
            let row = sqlx::query(
                "SELECT c.relname::text,
                        t.tgname::text,
                        pg_get_triggerdef(t.oid)::text
                 FROM pg_trigger t
                 JOIN pg_class c ON c.oid = t.tgrelid
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = $1 AND c.relname = $2 AND t.tgname = $3
                   AND NOT t.tgisinternal",
            )
            .bind(&schema)
            .bind(&table)
            .bind(&name)
            .fetch_optional(pool)
            .await
            .map_err(postgres_err)?;
            let row = require_row(row, format!("trigger {schema}.{table}.{name} not found"))?;
            Ok(PostgresObjectDetail::Trigger {
                schema,
                table: row.get(0),
                name: row.get(1),
                definition: row.get(2),
            })
        })
    })
}

fn fetch_schema_indexes(
    session: &PostgresSession,
    schema: &str,
) -> ConnectionResult<PostgresObjectDetail> {
    let schema = schema.to_owned();
    session.with_pool(|pool| {
        runtime::block_on(async {
            let rows = sqlx::query(
                "SELECT c.relname::text,
                        i.relname::text,
                        COALESCE(pg_relation_size(i.oid), 0)::bigint,
                        pg_get_indexdef(i.oid)::text
                 FROM pg_index x
                 JOIN pg_class c ON c.oid = x.indrelid
                 JOIN pg_class i ON i.oid = x.indexrelid
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = $1
                   AND c.relkind IN ('r', 'm', 'p')
                 ORDER BY c.relname, i.relname",
            )
            .bind(&schema)
            .fetch_all(pool)
            .await
            .map_err(postgres_err)?;
            Ok(PostgresObjectDetail::SchemaIndexes {
                schema,
                rows: rows
                    .into_iter()
                    .map(|r| IndexListRow {
                        table_name: r.get(0),
                        index_name: r.get(1),
                        size_bytes: r.get(2),
                        definition: r.get(3),
                    })
                    .collect(),
            })
        })
    })
}

fn fetch_schema_triggers(
    session: &PostgresSession,
    schema: &str,
) -> ConnectionResult<PostgresObjectDetail> {
    let schema = schema.to_owned();
    session.with_pool(|pool| {
        runtime::block_on(async {
            let rows = sqlx::query(
                "SELECT c.relname::text,
                        t.tgname::text,
                        pg_get_triggerdef(t.oid)::text
                 FROM pg_trigger t
                 JOIN pg_class c ON c.oid = t.tgrelid
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = $1
                   AND NOT t.tgisinternal
                 ORDER BY c.relname, t.tgname",
            )
            .bind(&schema)
            .fetch_all(pool)
            .await
            .map_err(postgres_err)?;
            Ok(PostgresObjectDetail::SchemaTriggers {
                schema,
                rows: rows
                    .into_iter()
                    .map(|r| TriggerListRow {
                        table_name: r.get(0),
                        trigger_name: r.get(1),
                        definition: r.get(2),
                    })
                    .collect(),
            })
        })
    })
}

fn fetch_schema_types(
    session: &PostgresSession,
    schema: &str,
) -> ConnectionResult<PostgresObjectDetail> {
    let schema = schema.to_owned();
    session.with_pool(|pool| {
        runtime::block_on(async {
            let rows = sqlx::query(
                "SELECT t.typname::text,
                        CASE t.typtype
                          WHEN 'c' THEN 'composite'
                          WHEN 'd' THEN 'domain'
                          WHEN 'e' THEN 'enum'
                          WHEN 'r' THEN 'range'
                          WHEN 'm' THEN 'multirange'
                          ELSE t.typtype::text
                        END
                 FROM pg_type t
                 JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE n.nspname = $1
                   AND t.typtype IN ('c', 'd', 'e', 'r', 'm')
                 ORDER BY t.typname",
            )
            .bind(&schema)
            .fetch_all(pool)
            .await
            .map_err(postgres_err)?;
            Ok(PostgresObjectDetail::SchemaTypes {
                schema,
                rows: rows
                    .into_iter()
                    .map(|r| TypeListRow {
                        name: r.get(0),
                        type_kind: r.get(1),
                    })
                    .collect(),
            })
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::connection::manager::ConnectionSession;
    use crate::connection::object_tree::{folder_id, ObjectTreeProvider, SchemaFolderKind};
    use crate::connection::postgres::{open_postgres, PostgresConnectParams};
    use crate::connection::postgres_object_tree::PostgresObjectTree;

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
    fn live_shop_function_and_indexes_folder() {
        let Some(session) = live_session() else {
            return;
        };
        let funcs = PostgresObjectTree::new(session.clone_handle());
        let folder = folder_id(DriverKind::Postgres, "shop", SchemaFolderKind::Functions);
        let children = funcs.list_children(Some(&folder)).expect("functions");
        let Some(first) = children.first() else {
            session.disconnect().ok();
            return;
        };
        let detail = fetch_detail(&session, &first.id).expect("function detail");
        match detail {
            PostgresObjectDetail::Function { overloads, .. } => {
                assert!(!overloads.is_empty());
                assert!(!overloads[0].definition.is_empty());
            }
            other => panic!("expected Function, got {other:?}"),
        }

        let idx_folder = folder_id(DriverKind::Postgres, "shop", SchemaFolderKind::Indexes);
        let indexes = fetch_detail(&session, &idx_folder).expect("indexes");
        match indexes {
            PostgresObjectDetail::SchemaIndexes { rows, .. } => {
                assert!(!rows.is_empty());
            }
            other => panic!("expected SchemaIndexes, got {other:?}"),
        }

        session.disconnect().ok();
    }
}
