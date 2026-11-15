//! Shared connection layer for Querya drivers (SQLite first, then PG/MySQL/…).

mod error;
mod id;
mod manager;
mod sqlite;

pub use error::ConnectionError;
pub use id::{ConnectionId, DriverKind};
pub use manager::{ConnectionConfig, ConnectionManager, ConnectionRegistry};
#[allow(unused_imports)] // public API for later IPC / introspection issues
pub use manager::ConnectionSession;
#[allow(unused_imports)] // public API for later IPC / introspection issues
pub use sqlite::{open_sqlite, SqliteSession};
