use super::error::{ConnectionError, ConnectionResult};
use super::id::{ConnectionId, DriverKind};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

/// Driver-agnostic connect parameters (tagged for IPC).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "driver", rename_all = "snake_case")]
pub enum ConnectionConfig {
    Sqlite {
        /// Absolute or relative path to a `.db` / `.sqlite` file.
        path: String,
    },
    Postgres {
        host: String,
        port: u16,
        database: String,
        user: String,
        /// Secret is resolved via keyring later; optional here for stubs.
        password: Option<String>,
    },
    Mysql {
        host: String,
        port: u16,
        database: String,
        user: String,
        password: Option<String>,
    },
}

impl ConnectionConfig {
    pub fn driver_kind(&self) -> DriverKind {
        match self {
            Self::Sqlite { .. } => DriverKind::Sqlite,
            Self::Postgres { .. } => DriverKind::Postgres,
            Self::Mysql { .. } => DriverKind::Mysql,
        }
    }
}

/// Live session handle — drivers implement this behind the registry.
pub trait ConnectionSession: Send + Sync {
    fn id(&self) -> &ConnectionId;
    fn driver(&self) -> DriverKind;
    fn disconnect(&mut self) -> ConnectionResult<()>;
}

/// Opens and tracks live DB sessions.
pub trait ConnectionManager: Send + Sync {
    fn connect(&self, config: ConnectionConfig) -> ConnectionResult<ConnectionId>;
    fn disconnect(&self, id: &ConnectionId) -> ConnectionResult<()>;
    fn is_connected(&self, id: &ConnectionId) -> bool;
    fn driver_of(&self, id: &ConnectionId) -> Option<DriverKind>;
}

type SessionBox = Box<dyn ConnectionSession>;

/// In-memory registry used by Tauri commands. Drivers register factories later.
#[derive(Default)]
pub struct ConnectionRegistry {
    sessions: Mutex<HashMap<ConnectionId, SessionBox>>,
    /// Optional opener for tests / driver wiring. Returns a live session.
    opener: Option<Arc<dyn Fn(ConnectionConfig) -> ConnectionResult<SessionBox> + Send + Sync>>,
}

impl ConnectionRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_opener<F>(opener: F) -> Self
    where
        F: Fn(ConnectionConfig) -> ConnectionResult<SessionBox> + Send + Sync + 'static,
    {
        Self {
            sessions: Mutex::new(HashMap::new()),
            opener: Some(Arc::new(opener)),
        }
    }

    fn lock(
        &self,
    ) -> ConnectionResult<std::sync::MutexGuard<'_, HashMap<ConnectionId, SessionBox>>> {
        self.sessions
            .lock()
            .map_err(|_| ConnectionError::io("connection registry lock poisoned"))
    }
}

impl ConnectionManager for ConnectionRegistry {
    fn connect(&self, config: ConnectionConfig) -> ConnectionResult<ConnectionId> {
        let opener = self
            .opener
            .as_ref()
            .ok_or(ConnectionError::UnsupportedDriver {
                driver: config.driver_kind(),
            })?;
        let session = opener(config)?;
        let id = session.id().clone();
        let mut map = self.lock()?;
        if map.contains_key(&id) {
            return Err(ConnectionError::AlreadyConnected { id });
        }
        map.insert(id.clone(), session);
        Ok(id)
    }

    fn disconnect(&self, id: &ConnectionId) -> ConnectionResult<()> {
        let mut map = self.lock()?;
        let mut session = map
            .remove(id)
            .ok_or_else(|| ConnectionError::NotFound { id: id.clone() })?;
        session.disconnect()?;
        Ok(())
    }

    fn is_connected(&self, id: &ConnectionId) -> bool {
        self.lock().map(|m| m.contains_key(id)).unwrap_or(false)
    }

    fn driver_of(&self, id: &ConnectionId) -> Option<DriverKind> {
        self.lock().ok()?.get(id).map(|s| s.driver())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FakeSession {
        id: ConnectionId,
        driver: DriverKind,
        closed: bool,
    }

    impl ConnectionSession for FakeSession {
        fn id(&self) -> &ConnectionId {
            &self.id
        }
        fn driver(&self) -> DriverKind {
            self.driver
        }
        fn disconnect(&mut self) -> ConnectionResult<()> {
            self.closed = true;
            Ok(())
        }
    }

    #[test]
    fn registry_connect_disconnect() {
        let reg = ConnectionRegistry::with_opener(|cfg| {
            assert!(matches!(cfg, ConnectionConfig::Sqlite { .. }));
            Ok(Box::new(FakeSession {
                id: ConnectionId::from("s1"),
                driver: DriverKind::Sqlite,
                closed: false,
            }))
        });

        let id = reg
            .connect(ConnectionConfig::Sqlite {
                path: "/tmp/x.db".into(),
            })
            .unwrap();
        assert_eq!(id.as_str(), "s1");
        assert!(reg.is_connected(&id));
        assert_eq!(reg.driver_of(&id), Some(DriverKind::Sqlite));
        reg.disconnect(&id).unwrap();
        assert!(!reg.is_connected(&id));
        let err = reg.disconnect(&id).unwrap_err();
        assert!(matches!(err, ConnectionError::NotFound { .. }));
    }

    #[test]
    fn registry_without_opener_is_unsupported() {
        let reg = ConnectionRegistry::new();
        let err = reg
            .connect(ConnectionConfig::Sqlite {
                path: "a.db".into(),
            })
            .unwrap_err();
        assert!(matches!(
            err,
            ConnectionError::UnsupportedDriver {
                driver: DriverKind::Sqlite
            }
        ));
    }
}
