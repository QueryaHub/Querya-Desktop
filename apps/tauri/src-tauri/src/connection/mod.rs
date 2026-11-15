//! Shared connection layer for Querya drivers (SQLite first, then PG/MySQL/…).

mod error;
mod id;
mod introspect;
mod manager;
mod query;
mod sqlite;
mod sqlite_introspect;
pub(crate) mod sqlite_query;

pub use error::ConnectionError;
pub use id::{ConnectionId, DriverKind};
pub use introspect::{ColumnMeta, SchemaObject, SchemaObjectKind, TableSchema};
pub use manager::{ConnectionConfig, ConnectionManager, ConnectionRegistry};
#[allow(unused_imports)] // public API for later IPC / frontend issues
pub use manager::ConnectionSession;
pub use query::QueryEvent;
#[allow(unused_imports)] // public API for later IPC / frontend issues
pub use sqlite::{open_sqlite, SqliteSession};
