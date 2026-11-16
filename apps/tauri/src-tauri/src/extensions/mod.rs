//! Extension host: spawn child processes and speak Flutter-compatible NDJSON JSON-RPC.

pub mod host;
pub mod paths;
pub mod rpc;

pub use host::{ExtensionHost, ExtensionSessionInfo};
pub use paths::hello_panel_executable;
