//! Minimal echo extension for host round-trip tests (NDJSON JSON-RPC 2.0 over stdio).
//!
//! Methods: `system.handshake`, `system.ping`, `system.shutdown`, `echo.echo`.

use serde_json::{json, Value};
use std::io::{self, BufRead, Write};

fn main() {
    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line in stdin.lock().lines() {
        let Ok(line) = line else {
            break;
        };
        if line.trim().is_empty() {
            continue;
        }
        let Ok(req) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let id = req.get("id").cloned().unwrap_or(Value::Null);
        let method = req.get("method").and_then(Value::as_str).unwrap_or("");
        let params = req.get("params").cloned();

        let response = match method {
            "system.handshake" => {
                let extension_id = params
                    .as_ref()
                    .and_then(|p| p.get("pluginId"))
                    .and_then(Value::as_str)
                    .unwrap_or("querya.echo");
                ok(
                    id,
                    json!({
                        "protocolVersion": 1,
                        "extensionId": extension_id,
                    }),
                )
            }
            "system.ping" => ok(id, json!("pong")),
            "echo.echo" => ok(id, params.unwrap_or(Value::Null)),
            "system.shutdown" => {
                let line = ok(id, json!({ "ok": true }));
                let _ = writeln!(stdout, "{line}");
                let _ = stdout.flush();
                break;
            }
            other => err(id, -32601, format!("method not found: {other}")),
        };

        if writeln!(stdout, "{response}").is_err() {
            break;
        }
        if stdout.flush().is_err() {
            break;
        }
    }
}

fn ok(id: Value, result: Value) -> String {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "result": result,
    })
    .to_string()
}

fn err(id: Value, code: i32, message: String) -> String {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": { "code": code, "message": message },
    })
    .to_string()
}
