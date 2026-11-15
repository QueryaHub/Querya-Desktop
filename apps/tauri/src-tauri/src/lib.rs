mod connection;

pub use connection::{
    ConnectionConfig, ConnectionError, ConnectionId, ConnectionManager, ConnectionRegistry,
    DriverKind,
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
        .manage(ConnectionRegistry::new())
        .invoke_handler(tauri::generate_handler![app_info, host_platform])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
