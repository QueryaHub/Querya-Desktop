//! Sample hello-panel extension: NDJSON JSON-RPC + SDUI `panel.get` (#1905).
//!
//! Methods: `system.handshake`, `system.ping`, `system.shutdown`, `panel.get`.

use serde_json::{json, Value};
use std::io::{self, BufRead, Write};

fn hello_panel_descriptor() -> Value {
    json!({
        "type": "panel",
        "id": "querya.hello-panel",
        "title": "Hello panel",
        "children": [
            {
                "type": "text",
                "role": "heading",
                "text": "Hello from SDUI"
            },
            {
                "type": "text",
                "role": "body",
                "text": "This panel is rendered by the Querya Vue host from a JSON descriptor."
            },
            {
                "type": "text",
                "role": "muted",
                "text": "Served live by querya-ext-hello-panel over NDJSON RPC."
            },
            { "type": "divider" },
            {
                "type": "stack",
                "direction": "row",
                "gap": "sm",
                "children": [
                    {
                        "type": "button",
                        "id": "hello.dismiss",
                        "label": "Dismiss",
                        "variant": "primary",
                        "action": "dismiss"
                    },
                    {
                        "type": "button",
                        "id": "hello.ping",
                        "label": "Ping host",
                        "variant": "secondary",
                        "action": "ping"
                    }
                ]
            }
        ]
    })
}

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
                    .unwrap_or("querya.hello-panel");
                ok(
                    id,
                    json!({
                        "protocolVersion": 1,
                        "extensionId": extension_id,
                    }),
                )
            }
            "system.ping" => ok(id, json!("pong")),
            "panel.get" => ok(id, hello_panel_descriptor()),
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
