use crate::connection::{
    ConnectionConfig, ConnectionError, ConnectionId, ConnectionManager, ConnectionRegistry,
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
pub fn db_is_connected(
    id: ConnectionId,
    registry: State<'_, ConnectionRegistry>,
) -> bool {
    registry.is_connected(&id)
}
