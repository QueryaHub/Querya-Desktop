mod commands;
mod connection;
mod profiles;

pub use connection::{
    ColumnMeta, ConnectionConfig, ConnectionError, ConnectionId, ConnectionManager,
    ConnectionRegistry, DriverKind, ObjectTreeProvider, QueryEvent, SchemaObject, SchemaObjectKind,
    SqlObjectKind, SqlObjectNode, SqliteOverview, TableSchema,
};
pub use profiles::{ConnectionProfile, ProfileStore, ProfileStoreError};

use commands::{
    db_connect_postgres, db_connect_sqlite, db_describe_object, db_disconnect, db_execute_query,
    db_is_connected, db_list_children, db_list_columns, db_list_schemas, db_list_tables,
    db_sqlite_overview, profiles_connect_sqlite, profiles_delete, profiles_list, profiles_upsert,
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
        .setup(|app| {
            use tauri::Manager;
            let store = ProfileStore::open_default().map_err(|e| {
                std::io::Error::other(format!("open profile store: {e}"))
            })?;
            app.manage(store);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            app_info,
            host_platform,
            db_connect_sqlite,
            db_connect_postgres,
            db_disconnect,
            db_is_connected,
            db_list_schemas,
            db_list_tables,
            db_list_columns,
            db_list_children,
            db_describe_object,
            db_sqlite_overview,
            db_execute_query,
            profiles_list,
            profiles_upsert,
            profiles_delete,
            profiles_connect_sqlite,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
