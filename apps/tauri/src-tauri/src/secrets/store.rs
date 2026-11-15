//! keyring-rs wrapper keyed by connection profile id.

use serde::Serialize;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

/// Keyring service id — stable across Querya Tauri builds.
pub const SERVICE: &str = "com.queryahub.querya_tauri";

fn password_account(profile_id: &str) -> String {
    format!("querya.tauri.v1.conn.{profile_id}.password")
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum SecretError {
    Invalid { message: String },
    Backend { message: String },
}

impl SecretError {
    pub fn invalid(message: impl Into<String>) -> Self {
        Self::Invalid {
            message: message.into(),
        }
    }

    pub fn backend(message: impl Into<String>) -> Self {
        Self::Backend {
            message: message.into(),
        }
    }
}

impl std::fmt::Display for SecretError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Invalid { message } | Self::Backend { message } => f.write_str(message),
        }
    }
}

impl std::error::Error for SecretError {}

impl From<keyring::Error> for SecretError {
    fn from(value: keyring::Error) -> Self {
        Self::backend(value.to_string())
    }
}

/// Pluggable secret backend (OS keyring in production, memory in tests).
pub trait SecretStore: Send + Sync {
    fn set_password(&self, profile_id: &str, password: &str) -> Result<(), SecretError>;
    fn get_password(&self, profile_id: &str) -> Result<Option<String>, SecretError>;
    fn delete_password(&self, profile_id: &str) -> Result<(), SecretError>;
}

pub type SharedSecretStore = Arc<dyn SecretStore>;

/// In-memory store for unit tests (never touches the OS keyring).
#[derive(Default)]
pub struct MemorySecretStore {
    map: Mutex<HashMap<String, String>>,
}

impl MemorySecretStore {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn shared() -> SharedSecretStore {
        Arc::new(Self::new())
    }
}

impl SecretStore for MemorySecretStore {
    fn set_password(&self, profile_id: &str, password: &str) -> Result<(), SecretError> {
        let id = profile_id.trim();
        if id.is_empty() {
            return Err(SecretError::invalid("profile id is empty"));
        }
        self.map
            .lock()
            .map_err(|_| SecretError::backend("secret store lock poisoned"))?
            .insert(password_account(id), password.to_owned());
        Ok(())
    }

    fn get_password(&self, profile_id: &str) -> Result<Option<String>, SecretError> {
        let id = profile_id.trim();
        if id.is_empty() {
            return Err(SecretError::invalid("profile id is empty"));
        }
        Ok(self
            .map
            .lock()
            .map_err(|_| SecretError::backend("secret store lock poisoned"))?
            .get(&password_account(id))
            .cloned())
    }

    fn delete_password(&self, profile_id: &str) -> Result<(), SecretError> {
        let id = profile_id.trim();
        if id.is_empty() {
            return Err(SecretError::invalid("profile id is empty"));
        }
        self.map
            .lock()
            .map_err(|_| SecretError::backend("secret store lock poisoned"))?
            .remove(&password_account(id));
        Ok(())
    }
}

/// OS keyring via `keyring` crate (Keychain / Credential Manager / Secret Service).
pub struct KeyringSecretStore;

impl KeyringSecretStore {
    pub fn new() -> Self {
        Self
    }

    pub fn shared() -> SharedSecretStore {
        Arc::new(Self::new())
    }

    fn entry(profile_id: &str) -> Result<keyring::Entry, SecretError> {
        let id = profile_id.trim();
        if id.is_empty() {
            return Err(SecretError::invalid("profile id is empty"));
        }
        keyring::Entry::new(SERVICE, &password_account(id)).map_err(Into::into)
    }
}

impl Default for KeyringSecretStore {
    fn default() -> Self {
        Self::new()
    }
}

impl SecretStore for KeyringSecretStore {
    fn set_password(&self, profile_id: &str, password: &str) -> Result<(), SecretError> {
        Self::entry(profile_id)?.set_password(password)?;
        Ok(())
    }

    fn get_password(&self, profile_id: &str) -> Result<Option<String>, SecretError> {
        match Self::entry(profile_id)?.get_password() {
            Ok(p) => Ok(Some(p)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    fn delete_password(&self, profile_id: &str) -> Result<(), SecretError> {
        match Self::entry(profile_id)?.delete_credential() {
            Ok(()) => Ok(()),
            Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(e.into()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn memory_round_trip() {
        let store = MemorySecretStore::new();
        store.set_password("p1", "s3cret").unwrap();
        assert_eq!(store.get_password("p1").unwrap().as_deref(), Some("s3cret"));
        store.delete_password("p1").unwrap();
        assert_eq!(store.get_password("p1").unwrap(), None);
    }

    #[test]
    fn memory_rejects_empty_id() {
        let store = MemorySecretStore::new();
        assert!(matches!(
            store.set_password("  ", "x"),
            Err(SecretError::Invalid { .. })
        ));
    }

    /// Platform keyring — skipped when the OS secret service is unavailable (CI).
    #[test]
    fn keyring_round_trip_or_skip() {
        if std::env::var_os("QUERYA_SKIP_KEYRING").is_some() {
            eprintln!("skip keyring live test (QUERYA_SKIP_KEYRING)");
            return;
        }
        let store = KeyringSecretStore::new();
        let id = format!(
            "test-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        );
        match store.set_password(&id, "roundtrip-secret") {
            Ok(()) => {}
            Err(e) => {
                eprintln!("skip keyring live test: {e}");
                return;
            }
        }
        let got = store.get_password(&id).expect("get");
        assert_eq!(got.as_deref(), Some("roundtrip-secret"));
        store.delete_password(&id).expect("delete");
        assert_eq!(store.get_password(&id).unwrap(), None);
    }
}
