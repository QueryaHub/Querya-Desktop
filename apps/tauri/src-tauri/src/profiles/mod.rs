//! Local connection profiles (Flutter LocalDb `connections` table equivalent).
//! Secrets never land here — keyring is #1878 / #1847.

mod store;

pub use store::{ConnectionProfile, ProfileStore, ProfileStoreError};
