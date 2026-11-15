use crate::connection::{
    ConnectionConfig, ConnectionError, ConnectionId, ConnectionManager, ConnectionRegistry,
    ErdSchema, PostgresObjectDetail, RedisScanPage, SchemaObject, SchemaObjectKind, SqlObjectKind,
    SqlObjectNode, SqliteOverview, TableSchema,
};
use crate::profiles::{ConnectionProfile, ProfileStore, ProfileStoreError};
use crate::secrets::SharedSecretStore;
use crate::staging::{apply_staging_request, ApplyResult, StagingApplyRequest};
use serde::Deserialize;
use tauri::ipc::Channel;
use tauri::State;

/// Bundled IPC args for Postgres/MySQL save+connect (keeps clippy under the limit).
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectPostgresRequest {
    pub name: String,
    pub host: String,
    pub port: u16,
    pub database: String,
    pub user: String,
    pub password: Option<String>,
    pub folder_id: Option<String>,
    pub id: Option<String>,
}

/// Same shape as Postgres — separate type so Tauri command names stay clear.
pub type ConnectMysqlRequest = ConnectPostgresRequest;

/// Redis save+connect args (`database` is the logical DB index as a string).
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectRedisRequest {
    pub name: String,
    pub host: String,
    pub port: u16,
    pub database: Option<String>,
    pub username: Option<String>,
    pub password: Option<String>,
    pub folder_id: Option<String>,
    pub id: Option<String>,
}

