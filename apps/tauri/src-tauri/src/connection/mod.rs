//! Shared connection layer for Querya drivers (SQLite first, then PG/MySQL/…).

mod error;
mod id;
mod manager;

pub use error::ConnectionError;
pub use id::{ConnectionId, DriverKind};
pub use manager::{ConnectionConfig, ConnectionManager, ConnectionRegistry};
