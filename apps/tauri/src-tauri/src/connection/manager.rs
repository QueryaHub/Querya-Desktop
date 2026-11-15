use super::error::{ConnectionError, ConnectionResult};
use super::id::{ConnectionId, DriverKind};
use super::query::QueryEvent;
use super::sqlite::SqliteSession;
use serde::{Deserialize, Serialize};
use std::any::Any;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

/// Driver-agnostic connect parameters (tagged for IPC).
/// Secrets are not part of this enum — keyring lands with #1847.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "driver", rename_all = "snake_case")]
pub enum ConnectionConfig {
    Sqlite {
        /// Absolute or relative path to a `.db` / `.sqlite` file.
        path: String,
    },
    /// Stub until the Postgres adapter epic wires connect.
    Postgres {
        host: String,
        port: u16,
        database: String,
        user: String,
    },
    /// Stub until the MySQL adapter epic wires connect.
    Mysql {
        host: String,
        port: u16,
        database: String,
        user: String,
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
    /// Close the underlying driver connection (interior mutability OK).
    fn disconnect(&self) -> ConnectionResult<()>;
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

type SessionArc = Arc<dyn ConnectionSession>;

/// In-memory registry used by Tauri commands.
pub struct ConnectionRegistry {
    sessions: Mutex<HashMap<ConnectionId, SessionArc>>,
    opener: Option<Arc<dyn Fn(ConnectionConfig) -> ConnectionResult<SessionArc> + Send + Sync>>,
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
            ConnectionConfig::Sqlite { path } => {
                let session = super::sqlite::open_sqlite(path)?;
                Ok(Arc::new(session) as SessionArc)
            }
            other => Err(ConnectionError::UnsupportedDriver {
                driver: other.driver_kind(),
            }),
        })
    }

    pub fn with_opener<F>(opener: F) -> Self
    where
        F: Fn(ConnectionConfig) -> ConnectionResult<SessionArc> + Send + Sync + 'static,
    {
        Self {
            sessions: Mutex::new(HashMap::new()),
            opener: Some(Arc::new(opener)),
        }
    }

    fn lock(
        &self,
    ) -> ConnectionResult<std::sync::MutexGuard<'_, HashMap<ConnectionId, SessionArc>>> {
        self.sessions
            .lock()
            .map_err(|_| ConnectionError::io("connection registry lock poisoned"))
    }

    /// Clone a session Arc under a brief map lock.
    fn session_arc(&self, id: &ConnectionId) -> ConnectionResult<SessionArc> {
        let map = self.lock()?;
        map.get(id)
            .cloned()
            .ok_or_else(|| ConnectionError::NotFound { id: id.clone() })
    }

    /// Run a closure against a live [`SqliteSession`] **outside** the registry map lock.
    pub fn with_sqlite<T>(
        &self,
        id: &ConnectionId,
        f: impl FnOnce(&SqliteSession) -> ConnectionResult<T>,
    ) -> ConnectionResult<T> {
        let session = self.session_arc(id)?;
        let sqlite = session
            .as_any()
            .downcast_ref::<SqliteSession>()
            .ok_or(ConnectionError::UnsupportedDriver {
                driver: session.driver(),
            })?;
        f(sqlite)
    }

    /// Stream a query through the SQLite session API (commands stay thin).
    pub fn execute_sqlite_query(
        &self,
        id: &ConnectionId,
        sql: &str,
        limit: Option<usize>,
        emit: impl FnMut(QueryEvent) -> ConnectionResult<()>,
    ) -> ConnectionResult<()> {
        self.with_sqlite(id, |s| s.execute_streaming(sql, limit, emit))
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
        // Open outside the map lock (disk I/O).
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
        let session = map
            .remove(id)
            .ok_or_else(|| ConnectionError::NotFound { id: id.clone() })?;
        drop(map);
        session.disconnect()
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
    }

    impl ConnectionSession for FakeSession {
        fn id(&self) -> &ConnectionId {
            &self.id
        }
        fn driver(&self) -> DriverKind {
            self.driver
        }
        fn disconnect(&self) -> ConnectionResult<()> {
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
            Ok(Arc::new(FakeSession {
                id: ConnectionId::from("s1"),
                driver: DriverKind::Sqlite,
            }) as SessionArc)
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
            })
            .unwrap_err();
        assert!(matches!(
            err,
            ConnectionError::UnsupportedDriver {
                driver: DriverKind::Postgres
            }
        ));
    }

    #[test]
    fn execute_sqlite_query_streams_via_session() {
        let path = std::env::temp_dir().join(format!(
            "querya_reg_query_{}.db",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        {
            let conn = rusqlite::Connection::open(&path).unwrap();
            conn.execute_batch("CREATE TABLE t(n INTEGER); INSERT INTO t VALUES (1),(2),(3);")
                .unwrap();
        }
        let reg = ConnectionRegistry::with_builtin_drivers();
        let id = reg
            .connect(ConnectionConfig::Sqlite {
                path: path.to_string_lossy().into(),
            })
            .unwrap();
        let mut events = Vec::new();
        reg.execute_sqlite_query(&id, "SELECT n FROM t ORDER BY n", Some(10), |ev| {
            events.push(ev);
            Ok(())
        })
        .unwrap();
        assert!(matches!(events.first(), Some(QueryEvent::Columns { .. })));
        assert!(matches!(events.last(), Some(QueryEvent::Done { row_count: 3, .. })));
        reg.disconnect(&id).unwrap();
        let _ = std::fs::remove_file(&path);
    }
}
