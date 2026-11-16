//! Stdio → loopback bridge for external MCP clients (`querya-mcp`).

use super::endpoint::McpEndpoint;
use std::path::PathBuf;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpStream;

/// Message when Querya Desktop is not reachable (Flutter parity).
pub const APP_NOT_RUNNING: &str = "Querya Desktop is not running or its MCP server is off. Start Querya Desktop and enable the MCP server in Settings, then retry.";

/// Forward stdin/stdout to the running Querya MCP host.
///
/// Returns the process exit code (0 = clean, 1 = unavailable / lost).
pub async fn run_shim(endpoint_file: Option<PathBuf>) -> i32 {
    let path = endpoint_file.unwrap_or_else(McpEndpoint::default_path);
    let endpoint = match McpEndpoint::read(&path) {
        Ok(Some(ep)) => ep,
        Ok(None) => {
            eprintln!("querya-mcp: {APP_NOT_RUNNING} (endpoint: {})", path.display());
            return answer_unavailable().await;
        }
        Err(e) => {
            eprintln!("querya-mcp: {APP_NOT_RUNNING} (endpoint: {}: {e})", path.display());
            return answer_unavailable().await;
        }
    };

    let connect = TcpStream::connect(("127.0.0.1", endpoint.port));
    let mut socket = match tokio::time::timeout(Duration::from_secs(3), connect).await {
        Ok(Ok(s)) => s,
        Ok(Err(e)) => {
            eprintln!(
                "querya-mcp: {APP_NOT_RUNNING} (endpoint: {}: {e})",
                path.display()
            );
            return answer_unavailable().await;
        }
        Err(_) => {
            eprintln!(
                "querya-mcp: {APP_NOT_RUNNING} (endpoint: {}: connect timed out)",
                path.display()
            );
            return answer_unavailable().await;
        }
    };

    if let Err(e) = socket.set_nodelay(true) {
        eprintln!("querya-mcp: tcp_nodelay: {e}");
    }

    if let Err(e) = socket
        .write_all(format!("{}\n", endpoint.token).as_bytes())
        .await
    {
        eprintln!("querya-mcp: connection to Querya Desktop lost: {e}");
        return 1;
    }

    let (mut sock_read, mut sock_write) = socket.into_split();
    let mut stdin = tokio::io::stdin();
    let mut stdout = tokio::io::stdout();

    let to_app = async {
        let mut buf = vec![0u8; 65536];
        loop {
            match stdin.read(&mut buf).await {
                Ok(0) => {
                    let _ = sock_write.shutdown().await;
                    break;
                }
                Ok(n) => {
                    if sock_write.write_all(&buf[..n]).await.is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    };

    let from_app = async {
        let mut buf = vec![0u8; 65536];
        loop {
            match sock_read.read(&mut buf).await {
                Ok(0) => break,
                Ok(n) => {
                    if stdout.write_all(&buf[..n]).await.is_err() {
                        break;
                    }
                    let _ = stdout.flush().await;
                }
                Err(_) => break,
            }
        }
    };

    tokio::select! {
        _ = to_app => {}
        _ = from_app => {}
    }
    0
}

async fn answer_unavailable() -> i32 {
    let stdin = BufReader::new(tokio::io::stdin());
    let mut lines = stdin.lines();
    let mut stdout = tokio::io::stdout();
    while let Ok(Some(line)) = lines.next_line().await {
        let id = serde_json::from_str::<serde_json::Value>(&line)
            .ok()
            .and_then(|v| v.get("id").cloned())
            .filter(|id| !id.is_null());
        let Some(id) = id else {
            continue;
        };
        let err = serde_json::json!({
            "jsonrpc": "2.0",
            "id": id,
            "error": { "code": -32000, "message": APP_NOT_RUNNING }
        });
        let _ = stdout.write_all(format!("{err}\n").as_bytes()).await;
        let _ = stdout.flush().await;
    }
    1
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::connection::{ConnectionConfig, ConnectionManager, ConnectionRegistry};
    use crate::mcp::host::McpController;
    use std::process::Stdio;
    use std::sync::Arc;
    use tokio::process::Command;

    #[test]
    fn shim_initialize_through_running_host() {
        if std::env::var_os("QUERYA_SKIP_MCP").is_some() {
            return;
        }

        let dir = std::env::temp_dir().join(format!(
            "querya-mcp-shim-{}-{}",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let db_path = dir.join("fixture.db");
        let ep_path = dir.join("mcp-endpoint.json");
        {
            let conn = rusqlite::Connection::open(&db_path).unwrap();
            conn.execute_batch("CREATE TABLE t (id INTEGER); INSERT INTO t VALUES (1);")
                .unwrap();
        }

        let registry = Arc::new(ConnectionRegistry::new());
        registry
            .connect(ConnectionConfig::Sqlite {
                path: db_path.to_string_lossy().into_owned(),
                id: Some("shim-sqlite".into()),
            })
            .unwrap();

        crate::connection::runtime::block_on(async {
            let ctrl = McpController::new(Arc::clone(&registry));
            let _ = ctrl.start_async(Some(ep_path.clone())).await.unwrap();

            // Prefer the built bin when available; otherwise exercise library path.
            let bin = std::env::current_exe()
                .ok()
                .and_then(|p| p.parent().map(|d| d.join("querya-mcp")));
            let use_bin = bin.as_ref().map(|b| b.exists()).unwrap_or(false);

            let output = if use_bin {
                let mut child = Command::new(bin.unwrap())
                    .env("QUERYA_MCP_ENDPOINT", &ep_path)
                    .stdin(Stdio::piped())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::piped())
                    .spawn()
                    .expect("spawn querya-mcp");
                let mut stdin = child.stdin.take().unwrap();
                let init = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"shim-test","version":"0"}}}"#;
                use tokio::io::AsyncWriteExt as _;
                stdin.write_all(format!("{init}\n").as_bytes()).await.unwrap();
                drop(stdin);
                let out = child.wait_with_output().await.unwrap();
                String::from_utf8_lossy(&out.stdout).into_owned()
            } else {
                // Library-level: connect like the shim would.
                let endpoint = McpEndpoint::read(&ep_path).unwrap().unwrap();
                let mut socket = TcpStream::connect(("127.0.0.1", endpoint.port))
                    .await
                    .unwrap();
                socket
                    .write_all(format!("{}\n", endpoint.token).as_bytes())
                    .await
                    .unwrap();
                let init = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"shim-test","version":"0"}}}"#;
                socket
                    .write_all(format!("{init}\n").as_bytes())
                    .await
                    .unwrap();
                let mut reader = BufReader::new(socket);
                let mut line = String::new();
                reader.read_line(&mut line).await.unwrap();
                line
            };

            assert!(
                output.contains("querya-desktop") || output.contains("protocolVersion"),
                "unexpected shim output: {output}"
            );
            let _ = ctrl.stop_async().await;
        });

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_endpoint_is_none() {
        let missing = std::env::temp_dir().join(format!(
            "querya-mcp-missing-{}-{}.json",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        assert!(McpEndpoint::read(&missing).unwrap().is_none());
    }
}
