//! Extension host: spawn child processes and speak Flutter-compatible NDJSON JSON-RPC.

pub mod host;
pub mod rpc;

pub use host::{ExtensionHost, ExtensionSessionInfo};
