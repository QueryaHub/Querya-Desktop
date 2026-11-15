//! In-memory grid staging buffer (Flutter `DataGridStagingBuffer` parity).
//!
//! Tracks cell edits, inserted rows, and deletions against an immutable
//! baseline. DML generation / apply are separate issues (#1888 / #1889).

mod buffer;

pub use buffer::{
    StagedCellStatus, StagedRowStatus, StagingBuffer, NULL_SENTINEL,
};
