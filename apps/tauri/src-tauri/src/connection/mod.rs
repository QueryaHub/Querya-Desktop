//! Shared connection layer for Querya drivers (SQLite first, then PG/MySQL/…).

mod error;
mod id;
mod introspect;
mod manager;
mod query;
mod smoke_slice;
mod sqlite;
mod sqlite_introspect;
pub(crate) mod sqlite_query;

pub use error::ConnectionError;
pub use id::{ConnectionId, DriverKind};
pub use introspect::{ColumnMeta, SchemaObject, SchemaObjectKind, TableSchema};
pub use manager::{ConnectionConfig, ConnectionManager, ConnectionRegistry};
pub use query::QueryEvent;
