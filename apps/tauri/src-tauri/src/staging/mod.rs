//! In-memory grid staging buffer (Flutter `DataGridStagingBuffer` parity).
//!
//! Tracks cell edits, inserted rows, and deletions against an immutable
//! baseline. DML generation lives in [`dml`]; apply-in-transaction is #1889.

mod buffer;
mod dml;

pub use buffer::{
    StagedCellStatus, StagedRowStatus, StagingBuffer, NULL_SENTINEL,
};
pub use dml::{
    generate_plan, MutationType, SqlDialect, StagingColumnMeta, TableMutationPlan,
    TableMutationStatement,
};