#[tauri::command]
pub fn db_connect_sqlite(
    path: String,
    id: Option<String>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<ConnectionId, ConnectionError> {
    registry.connect(ConnectionConfig::Sqlite { path, id })
}

#[tauri::command]
pub fn db_connect_postgres(
    host: String,
    port: u16,
    database: String,
    user: String,
    password: Option<String>,
    id: Option<String>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<ConnectionId, ConnectionError> {
    registry.connect(ConnectionConfig::Postgres {
        host,
        port,
        database,
        user,
        password,
        id,
    })
}

#[tauri::command]
pub fn db_connect_mysql(
    host: String,
    port: u16,
    database: String,
    user: String,
    password: Option<String>,
    id: Option<String>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<ConnectionId, ConnectionError> {
    registry.connect(ConnectionConfig::Mysql {
        host,
        port,
        database,
        user,
        password,
        id,
    })
}

#[tauri::command]
pub fn db_connect_redis(
    host: String,
    port: u16,
    password: Option<String>,
    username: Option<String>,
    db: Option<u8>,
    id: Option<String>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<ConnectionId, ConnectionError> {
    registry.connect(ConnectionConfig::Redis {
        host,
        port,
        password,
        username,
        db,
        id,
    })
}

#[tauri::command]
pub fn redis_ping(
    id: ConnectionId,
    registry: State<'_, ConnectionRegistry>,
) -> Result<String, ConnectionError> {
    registry.with_redis(&id, |s| s.ping())
}

#[tauri::command]
pub fn redis_scan(
    id: ConnectionId,
    cursor: Option<u64>,
    pattern: Option<String>,
    count: Option<u32>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<RedisScanPage, ConnectionError> {
    registry.with_redis(&id, |s| {
        s.scan(
            cursor.unwrap_or(0),
            pattern.as_deref(),
            count.map(|n| n as usize),
        )
    })
}

#[tauri::command]
pub fn redis_get(
    id: ConnectionId,
    key: String,
    registry: State<'_, ConnectionRegistry>,
) -> Result<Option<String>, ConnectionError> {
    registry.with_redis(&id, |s| s.get(&key))
}

#[tauri::command]
pub fn redis_set(
    id: ConnectionId,
    key: String,
    value: String,
    registry: State<'_, ConnectionRegistry>,
) -> Result<(), ConnectionError> {
    registry.with_redis(&id, |s| s.set(&key, &value))
}

#[tauri::command]
pub fn profiles_list(
    store: State<'_, ProfileStore>,
) -> Result<Vec<ConnectionProfile>, ProfileStoreError> {
    store.list()
}

#[tauri::command]
pub fn profiles_upsert(
    profile: ConnectionProfile,
    store: State<'_, ProfileStore>,
) -> Result<ConnectionProfile, ProfileStoreError> {
    let mut profile = profile;
    if profile.created_at.trim().is_empty() {
        profile = ConnectionProfile {
            created_at: profile.updated_at.clone(),
            ..profile
        };
    }
    profile.touch();
    store.upsert(&profile)?;
    Ok(profile)
}

#[tauri::command]
pub fn profiles_delete(
    id: String,
    store: State<'_, ProfileStore>,
    secrets: State<'_, SharedSecretStore>,
) -> Result<bool, ProfileStoreError> {
    // Best-effort secret cleanup — profile row is source of truth for "gone".
    let _ = secrets.delete_password(&id);
    store.delete(&id)
}

/// Save (or update) a SQLite profile and open a live session under the same id.
#[tauri::command]
pub fn profiles_connect_sqlite(
    name: String,
    path: String,
    folder_id: Option<String>,
    id: Option<String>,
    store: State<'_, ProfileStore>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<ConnectionProfile, ConnectionError> {
    let display_name = {
        let t = name.trim();
        if t.is_empty() {
            path.clone()
        } else {
            t.to_owned()
        }
    };

    let mut profile = match id.filter(|s| !s.trim().is_empty()) {
        Some(existing_id) => store
            .get(&existing_id)
            .map_err(|e| ConnectionError::io(e.to_string()))?
            .map(|mut p| {
                p.name = display_name.clone();
                p.path = Some(path.clone());
                p.folder_id = folder_id.clone();
                p.driver = "sqlite".into();
                p
            })
            .unwrap_or_else(|| {
                let mut p = ConnectionProfile::new_sqlite(display_name.clone(), path.clone());
                p.id = existing_id;
                p.folder_id = folder_id.clone();
                p
            }),
        None => {
            let mut p = ConnectionProfile::new_sqlite(display_name, path.clone());
            p.folder_id = folder_id;
            p
        }
    };
    profile.touch();
    store
        .upsert(&profile)
        .map_err(|e| ConnectionError::io(e.to_string()))?;

    if !registry.is_connected(&ConnectionId::from(profile.id.as_str())) {
        registry.connect(ConnectionConfig::Sqlite {
            path,
            id: Some(profile.id.clone()),
        })?;
    }
    Ok(profile)
}

/// Save Postgres profile metadata (no password) and open a live session.
#[tauri::command]
pub fn profiles_connect_postgres(
    request: ConnectPostgresRequest,
    store: State<'_, ProfileStore>,
    secrets: State<'_, SharedSecretStore>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<ConnectionProfile, ConnectionError> {
    let ConnectPostgresRequest {
        name,
        host,
        port,
        database,
        user,
        password,
        folder_id,
        id,
    } = request;

    let display_name = {
        let t = name.trim();
        if t.is_empty() {
            format!("{user}@{host}/{database}")
        } else {
            t.to_owned()
        }
    };

    let mut profile = match id.filter(|s| !s.trim().is_empty()) {
        Some(existing_id) => store
            .get(&existing_id)
            .map_err(|e| ConnectionError::io(e.to_string()))?
            .map(|mut p| {
                p.name = display_name.clone();
                p.host = Some(host.clone());
                p.port = Some(i64::from(port));
                p.database_name = Some(database.clone());
                p.username = Some(user.clone());
                p.folder_id = folder_id.clone();
                p.driver = "postgres".into();
                p.path = None;
                p
            })
            .unwrap_or_else(|| {
                let mut p = ConnectionProfile::new_postgres(
                    display_name.clone(),
                    host.clone(),
                    port,
                    database.clone(),
                    user.clone(),
                );
                p.id = existing_id;
                p.folder_id = folder_id.clone();
                p
            }),
        None => {
            let mut p = ConnectionProfile::new_postgres(
                display_name,
                host.clone(),
                port,
                database.clone(),
                user.clone(),
            );
            p.folder_id = folder_id;
            p
        }
    };
    profile.touch();
    store
        .upsert(&profile)
        .map_err(|e| ConnectionError::io(e.to_string()))?;

    // Resolve password: explicit form value wins; else OS keyring (#1878).
    let password = match password {
        Some(p) => {
            secrets
                .set_password(&profile.id, &p)
                .map_err(|e| ConnectionError::io(format!("keyring write: {e}")))?;
            Some(p)
        }
        None => secrets
            .get_password(&profile.id)
            .map_err(|e| ConnectionError::io(format!("keyring read: {e}")))?,
    };

    if !registry.is_connected(&ConnectionId::from(profile.id.as_str())) {
        registry.connect(ConnectionConfig::Postgres {
            host,
            port,
            database,
            user,
            password,
            id: Some(profile.id.clone()),
        })?;
    }
    Ok(profile)
}

/// Save MySQL profile metadata (no password) and open a live session.
#[tauri::command]
pub fn profiles_connect_mysql(
    request: ConnectMysqlRequest,
    store: State<'_, ProfileStore>,
    secrets: State<'_, SharedSecretStore>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<ConnectionProfile, ConnectionError> {
    let ConnectMysqlRequest {
        name,
        host,
        port,
        database,
        user,
        password,
        folder_id,
        id,
    } = request;

    let display_name = {
        let t = name.trim();
        if t.is_empty() {
            format!("{user}@{host}/{database}")
        } else {
            t.to_owned()
        }
    };

    let mut profile = match id.filter(|s| !s.trim().is_empty()) {
        Some(existing_id) => store
            .get(&existing_id)
            .map_err(|e| ConnectionError::io(e.to_string()))?
            .map(|mut p| {
                p.name = display_name.clone();
                p.host = Some(host.clone());
                p.port = Some(i64::from(port));
                p.database_name = Some(database.clone());
                p.username = Some(user.clone());
                p.folder_id = folder_id.clone();
                p.driver = "mysql".into();
                p.path = None;
                p
            })
            .unwrap_or_else(|| {
                let mut p = ConnectionProfile::new_mysql(
                    display_name.clone(),
                    host.clone(),
                    port,
                    database.clone(),
                    user.clone(),
                );
                p.id = existing_id;
                p.folder_id = folder_id.clone();
                p
            }),
        None => {
            let mut p = ConnectionProfile::new_mysql(
                display_name,
                host.clone(),
                port,
                database.clone(),
                user.clone(),
            );
            p.folder_id = folder_id;
            p
        }
    };
    profile.touch();
    store
        .upsert(&profile)
        .map_err(|e| ConnectionError::io(e.to_string()))?;

    let password = match password {
        Some(p) => {
            secrets
                .set_password(&profile.id, &p)
                .map_err(|e| ConnectionError::io(format!("keyring write: {e}")))?;
            Some(p)
        }
        None => secrets
            .get_password(&profile.id)
            .map_err(|e| ConnectionError::io(format!("keyring read: {e}")))?,
    };

    if !registry.is_connected(&ConnectionId::from(profile.id.as_str())) {
        registry.connect(ConnectionConfig::Mysql {
            host,
            port,
            database,
            user,
            password,
            id: Some(profile.id.clone()),
        })?;
    }
    Ok(profile)
}

/// Save Redis profile metadata (no password) and open a live session.
#[tauri::command]
pub fn profiles_connect_redis(
    request: ConnectRedisRequest,
    store: State<'_, ProfileStore>,
    secrets: State<'_, SharedSecretStore>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<ConnectionProfile, ConnectionError> {
    let ConnectRedisRequest {
        name,
        host,
        port,
        database,
        username,
        password,
        folder_id,
        id,
    } = request;

    let db: u8 = database
        .as_deref()
        .unwrap_or("0")
        .trim()
        .parse()
        .unwrap_or(0);
    let user = username
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned);

    let display_name = {
        let t = name.trim();
        if t.is_empty() {
            format!("{host}:{port}/{db}")
        } else {
            t.to_owned()
        }
    };

    let mut profile = match id.filter(|s| !s.trim().is_empty()) {
        Some(existing_id) => store
            .get(&existing_id)
            .map_err(|e| ConnectionError::io(e.to_string()))?
            .map(|mut p| {
                p.name = display_name.clone();
                p.host = Some(host.clone());
                p.port = Some(i64::from(port));
                p.database_name = Some(db.to_string());
                p.username = user.clone();
                p.folder_id = folder_id.clone();
                p.driver = "redis".into();
                p.path = None;
                p
            })
            .unwrap_or_else(|| {
                let mut p = ConnectionProfile::new_redis(
                    display_name.clone(),
                    host.clone(),
                    port,
                    db,
                    user.clone(),
                );
                p.id = existing_id;
                p.folder_id = folder_id.clone();
                p
            }),
        None => {
            let mut p =
                ConnectionProfile::new_redis(display_name, host.clone(), port, db, user.clone());
            p.folder_id = folder_id;
            p
        }
    };
    profile.touch();
    store
        .upsert(&profile)
        .map_err(|e| ConnectionError::io(e.to_string()))?;

    let password = match password {
        Some(p) => {
            secrets
                .set_password(&profile.id, &p)
                .map_err(|e| ConnectionError::io(format!("keyring write: {e}")))?;
            Some(p)
        }
        None => secrets
            .get_password(&profile.id)
            .map_err(|e| ConnectionError::io(format!("keyring read: {e}")))?,
    };

    if !registry.is_connected(&ConnectionId::from(profile.id.as_str())) {
        registry.connect(ConnectionConfig::Redis {
            host,
            port,
            password,
            username: user,
            db: Some(db),
            id: Some(profile.id.clone()),
        })?;
    }
    Ok(profile)
}

#[tauri::command]
pub fn db_disconnect(
    id: ConnectionId,
    registry: State<'_, ConnectionRegistry>,
) -> Result<(), ConnectionError> {
    registry.disconnect(&id)
}

#[tauri::command]
pub fn db_is_connected(id: ConnectionId, registry: State<'_, ConnectionRegistry>) -> bool {
    registry.is_connected(&id)
}

/// Universal object tree: `parent_id = null` → schemas; schema → relations; table/view → columns.
#[tauri::command]
pub fn db_list_children(
    id: ConnectionId,
    parent_id: Option<String>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<Vec<SqlObjectNode>, ConnectionError> {
    registry.list_children(&id, parent_id.as_deref())
}

/// Describe a table/view by stable object id (`sqlite:table:main:users`).
#[tauri::command]
pub fn db_describe_object(
    id: ConnectionId,
    object_id: String,
    registry: State<'_, ConnectionRegistry>,
) -> Result<TableSchema, ConnectionError> {
    registry.describe_object(&id, &object_id)
}

/// Postgres function / sequence / index / trigger / type detail (or schema listing).
#[tauri::command]
pub fn db_postgres_object_detail(
    id: ConnectionId,
    object_id: String,
    registry: State<'_, ConnectionRegistry>,
) -> Result<PostgresObjectDetail, ConnectionError> {
    registry.postgres_object_detail(&id, &object_id)
}

/// Shim: schema names via object tree roots.
#[tauri::command]
pub fn db_list_schemas(
    id: ConnectionId,
    registry: State<'_, ConnectionRegistry>,
) -> Result<Vec<String>, ConnectionError> {
    Ok(registry
        .list_children(&id, None)?
        .into_iter()
        .map(|n| n.name)
        .collect())
}

/// Shim: flat tables/views under `main` (legacy callers).
#[tauri::command]
pub fn db_list_tables(
    id: ConnectionId,
    registry: State<'_, ConnectionRegistry>,
) -> Result<Vec<SchemaObject>, ConnectionError> {
    let main = registry
        .list_children(&id, None)?
        .into_iter()
        .find(|n| n.name == "main")
        .ok_or_else(|| ConnectionError::invalid_config("sqlite schema main missing"))?;
    Ok(registry
        .list_children(&id, Some(&main.id))?
        .into_iter()
        .filter_map(|n| {
            let kind = match n.kind {
                SqlObjectKind::Table => SchemaObjectKind::Table,
                SqlObjectKind::View => SchemaObjectKind::View,
                _ => return None,
            };
            Some(SchemaObject {
                name: n.name,
                kind,
                schema: n.schema,
            })
        })
        .collect())
}

/// Shim: columns by table/view name (legacy callers).
#[tauri::command]
pub fn db_list_columns(
    id: ConnectionId,
    table: String,
    registry: State<'_, ConnectionRegistry>,
) -> Result<TableSchema, ConnectionError> {
    registry.with_sqlite(&id, |s| s.list_columns(&table))
}

/// SQLite Overview / Database Info (Flutter `SqliteOverviewTab`).
#[tauri::command]
pub fn db_sqlite_overview(
    id: ConnectionId,
    registry: State<'_, ConnectionRegistry>,
) -> Result<SqliteOverview, ConnectionError> {
    registry.with_sqlite(&id, |s| s.database_overview())
}

/// ER diagram catalog: tables/views + FK edges (optional neighbourhood).
#[tauri::command]
pub fn db_erd_schema(
    id: ConnectionId,
    schema: Option<String>,
    focus: Option<String>,
    depth: Option<u32>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<ErdSchema, ConnectionError> {
    registry.erd_schema(
        &id,
        schema.as_deref(),
        focus.as_deref(),
        depth,
    )
}

/// Execute SQL and stream `QueryEvent` batches over `on_event`.
/// Failures return as the invoke `Err` only (no dual channel `Error` event).
///
/// Pass `confirmed: true` after the UI acknowledged a
/// [`ConnectionError::NeedsConfirmation`] for DROP / TRUNCATE / unconditional
/// DELETE|UPDATE.
#[tauri::command]
pub fn db_execute_query(
    id: ConnectionId,
    sql: String,
    limit: Option<u32>,
    confirmed: Option<bool>,
    on_event: Channel<crate::connection::QueryEvent>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<(), ConnectionError> {
    let limit = limit.map(|n| n as usize);
    let confirmed = confirmed.unwrap_or(false);
    registry.execute_query(&id, &sql, limit, confirmed, |ev| {
        on_event
            .send(ev)
            .map_err(|e| ConnectionError::io(format!("query channel closed: {e}")))
    })
}

/// Apply frontend staging edits in a single transaction (#1891).
#[tauri::command]
pub fn db_apply_staging(
    request: StagingApplyRequest,
    registry: State<'_, ConnectionRegistry>,
) -> Result<ApplyResult, ConnectionError> {
    apply_staging_request(&registry, request)
}
