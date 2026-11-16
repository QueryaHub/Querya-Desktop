//! NDJSON JSON-RPC 2.0 client over a child process stdio (Flutter parity).

use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{ChildStdin, ChildStdout};
use tokio::sync::{oneshot, Mutex};
use tokio::task::JoinHandle;

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(10);
const MAX_LINE_BYTES: usize = 4 * 1024 * 1024;

#[derive(Debug)]
pub struct RpcError {
    pub message: String,
}

impl RpcError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl std::fmt::Display for RpcError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for RpcError {}

type PendingMap = HashMap<i64, oneshot::Sender<Result<Value, RpcError>>>;

/// Host-side NDJSON JSON-RPC client (one request/response line).
pub struct JsonRpcStdioClient {
    stdin: Arc<Mutex<ChildStdin>>,
    next_id: AtomicI64,
    pending: Arc<Mutex<PendingMap>>,
    reader_task: JoinHandle<()>,
    closed: Arc<std::sync::atomic::AtomicBool>,
}

impl JsonRpcStdioClient {
    pub fn new(stdin: ChildStdin, stdout: ChildStdout) -> Self {
        let pending: Arc<Mutex<PendingMap>> = Arc::new(Mutex::new(HashMap::new()));
        let pending_reader = Arc::clone(&pending);
        let closed = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let closed_reader = Arc::clone(&closed);

        let reader_task = tokio::spawn(async move {
            let mut lines = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                if closed_reader.load(Ordering::SeqCst) {
                    break;
                }
                if line.len() > MAX_LINE_BYTES {
                    fail_all(
                        &pending_reader,
                        RpcError::new("JSON-RPC response line exceeds max size"),
                    )
                    .await;
                    break;
                }
                let Ok(msg) = serde_json::from_str::<Value>(&line) else {
                    continue;
                };
                let Some(id) = msg.get("id").and_then(Value::as_i64) else {
                    continue;
                };
                let result = if let Some(err) = msg.get("error") {
                    Err(RpcError::new(
                        err.get("message")
                            .and_then(Value::as_str)
                            .unwrap_or("JSON-RPC error")
                            .to_owned(),
                    ))
                } else {
                    Ok(msg.get("result").cloned().unwrap_or(Value::Null))
                };
                let mut guard = pending_reader.lock().await;
                if let Some(tx) = guard.remove(&id) {
                    let _ = tx.send(result);
                }
            }
            fail_all(
                &pending_reader,
                RpcError::new("extension process stdout closed"),
            )
            .await;
        });

        Self {
            stdin: Arc::new(Mutex::new(stdin)),
            next_id: AtomicI64::new(1),
            pending,
            reader_task,
            closed,
        }
    }

    pub async fn send_request(
        &self,
        method: &str,
        params: Option<Value>,
    ) -> Result<Value, RpcError> {
        self.send_request_timeout(method, params, DEFAULT_TIMEOUT)
            .await
    }

    pub async fn send_request_timeout(
        &self,
        method: &str,
        params: Option<Value>,
        timeout: Duration,
    ) -> Result<Value, RpcError> {
        if self.closed.load(Ordering::SeqCst) {
            return Err(RpcError::new("JSON-RPC client is closed"));
        }
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let (tx, rx) = oneshot::channel();
        {
            let mut guard = self.pending.lock().await;
            guard.insert(id, tx);
        }

        let mut payload = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
        });
        if let Some(p) = params {
            payload["params"] = p;
        }

        {
            let mut stdin = self.stdin.lock().await;
            let line = format!("{payload}\n");
            stdin
                .write_all(line.as_bytes())
                .await
                .map_err(|e| RpcError::new(format!("write RPC request: {e}")))?;
            stdin
                .flush()
                .await
                .map_err(|e| RpcError::new(format!("flush RPC request: {e}")))?;
        }

        match tokio::time::timeout(timeout, rx).await {
            Ok(Ok(result)) => result,
            Ok(Err(_)) => Err(RpcError::new("RPC response channel dropped")),
            Err(_) => {
                let mut guard = self.pending.lock().await;
                guard.remove(&id);
                Err(RpcError::new(format!(
                    "JSON-RPC request \"{method}\" timed out after {timeout:?}"
                )))
            }
        }
    }

    pub async fn close(&self) {
        if self
            .closed
            .swap(true, Ordering::SeqCst)
        {
            return;
        }
        fail_all(&self.pending, RpcError::new("JSON-RPC client closed")).await;
        self.reader_task.abort();
    }
}

async fn fail_all(pending: &Arc<Mutex<PendingMap>>, err: RpcError) {
    let mut guard = pending.lock().await;
    for (_, tx) in guard.drain() {
        let _ = tx.send(Err(RpcError::new(err.message.clone())));
    }
}
