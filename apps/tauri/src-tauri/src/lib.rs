mod commands;
mod connection;

pub use connection::{
    ColumnMeta, ConnectionConfig, ConnectionError, ConnectionId, ConnectionManager,
    ConnectionRegistry, DriverKind, SchemaObject, SchemaObjectKind, TableSchema,
};

use commands::{
    db_connect_sqlite, db_disconnect, db_is_connected, db_list_columns, db_list_schemas,
    db_list_tables,
};

#[tauri::command]
fn app_info() -> serde_json::Value {
    serde_json::json!({
        "name": "Querya",
        "stack": "tauri2-vue3",
        "version": env!("CARGO_PKG_VERSION"),
        "os": std::env::consts::OS,
    })
}

/// Canonical host OS for chrome layout (`macos` / `windows` / `linux` / other).
#[tauri::command]
fn host_platform() -> String {
    match std::env::consts::OS {
        "macos" => "macos".into(),
        "windows" => "windows".into(),
        "linux" => "linux".into(),
        other => other.into(),
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .manage(ConnectionRegistry::new())
        .invoke_handler(tauri::generate_handler![
            app_info,
            host_platform,
            db_connect_sqlite,
            db_disconnect,
            db_is_connected,
            db_list_schemas,
            db_list_tables,
            db_list_columns,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
