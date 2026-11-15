//! SQLite driver via `rusqlite` (bundled libsqlite3).

use super::error::{ConnectionError, ConnectionResult};
use super::id::{ConnectionId, DriverKind};
use super::manager::ConnectionSession;
use super::query::QueryEvent;
use rusqlite::Connection;
use std::path::Path;
use std::sync::{Arc, Mutex};

pub struct SqliteSession {
    id: ConnectionId,
    /// On-disk path used to open this session (for diagnostics / UI).
    path: String,
    /// Shared so query streaming can hold the session Arc without the registry lock.
    conn: Arc<Mutex<Option<Connection>>>,
}

impl SqliteSession {
    pub fn path(&self) -> &str {
        &self.path
    }

    /// Clone the session handle (shared connection Arc) for providers outside the registry lock.
    pub fn clone_handle(&self) -> Self {
        Self {
            id: self.id.clone(),
            path: self.path.clone(),
            conn: Arc::clone(&self.conn),
        }
    }

    pub fn with_connection<T>(
        &self,
        f: impl FnOnce(&Connection) -> ConnectionResult<T>,
    ) -> ConnectionResult<T> {
        let guard = self
            .conn
            .lock()
            .map_err(|_| ConnectionError::io("sqlite connection lock poisoned"))?;
        let conn = guard
            .as_ref()
            .ok_or_else(|| ConnectionError::Disconnected {
                id: self.id.clone(),
            })?;
        f(conn)
    }

    pub fn list_schemas(&self) -> ConnectionResult<Vec<String>> {
        self.with_connection(super::sqlite_introspect::list_schemas)
    }

    pub fn list_tables(&self) -> ConnectionResult<Vec<super::introspect::SchemaObject>> {
        self.with_connection(super::sqlite_introspect::list_tables)
    }

    pub fn list_columns(
        &self,
        table: &str,
    ) -> ConnectionResult<super::introspect::TableSchema> {
        self.with_connection(|c| super::sqlite_introspect::list_columns(c, table))
    }

    /// Flutter `databaseOverview` for the Overview / Database Info tab.
    pub fn database_overview(
        &self,
    ) -> ConnectionResult<super::sqlite_introspect::SqliteOverview> {
        self.with_connection(|c| {
            super::sqlite_introspect::database_overview(c, &self.path)
        })
    }

    pub fn execute_streaming(
        &self,
        sql: &str,
        limit: Option<usize>,
        emit: impl FnMut(QueryEvent) -> ConnectionResult<()>,
    ) -> ConnectionResult<()> {
        self.with_connection(|c| {
            super::sqlite_query::execute_streaming(c, sql, limit, None, emit)
        })
    }
}

impl ConnectionSession for SqliteSession {
    fn id(&self) -> &ConnectionId {
        &self.id
    }

    fn driver(&self) -> DriverKind {
        DriverKind::Sqlite
    }

    fn disconnect(&self) -> ConnectionResult<()> {
        let mut guard = self
            .conn
            .lock()
            .map_err(|_| ConnectionError::io("sqlite connection lock poisoned"))?;
        if let Some(conn) = guard.take() {
            conn.close().map_err(|(_, e)| ConnectionError::from(e))?;
        }
        Ok(())
    }

    fn as_any(&self) -> &dyn std::any::Any {
        self
    }
}

/// Open a SQLite database file and return a live session.
pub fn open_sqlite(path: impl AsRef<str>) -> ConnectionResult<SqliteSession> {
    let path = path.as_ref().trim();
    if path.is_empty() {
        return Err(ConnectionError::invalid_config("sqlite path is empty"));
    }

    let p = Path::new(path);
    if let Some(parent) = p.parent() {
        if !parent.as_os_str().is_empty() && !parent.exists() {
            return Err(ConnectionError::io(format!(
                "parent directory does not exist: {}",
                parent.display()
            )));
        }
    }

    let conn = Connection::open(path)?;
    conn.query_row("SELECT 1", [], |_| Ok(()))?;

    Ok(SqliteSession {
        id: ConnectionId::new(),
        path: path.to_owned(),
        conn: Arc::new(Mutex::new(Some(conn))),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::connection::manager::{ConnectionConfig, ConnectionManager, ConnectionRegistry};
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_db() -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("querya_sqlite_test_{nanos}.db"))
    }

    #[test]
    fn open_and_disconnect_temp_db() {
        let path = temp_db();
        let path_str = path.to_string_lossy().to_string();
        let session = open_sqlite(&path_str).expect("open");
        assert_eq!(session.driver(), DriverKind::Sqlite);
        assert_eq!(session.path(), path_str);
        session.disconnect().expect("disconnect");
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn empty_path_is_invalid_config() {
        match open_sqlite("  ") {
            Err(ConnectionError::InvalidConfig { .. }) => {}
            Err(e) => panic!("expected InvalidConfig, got {e}"),
            Ok(_) => panic!("expected error for empty path"),
        }
    }

    #[test]
    fn registry_sqlite_round_trip() {
        let path = temp_db();
        let path_str = path.to_string_lossy().to_string();
        let reg = ConnectionRegistry::with_builtin_drivers();
        let id = reg
            .connect(ConnectionConfig::Sqlite {
                path: path_str.clone(),
            })
            .expect("connect");
        assert!(reg.is_connected(&id));
        assert_eq!(reg.driver_of(&id), Some(DriverKind::Sqlite));
        reg.disconnect(&id).expect("disconnect");
        assert!(!reg.is_connected(&id));
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn registry_introspect_fixture() {
        let path = temp_db();
        let path_str = path.to_string_lossy().to_string();
        {
            let conn = Connection::open(&path).unwrap();
            conn.execute_batch(
                "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL);",
            )
            .unwrap();
        }
        let reg = ConnectionRegistry::with_builtin_drivers();
        let id = reg
            .connect(ConnectionConfig::Sqlite {
                path: path_str,
            })
            .expect("connect");
        let schemas = reg
            .with_sqlite(&id, |s| s.list_schemas())
            .expect("schemas");
        assert_eq!(schemas, vec!["main".to_string()]);
        let tables = reg.with_sqlite(&id, |s| s.list_tables()).expect("tables");
        assert_eq!(tables.len(), 1);
        assert_eq!(tables[0].name, "t");
        let cols = reg
            .with_sqlite(&id, |s| s.list_columns("t"))
            .expect("columns");
        assert_eq!(cols.primary_keys, vec!["id".to_string()]);
        assert_eq!(cols.columns.len(), 2);
        reg.disconnect(&id).unwrap();
        let _ = std::fs::remove_file(&path);
    }
}
