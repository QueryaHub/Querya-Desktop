//! In-memory grid staging buffer (Flutter `DataGridStagingBuffer` parity).
//!
//! Tracks cell edits, inserted rows, and deletions against an immutable
//! baseline. DML generation lives in [`dml`]; transactional apply in [`apply`].

mod apply;
#[cfg(test)]
mod apply_live;
mod buffer;
mod dml;
mod ipc;

pub use apply::{
    apply_plan_mysql, apply_plan_postgres, apply_plan_sqlite, apply_staging_mysql,
    apply_staging_postgres, apply_staging_sqlite, ApplyError, ApplyResult,
};
pub use buffer::{
    StagedCellStatus, StagedRowStatus, StagingBuffer, NULL_SENTINEL,
};
pub use dml::{
    generate_plan, MutationType, SqlDialect, StagingColumnMeta, TableMutationPlan,
    TableMutationStatement,
};
pub use ipc::{apply_staging_request, StagingApplyRequest};
