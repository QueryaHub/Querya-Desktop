use super::error::{ConnectionError, ConnectionResult};
use super::id::{ConnectionId, DriverKind};
use super::mysql::MysqlSession;
use super::postgres::PostgresSession;
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
        /// Stable profile id — when set, the live session reuses this id.
        #[serde(default)]
        id: Option<String>,
    },
    Postgres {
        host: String,
        port: u16,
        database: String,
        user: String,
        /// Session-only secret — never written to ProfileStore (keyring: #1878).
        #[serde(default)]
        password: Option<String>,
        #[serde(default)]
        id: Option<String>,
    },
    Mysql {
        host: String,
        port: u16,
        database: String,
        user: String,
        #[serde(default)]
        password: Option<String>,
        #[serde(default)]
        id: Option<String>,
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

    /// Registry with SQLite + Postgres + MySQL openers.
    pub fn with_builtin_drivers() -> Self {
        Self::with_opener(|config| match config {
            ConnectionConfig::Sqlite { path, id } => {
                let session = match id {
                    Some(id) if !id.trim().is_empty() => {
                        super::sqlite::open_sqlite_with_id(path, ConnectionId::from(id))
                    }
                    _ => super::sqlite::open_sqlite(path),
                }?;
                Ok(Arc::new(session) as SessionArc)
            }
            ConnectionConfig::Postgres {
                host,
                port,
                database,
                user,
                password,
                id,
            } => {
                let session = super::postgres::open_postgres(super::postgres::PostgresConnectParams {
                    host,
                    port,
                    database,
                    user,
                    password,
                    id: id.filter(|s| !s.trim().is_empty()).map(ConnectionId::from),
                })?;
                Ok(Arc::new(session) as SessionArc)
            }
            ConnectionConfig::Mysql {
                host,
                port,
                database,
                user,
                password,
                id,
            } => {
                let session = super::mysql::open_mysql(super::mysql::MysqlConnectParams {
                    host,
                    port,
                    database,
                    user,
                    password,
                    id: id.filter(|s| !s.trim().is_empty()).map(ConnectionId::from),
                })?;
                Ok(Arc::new(session) as SessionArc)
            }
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

    pub fn with_postgres<T>(
        &self,
        id: &ConnectionId,
        f: impl FnOnce(&PostgresSession) -> ConnectionResult<T>,
    ) -> ConnectionResult<T> {
        let session = self.session_arc(id)?;
        let pg = session
            .as_any()
            .downcast_ref::<PostgresSession>()
            .ok_or(ConnectionError::UnsupportedDriver {
                driver: session.driver(),
            })?;
        f(pg)
    }

    pub fn with_mysql<T>(
        &self,
        id: &ConnectionId,
        f: impl FnOnce(&MysqlSession) -> ConnectionResult<T>,
    ) -> ConnectionResult<T> {
        let session = self.session_arc(id)?;
        let mysql = session
            .as_any()
            .downcast_ref::<MysqlSession>()
            .ok_or(ConnectionError::UnsupportedDriver {
                driver: session.driver(),
            })?;
        f(mysql)
    }

    /// Driver-aware query stream (SQLite + Postgres + MySQL).
    pub fn execute_query(
        &self,
        id: &ConnectionId,
        sql: &str,
        limit: Option<usize>,
        emit: impl FnMut(QueryEvent) -> ConnectionResult<()>,
    ) -> ConnectionResult<()> {
        let driver = self
            .driver_of(id)
            .ok_or_else(|| ConnectionError::NotFound { id: id.clone() })?;
        super::sql_guard::assert_single_statement(sql, driver)?;
        match driver {
            DriverKind::Sqlite => self.execute_sqlite_query(id, sql, limit, emit),
            DriverKind::Postgres => {
                self.with_postgres(id, |s| s.execute_streaming(sql, limit, emit))
            }
            DriverKind::Mysql => self.with_mysql(id, |s| s.execute_streaming(sql, limit, emit)),
        }
    }

    /// Postgres function / sequence / index / trigger / type detail (or schema listing).
    pub fn postgres_object_detail(
        &self,
        id: &ConnectionId,
        object_id: &str,
    ) -> ConnectionResult<super::postgres_object_detail::PostgresObjectDetail> {
        self.with_postgres(id, |s| {
            super::postgres_object_detail::fetch_detail(s, object_id)
        })
    }

    /// Driver-agnostic object tree for a live connection (SQLite first).
    pub fn object_tree(
        &self,
        id: &ConnectionId,
    ) -> ConnectionResult<Arc<dyn super::object_tree::ObjectTreeProvider>> {
        let session = self.session_arc(id)?;
        match session.driver() {
            DriverKind::Sqlite => {
                let sqlite = session
                    .as_any()
                    .downcast_ref::<SqliteSession>()
                    .ok_or(ConnectionError::UnsupportedDriver {
                        driver: DriverKind::Sqlite,
                    })?;
                Ok(Arc::new(super::sqlite_object_tree::SqliteObjectTree::new(
                    sqlite.clone_handle(),
                )))
            }
            DriverKind::Postgres => {
                let pg = session
                    .as_any()
                    .downcast_ref::<PostgresSession>()
                    .ok_or(ConnectionError::UnsupportedDriver {
                        driver: DriverKind::Postgres,
                    })?;
                Ok(Arc::new(
                    super::postgres_object_tree::PostgresObjectTree::new(pg.clone_handle()),
                ))
            }
            DriverKind::Mysql => {
                let mysql = session
                    .as_any()
                    .downcast_ref::<MysqlSession>()
                    .ok_or(ConnectionError::UnsupportedDriver {
                        driver: DriverKind::Mysql,
                    })?;
                Ok(Arc::new(super::mysql_object_tree::MysqlObjectTree::new(
                    mysql.clone_handle(),
                )))
            }
        }
    }

    pub fn list_children(
        &self,
        id: &ConnectionId,
        parent_id: Option<&str>,
    ) -> ConnectionResult<Vec<super::object_tree::SqlObjectNode>> {
        self.object_tree(id)?.list_children(parent_id)
    }

    pub fn describe_object(
        &self,
        id: &ConnectionId,
        object_id: &str,
    ) -> ConnectionResult<super::introspect::TableSchema> {
        self.object_tree(id)?.describe(object_id)
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
                id: None,
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
    fn registry_connect_reuses_stable_id() {
        let reg = ConnectionRegistry::with_opener(|cfg| match cfg {
            ConnectionConfig::Sqlite {
                id: Some(id), ..
            } => Ok(Arc::new(FakeSession {
                id: ConnectionId::from(id),
                driver: DriverKind::Sqlite,
            }) as SessionArc),
            _ => panic!("expected sqlite with id"),
        });
        let id = reg
            .connect(ConnectionConfig::Sqlite {
                path: "/tmp/x.db".into(),
                id: Some("profile-stable".into()),
            })
            .unwrap();
        assert_eq!(id.as_str(), "profile-stable");
        reg.disconnect(&id).unwrap();
    }

    #[test]
    fn registry_mysql_rejects_empty_host() {
        let reg = ConnectionRegistry::with_builtin_drivers();
        let err = reg
            .connect(ConnectionConfig::Mysql {
                host: "  ".into(),
                port: 3306,
                database: "db".into(),
                user: "u".into(),
                password: None,
                id: None,
            })
            .unwrap_err();
        assert!(matches!(err, ConnectionError::InvalidConfig { .. }));
    }

    #[test]
    fn registry_postgres_rejects_empty_host() {
        let reg = ConnectionRegistry::with_builtin_drivers();
        let err = reg
            .connect(ConnectionConfig::Postgres {
                host: "  ".into(),
                port: 5432,
                database: "querya".into(),
                user: "querya".into(),
                password: Some("querya".into()),
                id: None,
            })
            .unwrap_err();
        assert!(matches!(err, ConnectionError::InvalidConfig { .. }));
    }

    #[test]
    fn execute_query_rejects_multi_statement() {
        let path = std::env::temp_dir().join(format!(
            "querya_reg_guard_{}.db",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let _ = rusqlite::Connection::open(&path).unwrap();
        let reg = ConnectionRegistry::with_builtin_drivers();
        let id = reg
            .connect(ConnectionConfig::Sqlite {
                path: path.to_string_lossy().into(),
                id: None,
            })
            .unwrap();
        let err = reg
            .execute_query(&id, "SELECT 1; SELECT 2", None, |_| Ok(()))
            .unwrap_err();
        match err {
            ConnectionError::SqlGuard { rule, .. } => {
                assert_eq!(rule.as_str(), "single_statement");
            }
            other => panic!("expected SqlGuard, got {other:?}"),
        }
        let _ = std::fs::remove_file(&path);
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
                id: None,
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
