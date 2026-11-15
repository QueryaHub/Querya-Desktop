//! Shared connection layer for Querya drivers (SQLite first, then PG/MySQL/…).

mod error;
mod id;
mod introspect;
mod manager;
mod sqlite;
mod sqlite_introspect;

pub use error::ConnectionError;
pub use id::{ConnectionId, DriverKind};
pub use introspect::{ColumnMeta, SchemaObject, SchemaObjectKind, TableSchema};
pub use manager::{ConnectionConfig, ConnectionManager, ConnectionRegistry};
#[allow(unused_imports)] // public API for later IPC / frontend issues
pub use manager::ConnectionSession;
#[allow(unused_imports)] // public API for later IPC / frontend issues
pub use sqlite::{open_sqlite, SqliteSession};
