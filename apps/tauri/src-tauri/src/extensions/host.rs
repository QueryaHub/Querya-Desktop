//! Extension process host: spawn + handshake/ping/shutdown over NDJSON JSON-RPC.

use super::rpc::{JsonRpcStdioClient, RpcError};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;
use tokio::process::{Child, Command};
use tokio::sync::Mutex;

const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(15);
const SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExtensionSessionInfo {
    pub session_id: String,
    pub extension_id: String,
    pub protocol_version: Value,
    pub executable: String,
}

struct LiveSession {
    info: ExtensionSessionInfo,
    child: Child,
    rpc: Arc<JsonRpcStdioClient>,
}

/// In-process registry of running extension sessions.
#[derive(Default)]
pub struct ExtensionHost {
    sessions: Mutex<HashMap<String, LiveSession>>,
}

impl ExtensionHost {
    pub fn new() -> Self {
        Self::default()
    }

    /// Spawn `executable` with `args`, run `system.handshake`, return session info.
    pub async fn start(
        &self,
        session_id: String,
        executable: PathBuf,
        args: Vec<String>,
        handshake_params: Value,
    ) -> Result<ExtensionSessionInfo, String> {
        {
            let guard = self.sessions.lock().await;
            if guard.contains_key(&session_id) {
                return Err(format!("extension session already running: {session_id}"));
            }
        }

        let mut child = Command::new(&executable)
            .args(&args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| format!("spawn extension process: {e}"))?;

        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| "extension stdin unavailable".to_string())?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| "extension stdout unavailable".to_string())?;

        let rpc = Arc::new(JsonRpcStdioClient::new(stdin, stdout));

        let handshake = rpc
            .send_request_timeout(
                "system.handshake",
                Some(handshake_params),
                HANDSHAKE_TIMEOUT,
            )
            .await
            .map_err(|e| format!("system.handshake failed: {e}"))?;

        let extension_id = handshake
            .get("extensionId")
            .or_else(|| handshake.get("pluginId"))
            .and_then(Value::as_str)
            .unwrap_or("unknown")
            .to_owned();
        let protocol_version = handshake
            .get("protocolVersion")
            .cloned()
            .unwrap_or(json!(1));

        let info = ExtensionSessionInfo {
            session_id: session_id.clone(),
            extension_id,
            protocol_version,
            executable: executable.display().to_string(),
        };

        let mut guard = self.sessions.lock().await;
        guard.insert(
            session_id,
            LiveSession {
                info: info.clone(),
                child,
                rpc,
            },
        );
        Ok(info)
    }

    pub async fn call(
        &self,
        session_id: &str,
        method: &str,
        params: Option<Value>,
    ) -> Result<Value, String> {
        let rpc = {
            let guard = self.sessions.lock().await;
            let session = guard
                .get(session_id)
                .ok_or_else(|| format!("unknown extension session: {session_id}"))?;
            Arc::clone(&session.rpc)
        };
        rpc.send_request(method, params)
            .await
            .map_err(|e: RpcError| e.message)
    }

    pub async fn ping(&self, session_id: &str) -> Result<Value, String> {
        self.call(session_id, "system.ping", None).await
    }

    pub async fn stop(&self, session_id: &str) -> Result<(), String> {
        let mut session = {
            let mut guard = self.sessions.lock().await;
            guard
                .remove(session_id)
                .ok_or_else(|| format!("unknown extension session: {session_id}"))?
        };

        let _ = session
            .rpc
            .send_request_timeout("system.shutdown", None, SHUTDOWN_TIMEOUT)
            .await;
        session.rpc.close().await;

        match tokio::time::timeout(SHUTDOWN_TIMEOUT, session.child.wait()).await {
            Ok(Ok(_)) => Ok(()),
            Ok(Err(e)) => Err(format!("wait for extension exit: {e}")),
            Err(_) => {
                let _ = session.child.kill().await;
                Ok(())
            }
        }
    }

    pub async fn list(&self) -> Vec<ExtensionSessionInfo> {
        let guard = self.sessions.lock().await;
        guard.values().map(|s| s.info.clone()).collect()
    }
}
