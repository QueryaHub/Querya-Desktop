//! IPC payload: rebuild a [`StagingBuffer`] from the frontend snapshot and apply.

use super::apply::{
    apply_staging_mysql, apply_staging_postgres, apply_staging_sqlite, ApplyError, ApplyResult,
};
use super::StagingBuffer;
use crate::connection::{
    ConnectionError, ConnectionId, ConnectionManager, ConnectionRegistry, DriverKind,
};
use serde::Deserialize;
use std::collections::BTreeSet;

/// One staged cell edit (JSON-friendly; Maps don't round-trip cleanly).
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StagedCellEdit {
    pub row: usize,
    pub col: usize,
    pub value: String,
}

/// Frontend staging snapshot for apply (#1891).
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StagingApplyRequest {
    pub connection_id: ConnectionId,
    pub table_name: String,
    pub schema: Option<String>,
    pub columns: Vec<String>,
    pub primary_keys: Vec<String>,
    pub original_rows: Vec<Vec<String>>,
    pub modified_cells: Vec<StagedCellEdit>,
    pub inserted_rows: Vec<Vec<String>>,
    pub deleted_row_indices: Vec<usize>,
}

impl StagingApplyRequest {
    pub fn into_buffer(self) -> StagingBuffer {
        let mut buf = StagingBuffer::new(
            self.columns,
            self.original_rows,
            self.primary_keys,
        );
        for edit in self.modified_cells {
            buf.set_cell(edit.row, edit.col, edit.value);
        }
        for row in self.inserted_rows {
            buf.add_row(Some(row));
        }
        let deleted: BTreeSet<usize> = self.deleted_row_indices.into_iter().collect();
        for idx in deleted {
            buf.toggle_delete_row(idx);
        }
        buf
    }
}

/// Apply staged edits on the live connection; clears buffer only on success (Rust side).
pub fn apply_staging_request(
    registry: &ConnectionRegistry,
    req: StagingApplyRequest,
) -> Result<ApplyResult, ConnectionError> {
    let id = req.connection_id.clone();
    let table = req.table_name.clone();
    let schema = req.schema.clone();
    let mut buffer = req.into_buffer();

    let driver = registry
        .driver_of(&id)
        .ok_or_else(|| ConnectionError::NotFound { id: id.clone() })?;

    let result = match driver {
        DriverKind::Sqlite => registry.with_sqlite(&id, |s| {
            s.with_connection(|conn| {
                apply_staging_sqlite(conn, &mut buffer, &table, schema.as_deref())
                    .map_err(map_apply_error)
            })
        }),
        DriverKind::Postgres => registry.with_postgres(&id, |s| {
            s.with_pool(|pool| {
                apply_staging_postgres(pool, &mut buffer, &table, schema.as_deref())
                    .map_err(map_apply_error)
            })
        }),
        DriverKind::Mysql => registry.with_mysql(&id, |s| {
            s.with_pool(|pool| {
                apply_staging_mysql(pool, &mut buffer, &table, schema.as_deref())
                    .map_err(map_apply_error)
            })
        }),
        DriverKind::Redis => Err(ConnectionError::UnsupportedDriver {
            driver: DriverKind::Redis,
        }),
    }?;

    Ok(result)
}

fn map_apply_error(err: ApplyError) -> ConnectionError {
    ConnectionError::io(err.to_string())
}
