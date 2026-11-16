//! `querya-mcp` — stdio bridge to a running Querya Desktop MCP host.
//!
//! Compatible with the Flutter endpoint file (`QUERYA_MCP_ENDPOINT` override).

use querya_desktop_tauri_lib::mcp::shim::run_shim;
use std::env;
use std::process::ExitCode;

#[tokio::main]
async fn main() -> ExitCode {
    if env::args().any(|a| a == "--help" || a == "-h") {
        eprintln!(
            "Usage: querya-mcp\n\n\
             Connects an MCP client over stdio to the MCP server of a running\n\
             Querya Desktop. Takes no arguments; the endpoint file can be\n\
             overridden with QUERYA_MCP_ENDPOINT."
        );
        return ExitCode::SUCCESS;
    }

    let code = run_shim(None).await;
    ExitCode::from(code as u8)
}
