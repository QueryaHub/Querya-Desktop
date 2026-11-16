//! Loopback TCP host with token handshake (Flutter `McpSocketHost` parity).

use super::endpoint::McpEndpoint;
use super::server::QueryaMcpServer;
use rmcp::ServiceExt;
use serde::Serialize;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::JoinHandle;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpStatus {
    pub running: bool,
    pub port: Option<u16>,
    pub session_count: u32,
    pub endpoint_path: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpError {
    pub message: String,
}

impl McpError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl std::fmt::Display for McpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for McpError {}

struct RunningHost {
    port: u16,
    endpoint_path: PathBuf,
    session_count: Arc<AtomicUsize>,
    stop: Arc<AtomicBool>,
    accept_task: JoinHandle<()>,
}

/// Starts / stops the in-process MCP loopback server.
#[derive(Default)]
pub struct McpController {
    inner: Mutex<Option<RunningHost>>,
}

impl McpController {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn status(&self) -> Result<McpStatus, McpError> {
        let guard = self
            .inner
            .lock()
            .map_err(|_| McpError::new("mcp controller lock poisoned"))?;
        let path = McpEndpoint::default_path();
        match guard.as_ref() {
            Some(h) => Ok(McpStatus {
                running: true,
                port: Some(h.port),
                session_count: h.session_count.load(Ordering::SeqCst) as u32,
                endpoint_path: h.endpoint_path.display().to_string(),
            }),
            None => Ok(McpStatus {
                running: false,
                port: None,
                session_count: 0,
                endpoint_path: path.display().to_string(),
            }),
        }
    }

    pub fn start(&self) -> Result<McpStatus, McpError> {
        crate::connection::runtime::block_on(self.start_async(None))
    }

    pub fn stop(&self) -> Result<McpStatus, McpError> {
        crate::connection::runtime::block_on(self.stop_async())
    }

    async fn start_async(
        &self,
        endpoint_path: Option<PathBuf>,
    ) -> Result<McpStatus, McpError> {
        {
            let guard = self
                .inner
                .lock()
                .map_err(|_| McpError::new("mcp controller lock poisoned"))?;
            if guard.is_some() {
                drop(guard);
                return self.status();
            }
        }

        let listener = TcpListener::bind(("127.0.0.1", 0))
            .await
            .map_err(|e| McpError::new(format!("bind MCP loopback: {e}")))?;
        let port = listener
            .local_addr()
            .map_err(|e| McpError::new(format!("MCP local addr: {e}")))?
            .port();
        let token = McpEndpoint::new_token();
        let endpoint_path = endpoint_path.unwrap_or_else(McpEndpoint::default_path);
        let endpoint = McpEndpoint {
            port,
            token: token.clone(),
            pid: std::process::id(),
            version: env!("CARGO_PKG_VERSION").into(),
        };
        endpoint
            .write(&endpoint_path)
            .map_err(|e| McpError::new(format!("write MCP endpoint: {e}")))?;

        let stop = Arc::new(AtomicBool::new(false));
        let session_count = Arc::new(AtomicUsize::new(0));
        let stop_flag = Arc::clone(&stop);
        let sessions = Arc::clone(&session_count);
        let accept_token = token.clone();

        let accept_task = tokio::spawn(async move {
            loop {
                if stop_flag.load(Ordering::SeqCst) {
                    break;
                }
                let accept =
                    tokio::time::timeout(Duration::from_millis(400), listener.accept()).await;
                match accept {
                    Ok(Ok((socket, _))) => {
                        let token = accept_token.clone();
                        let sessions = Arc::clone(&sessions);
                        let stop_flag = Arc::clone(&stop_flag);
                        tokio::spawn(async move {
                            if let Err(e) =
                                handle_connection(socket, token, sessions, stop_flag).await
                            {
                                eprintln!("mcp session error: {e}");
                            }
                        });
                    }
                    Ok(Err(_)) => break,
                    Err(_) => continue,
                }
            }
        });

        let mut guard = self
            .inner
            .lock()
            .map_err(|_| McpError::new("mcp controller lock poisoned"))?;
        *guard = Some(RunningHost {
            port,
            endpoint_path: endpoint_path.clone(),
            session_count,
            stop,
            accept_task,
        });
        drop(guard);
        self.status()
    }

    async fn stop_async(&self) -> Result<McpStatus, McpError> {
        let running = {
            let mut guard = self
                .inner
                .lock()
                .map_err(|_| McpError::new("mcp controller lock poisoned"))?;
            guard.take()
        };
        if let Some(h) = running {
            h.stop.store(true, Ordering::SeqCst);
            h.accept_task.abort();
            let _ = McpEndpoint::clear(&h.endpoint_path);
        }
        self.status()
    }
}

async fn handle_connection(
    mut socket: TcpStream,
    expected_token: String,
    session_count: Arc<AtomicUsize>,
    stop: Arc<AtomicBool>,
) -> Result<(), McpError> {
    if stop.load(Ordering::SeqCst) {
        return Ok(());
    }
    let line = read_handshake_line(&mut socket).await?;
    if !McpEndpoint::tokens_equal(line.trim(), &expected_token) {
        let err = serde_json::json!({
            "jsonrpc": "2.0",
            "id": null,
            "error": {
                "code": -32001,
                "message": "Invalid Querya MCP token. Restart the MCP client."
            }
        });
        let _ = socket
            .write_all(format!("{err}\n").as_bytes())
            .await;
        let _ = socket.shutdown().await;
        return Err(McpError::new("invalid MCP token"));
    }

    session_count.fetch_add(1, Ordering::SeqCst);
    let _guard = SessionGuard(session_count);

    let server = QueryaMcpServer::new();
    let running = server
        .serve(socket)
        .await
        .map_err(|e| McpError::new(format!("MCP serve failed: {e}")))?;
    let _ = running.waiting().await;
    Ok(())
}

struct SessionGuard(Arc<AtomicUsize>);

impl Drop for SessionGuard {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::SeqCst);
    }
}

