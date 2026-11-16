//! In-process MCP server (loopback + token) for Querya Desktop.

mod endpoint;
mod host;
mod server;

#[allow(unused_imports)]
pub use endpoint::McpEndpoint;
pub use host::{McpController, McpError, McpStatus};
#[allow(unused_imports)]
pub use server::QueryaMcpServer;
