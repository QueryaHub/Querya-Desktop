mod commands;
mod connection;
mod profiles;
mod secrets;
mod ssh_tunnel;
mod staging;

pub use connection::{
    ColumnMeta, ConnectionConfig, ConnectionError, ConnectionId, ConnectionManager,
    ConnectionRegistry, DriverKind, ErdColumn, ErdRelation, ErdSchema, ErdTable, MongoFindResult,
    ObjectTreeProvider, PostgresObjectDetail, QueryEvent, RedisKeyMeta, RedisKeyView, RedisScanPage,
    SchemaObject, SchemaObjectKind, SqlObjectKind, SqlObjectNode, SqliteOverview, TableSchema,
};
pub use profiles::{ConnectionProfile, ProfileStore, ProfileStoreError};
pub use secrets::{KeyringSecretStore, MemorySecretStore, SecretError, SecretStore, SharedSecretStore};
pub use ssh_tunnel::{
    SshTunnelError, SshTunnelInfo, SshTunnelOpenRequest, SshTunnelRegistry,
};
pub use staging::{
    apply_plan_mysql, apply_plan_postgres, apply_plan_sqlite, apply_staging_mysql,
    apply_staging_postgres, apply_staging_sqlite, generate_plan, ApplyError, ApplyResult,
    MutationType, SqlDialect, StagedCellStatus, StagedRowStatus, StagingBuffer, StagingColumnMeta,
    TableMutationPlan, TableMutationStatement, NULL_SENTINEL,
};

use commands::{
    db_apply_staging, db_connect_mongo, db_connect_mysql, db_connect_postgres, db_connect_redis,
    db_connect_sqlite, db_describe_object, db_disconnect, db_erd_schema, db_execute_query,
    db_is_connected, db_list_children, db_list_columns, db_list_schemas, db_list_tables,
    db_postgres_object_detail, db_sqlite_overview, mongo_find, mongo_list_collections,
    mongo_list_databases, mongo_ping, profiles_connect_mongo, profiles_connect_mysql,
    profiles_connect_postgres, profiles_connect_redis, profiles_connect_sqlite, profiles_delete,
    profiles_list, profiles_upsert, redis_get, redis_key_metas, redis_ping, redis_read_key,
    redis_scan, redis_set, ssh_tunnel_close, ssh_tunnel_list, ssh_tunnel_open,
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

/// Build the main window from `tauri.conf.json`, applying OS chrome rules.
///
/// - **macOS:** native traffic lights via `titleBarStyle: Overlay` + `hiddenTitle`
///   (decorations stay on). Custom HTML title bar sits under the system controls.
/// - **Windows / Linux:** undecorated; frontend draws Fluent-style caption buttons.
fn open_main_window(app: &tauri::App) -> tauri::Result<()> {
    use tauri::WebviewWindowBuilder;

    let mut cfg = app
        .config()
        .app
        .windows
        .first()
        .cloned()
        .ok_or_else(|| tauri::Error::WindowNotFound)?;

    // Overlay + hiddenTitle + trafficLightPosition stay in tauri.conf.json (macOS).
    cfg.decorations = cfg!(target_os = "macos");

    WebviewWindowBuilder::from_config(app.handle(), &cfg)?.build()?;
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .manage(ConnectionRegistry::new())
        .manage(KeyringSecretStore::shared())
        .manage(SshTunnelRegistry::new())
        .setup(|app| {
            use tauri::Manager;
            let store = ProfileStore::open_default().map_err(|e| {
                std::io::Error::other(format!("open profile store: {e}"))
            })?;
            app.manage(store);
            open_main_window(app).map_err(|e| {
                std::io::Error::other(format!("open main window: {e}"))
            })?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            app_info,
            host_platform,
            db_connect_sqlite,
            db_connect_postgres,
            db_connect_mysql,
            db_connect_redis,
            db_connect_mongo,
            db_disconnect,
            db_is_connected,
            db_list_schemas,
            db_list_tables,
            db_list_columns,
            db_list_children,
            db_describe_object,
            db_postgres_object_detail,
            db_sqlite_overview,
            db_erd_schema,
            db_execute_query,
            db_apply_staging,
            redis_ping,
            redis_scan,
            redis_get,
            redis_set,
            redis_key_metas,
            redis_read_key,
            mongo_ping,
            mongo_list_databases,
            mongo_list_collections,
            mongo_find,
            profiles_list,
            profiles_upsert,
            profiles_delete,
            profiles_connect_sqlite,
            profiles_connect_postgres,
            profiles_connect_mysql,
            profiles_connect_redis,
            profiles_connect_mongo,
            ssh_tunnel_open,
            ssh_tunnel_close,
            ssh_tunnel_list,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
