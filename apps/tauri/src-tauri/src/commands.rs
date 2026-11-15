use crate::connection::{
    ConnectionConfig, ConnectionError, ConnectionId, ConnectionManager, ConnectionRegistry,
    SchemaObject, SchemaObjectKind, SqlObjectKind, SqlObjectNode, TableSchema,
};
use tauri::ipc::Channel;
use tauri::State;

#[tauri::command]
pub fn db_connect_sqlite(
    path: String,
    registry: State<'_, ConnectionRegistry>,
) -> Result<ConnectionId, ConnectionError> {
    registry.connect(ConnectionConfig::Sqlite { path })
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

/// Execute SQL and stream `QueryEvent` batches over `on_event`.
/// Failures return as the invoke `Err` only (no dual channel `Error` event).
#[tauri::command]
pub fn db_execute_query(
    id: ConnectionId,
    sql: String,
    limit: Option<u32>,
    on_event: Channel<crate::connection::QueryEvent>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<(), ConnectionError> {
    let limit = limit.map(|n| n as usize);
    registry.execute_sqlite_query(&id, &sql, limit, |ev| {
        on_event
            .send(ev)
            .map_err(|e| ConnectionError::io(format!("query channel closed: {e}")))
    })
}
