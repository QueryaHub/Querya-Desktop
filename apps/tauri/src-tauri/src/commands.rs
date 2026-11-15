use crate::connection::{
    ConnectionConfig, ConnectionError, ConnectionId, ConnectionManager, ConnectionRegistry,
    SchemaObject, TableSchema,
};
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
