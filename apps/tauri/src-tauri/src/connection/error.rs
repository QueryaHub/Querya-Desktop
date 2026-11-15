use super::id::{ConnectionId, DriverKind};
use serde::Serialize;
use std::fmt;

/// Typed connection failures exposed over Tauri IPC.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ConnectionError {
    NotFound { id: ConnectionId },
    AlreadyConnected { id: ConnectionId },
    Disconnected { id: ConnectionId },
    InvalidConfig { message: String },
    UnsupportedDriver { driver: DriverKind },
    Io { message: String },
    Driver { driver: DriverKind, message: String },
}

impl ConnectionError {
    pub fn invalid_config(message: impl Into<String>) -> Self {
        Self::InvalidConfig {
            message: message.into(),
        }
    }

    pub fn io(message: impl Into<String>) -> Self {
        Self::Io {
            message: message.into(),
        }
    }

    pub fn driver(driver: DriverKind, message: impl Into<String>) -> Self {
        Self::Driver {
            driver,
            message: message.into(),
        }
    }
}

impl fmt::Display for ConnectionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFound { id } => write!(f, "connection not found: {id}"),
            Self::AlreadyConnected { id } => write!(f, "already connected: {id}"),
            Self::Disconnected { id } => write!(f, "connection closed: {id}"),
            Self::InvalidConfig { message } => write!(f, "invalid config: {message}"),
            Self::UnsupportedDriver { driver } => {
                write!(f, "unsupported driver: {driver}")
            }
            Self::Io { message } => write!(f, "io error: {message}"),
            Self::Driver { driver, message } => {
                write!(f, "{driver} error: {message}")
            }
        }
    }
}

impl std::error::Error for ConnectionError {}

impl From<rusqlite::Error> for ConnectionError {
    fn from(value: rusqlite::Error) -> Self {
        Self::driver(DriverKind::Sqlite, value.to_string())
    }
}

/// IPC-friendly result alias.
pub type ConnectionResult<T> = Result<T, ConnectionError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_and_serde_not_found() {
        let err = ConnectionError::NotFound {
            id: ConnectionId::from("c1"),
        };
        assert_eq!(err.to_string(), "connection not found: c1");
        let json = serde_json::to_value(&err).unwrap();
        assert_eq!(json["kind"], "not_found");
        assert_eq!(json["id"], "c1");
    }

    #[test]
    fn display_driver() {
        let err = ConnectionError::driver(DriverKind::Sqlite, "no such table");
        assert_eq!(err.to_string(), "sqlite error: no such table");
    }

    #[test]
    fn from_rusqlite() {
        let err: ConnectionError = rusqlite::Error::InvalidQuery.into();
        assert!(matches!(
            err,
            ConnectionError::Driver {
                driver: DriverKind::Sqlite,
                ..
            }
        ));
    }
}
