//! OS keyring for connection secrets (Flutter `ConnectionSecretsStore` parity).
//! Passwords never land in ProfileStore — only here (#1878 / #1847).

mod store;

pub use store::{
    KeyringSecretStore, MemorySecretStore, SecretError, SecretStore, SharedSecretStore,
};
