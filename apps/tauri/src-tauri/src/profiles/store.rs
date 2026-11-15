//! App-data SQLite for connection metadata (no passwords / connection strings).

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

const SCHEMA_VERSION: i32 = 1;

/// Persisted connection profile — mirrors Flutter `ConnectionRow` non-secret fields.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ConnectionProfile {
    pub id: String,
    /// Driver family: `sqlite` | `postgres` | `mysql` (… later).
    pub driver: String,
    pub name: String,
    /// SQLite file path (absolute).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub host: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub port: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub username: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub database_name: Option<String>,
    /// SERVERS folder id (frontend string id; not a LocalDb integer).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub folder_id: Option<String>,
    pub sort_order: i64,
    pub created_at: String,
    pub updated_at: String,
}

impl ConnectionProfile {
    pub fn new_sqlite(name: impl Into<String>, path: impl Into<String>) -> Self {
        let now = now_rfc3339();
        Self {
            id: Uuid::new_v4().to_string(),
            driver: "sqlite".into(),
            name: name.into(),
            path: Some(path.into()),
            host: None,
            port: None,
            username: None,
            database_name: None,
            folder_id: None,
            sort_order: 0,
            created_at: now.clone(),
            updated_at: now,
        }
    }

    pub fn new_postgres(
        name: impl Into<String>,
        host: impl Into<String>,
        port: u16,
        database: impl Into<String>,
        user: impl Into<String>,
    ) -> Self {
        let now = now_rfc3339();
        Self {
            id: Uuid::new_v4().to_string(),
            driver: "postgres".into(),
            name: name.into(),
            path: None,
            host: Some(host.into()),
            port: Some(i64::from(port)),
            username: Some(user.into()),
            database_name: Some(database.into()),
            folder_id: None,
            sort_order: 0,
            created_at: now.clone(),
            updated_at: now,
        }
    }

    pub fn new_mysql(
        name: impl Into<String>,
        host: impl Into<String>,
        port: u16,
        database: impl Into<String>,
        user: impl Into<String>,
    ) -> Self {
        let now = now_rfc3339();
        Self {
            id: Uuid::new_v4().to_string(),
            driver: "mysql".into(),
            name: name.into(),
            path: None,
            host: Some(host.into()),
            port: Some(i64::from(port)),
            username: Some(user.into()),
            database_name: Some(database.into()),
            folder_id: None,
            sort_order: 0,
            created_at: now.clone(),
            updated_at: now,
        }
    }

    pub fn touch(&mut self) {
        self.updated_at = now_rfc3339();
    }
}

#[derive(Debug)]
pub enum ProfileStoreError {
    Io(String),
    Db(String),
    Invalid(String),
}

impl std::fmt::Display for ProfileStoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(m) | Self::Db(m) | Self::Invalid(m) => f.write_str(m),
        }
    }
}

impl std::error::Error for ProfileStoreError {}

impl From<rusqlite::Error> for ProfileStoreError {
    fn from(value: rusqlite::Error) -> Self {
        Self::Db(value.to_string())
    }
}

impl From<std::io::Error> for ProfileStoreError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value.to_string())
    }
}

impl serde::Serialize for ProfileStoreError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}

/// LocalDb-equivalent profile store. Open once; share via Tauri `State`.
pub struct ProfileStore {
    conn: Mutex<Connection>,
    path: PathBuf,
}

impl ProfileStore {
    /// Default on-disk location: `{data_dir}/querya_desktop/querya.db`
    /// (Flutter LocalDb folder name; Tauri-only file until shared migration).
    pub fn default_path() -> PathBuf {
        let base = dirs::data_dir().unwrap_or_else(std::env::temp_dir);
        base.join("querya_desktop").join("querya.db")
    }

    pub fn open_default() -> Result<Self, ProfileStoreError> {
        Self::open(Self::default_path())
    }

