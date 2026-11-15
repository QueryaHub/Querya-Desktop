use crate::connection::{
    ConnectionConfig, ConnectionError, ConnectionId, ConnectionManager, ConnectionRegistry,
    QueryEvent, SchemaObject, TableSchema,
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

#[tauri::command]
pub fn db_list_schemas(
    id: ConnectionId,
    registry: State<'_, ConnectionRegistry>,
) -> Result<Vec<String>, ConnectionError> {
    registry.with_sqlite(&id, |s| s.list_schemas())
}

#[tauri::command]
pub fn db_list_tables(
    id: ConnectionId,
    registry: State<'_, ConnectionRegistry>,
) -> Result<Vec<SchemaObject>, ConnectionError> {
    registry.with_sqlite(&id, |s| s.list_tables())
}

#[tauri::command]
pub fn db_list_columns(
    id: ConnectionId,
    table: String,
    registry: State<'_, ConnectionRegistry>,
) -> Result<TableSchema, ConnectionError> {
    registry.with_sqlite(&id, |s| s.list_columns(&table))
}

/// Execute SQL and stream `QueryEvent` batches over `on_event` (not one giant IPC payload).
#[tauri::command]
pub fn db_execute_query(
    id: ConnectionId,
    sql: String,
    limit: Option<u32>,
    on_event: Channel<QueryEvent>,
    registry: State<'_, ConnectionRegistry>,
) -> Result<(), ConnectionError> {
    let conn_arc = registry.sqlite_connection_arc(&id)?;
    let guard = conn_arc
        .lock()
        .map_err(|_| ConnectionError::io("sqlite connection lock poisoned"))?;
    let conn = guard
        .as_ref()
        .ok_or_else(|| ConnectionError::Disconnected { id: id.clone() })?;

    let limit = limit.map(|n| n as usize);
    match crate::connection::sqlite_query::execute_streaming(conn, &sql, limit, None, |ev| {
        on_event
            .send(ev)
            .map_err(|e| ConnectionError::io(format!("query channel closed: {e}")))
    }) {
        Ok(()) => Ok(()),
        Err(e) => {
            let _ = on_event.send(QueryEvent::Error {
                message: e.to_string(),
            });
            Err(e)
        }
    }
}
