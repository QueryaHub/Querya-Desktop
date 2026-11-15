//! Query result streaming events (shared IPC shape).

use serde::Serialize;

/// Events pushed over a Tauri [`tauri::ipc::Channel`] during `db_execute_query`.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum QueryEvent {
    Columns {
        names: Vec<String>,
    },
    Rows {
        rows: Vec<Vec<serde_json::Value>>,
        offset: u64,
    },
    Done {
        row_count: u64,
        truncated: bool,
        #[serde(skip_serializing_if = "Option::is_none")]
        affected_rows: Option<u64>,
        elapsed_ms: u64,
    },
    Error {
        message: String,
    },
}