    pub fn open(path: impl AsRef<Path>) -> Result<Self, ProfileStoreError> {
        let path = path.as_ref().to_path_buf();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let conn = Connection::open(&path)?;
        conn.execute_batch(
            "PRAGMA foreign_keys = ON;
             PRAGMA journal_mode = WAL;
             PRAGMA busy_timeout = 5000;
             PRAGMA synchronous = NORMAL;",
        )?;
        migrate(&conn)?;
        Ok(Self {
            conn: Mutex::new(conn),
            path,
        })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn list(&self) -> Result<Vec<ConnectionProfile>, ProfileStoreError> {
        let conn = self.lock()?;
        let mut stmt = conn.prepare(
            "SELECT id, driver, name, path, host, port, username, database_name,
                    folder_id, sort_order, created_at, updated_at
             FROM connections
             ORDER BY sort_order ASC, name ASC",
        )?;
        let rows = stmt.query_map([], row_to_profile)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    pub fn get(&self, id: &str) -> Result<Option<ConnectionProfile>, ProfileStoreError> {
        let conn = self.lock()?;
        conn.query_row(
            "SELECT id, driver, name, path, host, port, username, database_name,
                    folder_id, sort_order, created_at, updated_at
             FROM connections WHERE id = ?1",
            params![id],
            row_to_profile,
        )
        .optional()
        .map_err(Into::into)
    }

    /// Insert or replace. Never writes password / connection_string columns.
    pub fn upsert(&self, profile: &ConnectionProfile) -> Result<(), ProfileStoreError> {
        if profile.id.trim().is_empty() {
            return Err(ProfileStoreError::Invalid("profile id is empty".into()));
        }
        if profile.name.trim().is_empty() {
            return Err(ProfileStoreError::Invalid("profile name is empty".into()));
        }
        if profile.driver.trim().is_empty() {
            return Err(ProfileStoreError::Invalid("profile driver is empty".into()));
        }
        let conn = self.lock()?;
        conn.execute(
            "INSERT INTO connections (
                id, driver, name, path, host, port, username, database_name,
                folder_id, sort_order, created_at, updated_at,
                password, connection_string
             ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8,
                ?9, ?10, ?11, ?12,
                NULL, NULL
             )
             ON CONFLICT(id) DO UPDATE SET
                driver = excluded.driver,
                name = excluded.name,
                path = excluded.path,
                host = excluded.host,
                port = excluded.port,
                username = excluded.username,
                database_name = excluded.database_name,
                folder_id = excluded.folder_id,
                sort_order = excluded.sort_order,
                updated_at = excluded.updated_at,
                password = NULL,
                connection_string = NULL",
            params![
                profile.id,
                profile.driver,
                profile.name,
                profile.path,
                profile.host,
                profile.port,
                profile.username,
                profile.database_name,
                profile.folder_id,
                profile.sort_order,
                profile.created_at,
                profile.updated_at,
            ],
        )?;
        Ok(())
    }

    pub fn delete(&self, id: &str) -> Result<bool, ProfileStoreError> {
        let conn = self.lock()?;
        let n = conn.execute("DELETE FROM connections WHERE id = ?1", params![id])?;
        Ok(n > 0)
    }

    fn lock(&self) -> Result<std::sync::MutexGuard<'_, Connection>, ProfileStoreError> {
        self.conn
            .lock()
            .map_err(|_| ProfileStoreError::Io("profile store lock poisoned".into()))
    }
}

fn migrate(conn: &Connection) -> Result<(), ProfileStoreError> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY NOT NULL
         );",
    )?;
    let current: i32 = conn
        .query_row(
            "SELECT COALESCE(MAX(version), 0) FROM schema_migrations",
            [],
            |r| r.get(0),
        )
        .unwrap_or(0);

    if current < 1 {
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS connections (
                id TEXT PRIMARY KEY NOT NULL,
                driver TEXT NOT NULL,
                name TEXT NOT NULL,
                path TEXT,
                host TEXT,
                port INTEGER,
                username TEXT,
                database_name TEXT,
                folder_id TEXT,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                -- Reserved for schema parity with Flutter; always NULL (secrets → keyring).
                password TEXT,
                connection_string TEXT
             );
             CREATE INDEX IF NOT EXISTS idx_connections_sort
             ON connections (sort_order ASC, name ASC);",
        )?;
        conn.execute(
            "INSERT INTO schema_migrations (version) VALUES (?1)",
            params![SCHEMA_VERSION],
        )?;
    }
    Ok(())
}

fn row_to_profile(row: &rusqlite::Row<'_>) -> rusqlite::Result<ConnectionProfile> {
    Ok(ConnectionProfile {
        id: row.get(0)?,
        driver: row.get(1)?,
        name: row.get(2)?,
        path: row.get(3)?,
        host: row.get(4)?,
        port: row.get(5)?,
        username: row.get(6)?,
        database_name: row.get(7)?,
        folder_id: row.get(8)?,
        sort_order: row.get(9)?,
        created_at: row.get(10)?,
        updated_at: row.get(11)?,
    })
}

fn now_rfc3339() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    // Compact UTC stamp is enough for sort/debug; full chrono not required yet.
    format!("{secs}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_store() -> (ProfileStore, PathBuf) {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("querya_profiles_test_{nanos}.db"));
        let store = ProfileStore::open(&path).expect("open");
        (store, path)
    }

    #[test]
    fn upsert_list_get_delete_round_trip() {
        let (store, path) = temp_store();
        let mut p = ConnectionProfile::new_sqlite("shop", "/tmp/shop.db");
        p.folder_id = Some("folder-1".into());
        store.upsert(&p).unwrap();

        let listed = store.list().unwrap();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].name, "shop");
        assert_eq!(listed[0].path.as_deref(), Some("/tmp/shop.db"));
        assert_eq!(listed[0].folder_id.as_deref(), Some("folder-1"));

        let got = store.get(&p.id).unwrap().expect("present");
        assert_eq!(got.id, p.id);

        // Secrets columns must stay NULL even if someone tries to poke the row.
        {
            let conn = Connection::open(&path).unwrap();
            let (pw, cs): (Option<String>, Option<String>) = conn
                .query_row(
                    "SELECT password, connection_string FROM connections WHERE id = ?1",
                    params![p.id],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .unwrap();
            assert!(pw.is_none());
            assert!(cs.is_none());
        }

        p.name = "shop-renamed".into();
        p.touch();
        store.upsert(&p).unwrap();
        assert_eq!(store.get(&p.id).unwrap().unwrap().name, "shop-renamed");

        assert!(store.delete(&p.id).unwrap());
        assert!(store.list().unwrap().is_empty());
        assert!(!store.delete(&p.id).unwrap());
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn rejects_empty_name() {
        let (store, path) = temp_store();
        let mut p = ConnectionProfile::new_sqlite("x", "/tmp/x.db");
        p.name = "  ".into();
        let err = store.upsert(&p).unwrap_err();
        assert!(matches!(err, ProfileStoreError::Invalid(_)));
        let _ = std::fs::remove_file(&path);
    }
}
