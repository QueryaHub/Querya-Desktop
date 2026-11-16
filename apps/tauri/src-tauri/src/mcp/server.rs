//! Minimal in-process MCP server (initialize / ping). Tools land in #1901.

use rmcp::handler::server::ServerHandler;
use rmcp::model::{Implementation, ServerCapabilities, ServerConfig};

#[derive(Clone, Default)]
pub struct QueryaMcpServer;

impl QueryaMcpServer {
    pub fn new() -> Self {
        Self
    }
}

impl ServerHandler for QueryaMcpServer {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(ServerCapabilities::builder().enable_tools().build())
            .with_server_info(Implementation::new(
                "querya-desktop",
                env!("CARGO_PKG_VERSION"),
            ))
            .with_instructions(
                "Querya Desktop MCP skeleton. Connection/query tools arrive in a follow-up.",
            )
    }
}
