use super::error::{ConnectionError, ConnectionResult};
use super::id::{ConnectionId, DriverKind};
use super::sqlite::SqliteSession;
use serde::{Deserialize, Serialize};
use std::any::Any;
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
    /// Downcast hook for driver-specific APIs (introspection, query).
    fn as_any(&self) -> &dyn Any;
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
pub struct ConnectionRegistry {
    sessions: Mutex<HashMap<ConnectionId, SessionBox>>,
    /// Optional opener for tests / driver wiring. Returns a live session.
    opener: Option<Arc<dyn Fn(ConnectionConfig) -> ConnectionResult<SessionBox> + Send + Sync>>,
}

impl Default for ConnectionRegistry {
    fn default() -> Self {
        Self::with_builtin_drivers()
    }
}

impl ConnectionRegistry {
    pub fn new() -> Self {
        Self::with_builtin_drivers()
    }

    /// Registry with SQLite opener wired (PG/MySQL return UnsupportedDriver).
    pub fn with_builtin_drivers() -> Self {
        Self::with_opener(|config| match config {
            ConnectionConfig::Sqlite { path } => super::sqlite::open_sqlite(path),
            other => Err(ConnectionError::UnsupportedDriver {
                driver: other.driver_kind(),
            }),
        })
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

    /// Run a closure against a live [`SqliteSession`].
    pub fn with_sqlite<T>(
        &self,
        id: &ConnectionId,
        f: impl FnOnce(&SqliteSession) -> ConnectionResult<T>,
    ) -> ConnectionResult<T> {
        let map = self.lock()?;
        let session = map
            .get(id)
            .ok_or_else(|| ConnectionError::NotFound { id: id.clone() })?;
        let sqlite = session
            .as_any()
            .downcast_ref::<SqliteSession>()
            .ok_or(ConnectionError::UnsupportedDriver {
                driver: session.driver(),
            })?;
        f(sqlite)
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
        fn as_any(&self) -> &dyn Any {
            self
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
    fn registry_postgres_is_unsupported_for_now() {
        let reg = ConnectionRegistry::with_builtin_drivers();
        let err = reg
            .connect(ConnectionConfig::Postgres {
                host: "localhost".into(),
                port: 5432,
                database: "db".into(),
                user: "u".into(),
                password: None,
            })
            .unwrap_err();
        assert!(matches!(
            err,
            ConnectionError::UnsupportedDriver {
                driver: DriverKind::Postgres
            }
        ));
    }
}
