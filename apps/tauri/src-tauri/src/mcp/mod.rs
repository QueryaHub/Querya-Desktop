//! In-process MCP server (loopback + token) for Querya Desktop.

mod endpoint;
mod host;
pub mod paths;
mod server;
pub mod shim;

#[allow(unused_imports)]
pub use endpoint::McpEndpoint;
pub use host::{McpController, McpError, McpStatus};
#[allow(unused_imports)]
pub use server::QueryaMcpServer;
pub use shim::{run_shim, APP_NOT_RUNNING};