async fn read_handshake_line(socket: &mut TcpStream) -> Result<String, McpError> {
    let mut buf = Vec::with_capacity(64);
    let mut byte = [0u8; 1];
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    loop {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        if remaining.is_zero() {
            return Err(McpError::new("MCP handshake timed out"));
        }
        tokio::time::timeout(remaining, socket.read_exact(&mut byte))
            .await
            .map_err(|_| McpError::new("MCP handshake timed out"))?
            .map_err(|e| McpError::new(format!("MCP handshake read: {e}")))?;
        if byte[0] == b'\n' {
            break;
        }
        if byte[0] != b'\r' {
            buf.push(byte[0]);
        }
        if buf.len() > 4096 {
            return Err(McpError::new("MCP handshake too long"));
        }
    }
    String::from_utf8(buf).map_err(|_| McpError::new("MCP handshake is not UTF-8"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncBufReadExt, BufReader};

    #[test]
    fn start_initialize_ping_stop() {
        if std::env::var_os("QUERYA_SKIP_MCP").is_some() {
            eprintln!("skip mcp live test (QUERYA_SKIP_MCP)");
            return;
        }

        let dir = std::env::temp_dir().join(format!(
            "querya-mcp-host-{}-{}",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        let ep_path = dir.join("mcp-endpoint.json");
        std::fs::create_dir_all(&dir).unwrap();

        crate::connection::runtime::block_on(async {
            let ctrl = McpController::new();
            let status = ctrl
                .start_async(Some(ep_path.clone()))
                .await
                .expect("start mcp");
            assert!(status.running);
            let port = status.port.expect("port");

            let endpoint = McpEndpoint::read(&ep_path)
                .unwrap()
                .expect("endpoint file");
            assert_eq!(endpoint.port, port);

            let mut stream = TcpStream::connect(("127.0.0.1", port))
                .await
                .expect("connect");
            stream
                .write_all(format!("{}\n", endpoint.token).as_bytes())
                .await
                .unwrap();

            let init = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"querya-test","version":"0.0.1"}}}"#;
            stream
                .write_all(format!("{init}\n").as_bytes())
                .await
                .unwrap();

            let mut reader = BufReader::new(stream);
            let mut line = String::new();
            tokio::time::timeout(Duration::from_secs(3), reader.read_line(&mut line))
                .await
                .expect("init timeout")
                .expect("init read");
            let v: serde_json::Value = serde_json::from_str(line.trim()).unwrap();
            assert_eq!(v["id"], 1);
            assert_eq!(
                v["result"]["serverInfo"]["name"].as_str().unwrap(),
                "querya-desktop"
            );
            assert!(v["result"]["protocolVersion"].is_string());

            let initialized = r#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#;
            reader
                .get_mut()
                .write_all(format!("{initialized}\n").as_bytes())
                .await
                .unwrap();

            let ping = r#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#;
            reader
                .get_mut()
                .write_all(format!("{ping}\n").as_bytes())
                .await
                .unwrap();
            line.clear();
            tokio::time::timeout(Duration::from_secs(3), reader.read_line(&mut line))
                .await
                .expect("ping timeout")
                .expect("ping read");
            let ping_v: serde_json::Value = serde_json::from_str(line.trim()).unwrap();
            assert_eq!(ping_v["id"], 2);
            assert!(ping_v.get("result").is_some());

            let stopped = ctrl.stop_async().await.expect("stop");
            assert!(!stopped.running);
            assert!(McpEndpoint::read(&ep_path).unwrap().is_none());
        });

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn rejects_bad_token() {
        if std::env::var_os("QUERYA_SKIP_MCP").is_some() {
            return;
        }
        let dir = std::env::temp_dir().join(format!(
            "querya-mcp-bad-{}-{}",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        let ep_path = dir.join("mcp-endpoint.json");
        std::fs::create_dir_all(&dir).unwrap();

        crate::connection::runtime::block_on(async {
            let ctrl = McpController::new();
            let status = ctrl.start_async(Some(ep_path.clone())).await.unwrap();
            let port = status.port.unwrap();
            let mut stream = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
            stream.write_all(b"not-the-token\n").await.unwrap();
            let mut reader = BufReader::new(stream);
            let mut line = String::new();
            tokio::time::timeout(Duration::from_secs(3), reader.read_line(&mut line))
                .await
                .unwrap()
                .unwrap();
            let v: serde_json::Value = serde_json::from_str(line.trim()).unwrap();
            assert_eq!(v["error"]["code"], -32001);
            let _ = ctrl.stop_async().await;
        });

        let _ = std::fs::remove_dir_all(&dir);
    }
}
