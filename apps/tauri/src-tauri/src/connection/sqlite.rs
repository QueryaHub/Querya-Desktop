//! SQLite driver via `rusqlite` (bundled libsqlite3).

use super::error::{ConnectionError, ConnectionResult};
use super::id::{ConnectionId, DriverKind};
use super::manager::ConnectionSession;
use rusqlite::Connection;
use std::path::Path;
use std::sync::Mutex;

pub struct SqliteSession {
    id: ConnectionId,
    path: String,
    /// rusqlite::Connection is !Sync — guard for Tauri/registry threads.
    conn: Mutex<Option<Connection>>,
}

impl SqliteSession {
    #[allow(dead_code)] // used by introspection / query issues next
    pub fn path(&self) -> &str {
        &self.path
    }

    #[allow(dead_code)] // used by execute_query / tree issues next
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
}

impl ConnectionSession for SqliteSession {
    fn id(&self) -> &ConnectionId {
        &self.id
    }

    fn driver(&self) -> DriverKind {
        DriverKind::Sqlite
    }

    fn disconnect(&mut self) -> ConnectionResult<()> {
        let guard = self
            .conn
            .get_mut()
            .map_err(|_| ConnectionError::io("sqlite connection lock poisoned"))?;
        if let Some(conn) = guard.take() {
            conn.close()
                .map_err(|(_, e)| ConnectionError::driver(DriverKind::Sqlite, e.to_string()))?;
        }
        Ok(())
    }
}

/// Open a SQLite database file and return a live session.
pub fn open_sqlite(path: impl AsRef<str>) -> ConnectionResult<Box<dyn ConnectionSession>> {
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

    let conn = Connection::open(path)
        .map_err(|e| ConnectionError::driver(DriverKind::Sqlite, e.to_string()))?;

    conn.query_row("SELECT 1", [], |_| Ok(()))
        .map_err(|e| ConnectionError::driver(DriverKind::Sqlite, e.to_string()))?;

    Ok(Box::new(SqliteSession {
        id: ConnectionId::new(),
        path: path.to_owned(),
        conn: Mutex::new(Some(conn)),
    }))
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
        let mut session = open_sqlite(&path_str).expect("open");
        assert_eq!(session.driver(), DriverKind::Sqlite);
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
}
