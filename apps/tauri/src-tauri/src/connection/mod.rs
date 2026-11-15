//! Shared connection layer for Querya drivers (SQLite first, then PG/MySQL/…).

mod erd;
mod error;
mod id;
mod introspect;
pub(crate) mod manager;
pub(crate) mod mysql;
mod mysql_object_tree;
pub(crate) mod mysql_query;
mod object_tree;
pub(crate) mod postgres;
mod postgres_erd;
mod postgres_object_detail;
mod postgres_object_tree;
pub(crate) mod postgres_query;
mod query;
pub(crate) mod redis;
pub(crate) mod runtime;
mod smoke_slice;
mod sql_guard;
mod sqlite;
mod sqlite_erd;
mod sqlite_introspect;
mod sqlite_object_tree;
pub(crate) mod sqlite_query;

pub use erd::{ErdColumn, ErdRelation, ErdSchema, ErdTable};
pub use error::ConnectionError;
pub use id::{ConnectionId, DriverKind};
pub use introspect::{ColumnMeta, SchemaObject, SchemaObjectKind, TableSchema};
pub use manager::{ConnectionConfig, ConnectionManager, ConnectionRegistry};
pub use object_tree::{ObjectTreeProvider, SqlObjectKind, SqlObjectNode};
pub use postgres_object_detail::PostgresObjectDetail;
pub use query::QueryEvent;
pub use redis::RedisScanPage;
pub use sqlite_introspect::SqliteOverview;
