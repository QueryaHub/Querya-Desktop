use serde::{Deserialize, Serialize};
use std::fmt;
use uuid::Uuid;

/// Opaque live-connection handle shared across IPC and drivers.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ConnectionId(String);

impl ConnectionId {
    pub fn new() -> Self {
        Self(Uuid::new_v4().to_string())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Default for ConnectionId {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Display for ConnectionId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl From<String> for ConnectionId {
    fn from(value: String) -> Self {
        Self(value)
    }
}

impl From<&str> for ConnectionId {
    fn from(value: &str) -> Self {
        Self(value.to_owned())
    }
}

/// Driver family — mirrors Flutter connection `type` strings.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DriverKind {
    Sqlite,
    Postgres,
    Mysql,
    Redis,
    Mongodb,
}

impl DriverKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Sqlite => "sqlite",
            Self::Postgres => "postgres",
            Self::Mysql => "mysql",
            Self::Redis => "redis",
            Self::Mongodb => "mongodb",
        }
    }
}

impl fmt::Display for DriverKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn connection_id_round_trips_json() {
        let id = ConnectionId::from("abc-123");
        let json = serde_json::to_string(&id).unwrap();
        assert_eq!(json, "\"abc-123\"");
        let back: ConnectionId = serde_json::from_str(&json).unwrap();
        assert_eq!(back, id);
    }

    #[test]
    fn driver_kind_serde() {
        let json = serde_json::to_string(&DriverKind::Sqlite).unwrap();
        assert_eq!(json, "\"sqlite\"");
    }
}
