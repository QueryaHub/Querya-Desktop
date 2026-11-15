//! Staging buffer model — cell edits keyed by baseline row index / PK names.

use std::collections::{BTreeMap, BTreeSet};

/// Sentinel stored for an explicit SQL NULL (Flutter `kNullSentinel` parity).
pub const NULL_SENTINEL: &str = "\u{0000}__QUERYA_NULL__\u{0000}";

/// Status of a row within the staging buffer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StagedRowStatus {
    Unchanged,
    Modified,
    Inserted,
    Deleted,
}

/// Status of an individual cell.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StagedCellStatus {
    Clean,
    Modified,
}

/// In-memory staging of cell edits against an immutable baseline snapshot.
#[derive(Debug, Clone)]
pub struct StagingBuffer {
    columns: Vec<String>,
    original_rows: Vec<Vec<String>>,
    /// Primary key column names (used when duplicating a row).
    primary_keys: Vec<String>,
    /// `row_index → (col_index → staged value)` for baseline rows.
    modified_cells: BTreeMap<usize, BTreeMap<usize, String>>,
    inserted_rows: Vec<Vec<String>>,
    deleted_row_indices: BTreeSet<usize>,
}

impl StagingBuffer {
    pub fn new(
        columns: impl IntoIterator<Item = impl Into<String>>,
        rows: impl IntoIterator<Item = impl IntoIterator<Item = impl Into<String>>>,
        primary_keys: impl IntoIterator<Item = impl Into<String>>,
    ) -> Self {
        Self {
            columns: columns.into_iter().map(Into::into).collect(),
            original_rows: rows
                .into_iter()
                .map(|r| r.into_iter().map(Into::into).collect())
                .collect(),
            primary_keys: primary_keys.into_iter().map(Into::into).collect(),
            modified_cells: BTreeMap::new(),
            inserted_rows: Vec::new(),
            deleted_row_indices: BTreeSet::new(),
        }
    }

    pub fn columns(&self) -> &[String] {
        &self.columns
    }

    pub fn original_rows(&self) -> &[Vec<String>] {
        &self.original_rows
    }

    pub fn primary_keys(&self) -> &[String] {
        &self.primary_keys
    }

    pub fn total_row_count(&self) -> usize {
        self.original_rows.len() + self.inserted_rows.len()
    }

    pub fn is_dirty(&self) -> bool {
        !self.modified_cells.is_empty()
            || !self.inserted_rows.is_empty()
            || !self.deleted_row_indices.is_empty()
    }

    pub fn change_count(&self) -> usize {
        self.modified_cell_count() + self.inserted_rows.len() + self.deleted_row_indices.len()
    }

    pub fn deleted_row_count(&self) -> usize {
        self.deleted_row_indices.len()
    }

    pub fn inserted_row_count(&self) -> usize {
        self.inserted_rows.len()
    }

    pub fn modified_cell_count(&self) -> usize {
        self.modified_cells.values().map(BTreeMap::len).sum()
    }

    pub fn modified_cells(&self) -> &BTreeMap<usize, BTreeMap<usize, String>> {
        &self.modified_cells
    }

    pub fn inserted_rows(&self) -> &[Vec<String>] {
        &self.inserted_rows
    }

    pub fn deleted_row_indices(&self) -> &BTreeSet<usize> {
        &self.deleted_row_indices
    }

    pub fn get_cell_value(&self, row: usize, col: usize) -> String {
        if row < self.original_rows.len() {
            if let Some(staged) = self.modified_cells.get(&row).and_then(|m| m.get(&col)) {
                return sanitize_null(staged);
            }
            return self
                .original_rows
                .get(row)
                .and_then(|r| r.get(col))
                .cloned()
                .unwrap_or_default();
        }
        let insert_idx = row - self.original_rows.len();
        self.inserted_rows
            .get(insert_idx)
            .and_then(|r| r.get(col))
            .map(|v| sanitize_null(v))
            .unwrap_or_default()
    }

    pub fn get_original_cell_value(&self, row: usize, col: usize) -> Option<&str> {
        self.original_rows
            .get(row)
            .and_then(|r| r.get(col))
            .map(String::as_str)
    }

    pub fn is_cell_null(&self, row: usize, col: usize) -> bool {
        if row < self.original_rows.len() {
            if let Some(staged) = self.modified_cells.get(&row).and_then(|m| m.get(&col)) {
                return staged == NULL_SENTINEL;
            }
            return self
                .original_rows
                .get(row)
                .and_then(|r| r.get(col))
                .is_some_and(|v| v == "NULL" || v == NULL_SENTINEL);
        }
        let insert_idx = row - self.original_rows.len();
        self.inserted_rows
            .get(insert_idx)
            .and_then(|r| r.get(col))
            .is_some_and(|v| v == "NULL" || v == NULL_SENTINEL)
    }

    pub fn row_status(&self, row: usize) -> StagedRowStatus {
        if row >= self.original_rows.len() {
            if row < self.total_row_count() {
                return StagedRowStatus::Inserted;
            }
            return StagedRowStatus::Unchanged;
        }
        if self.deleted_row_indices.contains(&row) {
            return StagedRowStatus::Deleted;
        }
        if self
            .modified_cells
            .get(&row)
            .is_some_and(|m| !m.is_empty())
        {
            return StagedRowStatus::Modified;
        }
        StagedRowStatus::Unchanged
    }

    pub fn cell_status(&self, row: usize, col: usize) -> StagedCellStatus {
        if row < self.original_rows.len()
            && self
                .modified_cells
                .get(&row)
                .is_some_and(|m| m.contains_key(&col))
        {
            StagedCellStatus::Modified
        } else {
            StagedCellStatus::Clean
        }
    }

    pub fn set_cell_null(&mut self, row: usize, col: usize) {
        self.set_cell(row, col, NULL_SENTINEL.to_string());
    }

    /// Stage an edit. Reverting to the original value clears the modified flag.
    pub fn set_cell(&mut self, row: usize, col: usize, value: impl Into<String>) {
        let value = value.into();
        if row < self.original_rows.len() {
            let orig = self
                .original_rows
                .get(row)
                .and_then(|r| r.get(col))
                .cloned()
                .unwrap_or_default();
            if value == orig {
                if let Some(map) = self.modified_cells.get_mut(&row) {
                    map.remove(&col);
                    if map.is_empty() {
                        self.modified_cells.remove(&row);
                    }
                }
            } else {
                self.modified_cells
                    .entry(row)
                    .or_default()
                    .insert(col, value);
            }
            return;
        }
        let insert_idx = row - self.original_rows.len();
        if let Some(ins) = self.inserted_rows.get_mut(insert_idx) {
            while ins.len() <= col {
                ins.push(String::new());
            }
            ins[col] = value;
        }
    }

    /// Append a new row; returns its absolute index.
    pub fn add_row(&mut self, initial: Option<Vec<String>>) -> usize {
        let row = initial.unwrap_or_else(|| vec![String::new(); self.columns.len()]);
        self.inserted_rows.push(row);
        self.total_row_count() - 1
    }

    pub fn remove_inserted_row(&mut self, row: usize) {
        if row < self.original_rows.len() {
            return;
        }
        let insert_idx = row - self.original_rows.len();
        if insert_idx < self.inserted_rows.len() {
            self.inserted_rows.remove(insert_idx);
        }
    }

    /// Mark a baseline row deleted, or drop an inserted row.
    pub fn toggle_delete_row(&mut self, row: usize) {
        if row < self.original_rows.len() {
            if !self.deleted_row_indices.remove(&row) {
                self.deleted_row_indices.insert(row);
            }
        } else {
            self.remove_inserted_row(row);
        }
    }

    pub fn revert_cell(&mut self, row: usize, col: usize) {
        if let Some(map) = self.modified_cells.get_mut(&row) {
            map.remove(&col);
            if map.is_empty() {
                self.modified_cells.remove(&row);
            }
        }
    }

    pub fn revert_row(&mut self, row: usize) {
        if row < self.original_rows.len() {
            self.modified_cells.remove(&row);
            self.deleted_row_indices.remove(&row);
        } else {
            self.remove_inserted_row(row);
        }
    }

    pub fn revert_all(&mut self) {
        if !self.is_dirty() {
            return;
        }
        self.modified_cells.clear();
        self.inserted_rows.clear();
        self.deleted_row_indices.clear();
    }

    /// Duplicate `index` as a new inserted row with PK cells blanked.
    pub fn duplicate_row(&mut self, index: usize) {
        if index >= self.total_row_count() {
            return;
        }
        let pk_names: BTreeSet<String> = self
            .primary_keys
            .iter()
            .map(|pk| unquote_ident(pk).to_ascii_lowercase())
            .collect();
        let row: Vec<String> = (0..self.columns.len())
            .map(|c| {
                let name = unquote_ident(&self.columns[c]).to_ascii_lowercase();
                if pk_names.contains(&name) {
                    String::new()
                } else {
                    sanitize_null(&self.get_cell_value(index, c))
                }
            })
            .collect();
        self.add_row(Some(row));
    }

    /// Effective grid snapshot (deleted rows kept for strike-through alignment).
    pub fn effective_rows(&self) -> Vec<Vec<String>> {
        self.build_rows(true)
    }

    /// Rows after a successful apply (deleted dropped; NULLs sanitized).
    pub fn committed_rows(&self) -> Vec<Vec<String>> {
        self.build_rows(false)
    }

    fn build_rows(&self, include_deleted: bool) -> Vec<Vec<String>> {
        let mut result = Vec::with_capacity(self.total_row_count());
        for (r, orig) in self.original_rows.iter().enumerate() {
            if !include_deleted && self.deleted_row_indices.contains(&r) {
                continue;
            }
            if let Some(mods) = self.modified_cells.get(&r) {
                let mut row = orig.clone();
                for (&col, value) in mods {
                    if col < row.len() {
                        row[col] = sanitize_null(value);
                    }
                }
                result.push(row);
            } else {
                result.push(orig.clone());
            }
        }
        for ins in &self.inserted_rows {
            if ins.iter().any(|v| v == NULL_SENTINEL) {
                result.push(ins.iter().map(|v| sanitize_null(v)).collect());
            } else {
                result.push(ins.clone());
            }
        }
        result
    }
}

fn sanitize_null(value: &str) -> String {
    if value == NULL_SENTINEL {
        "NULL".into()
    } else {
        value.to_string()
    }
}

fn unquote_ident(name: &str) -> &str {
    let t = name.trim();
    if t.len() >= 2 {
        let bytes = t.as_bytes();
        let q = bytes[0];
        if (q == b'"' || q == b'`' || q == b'[') && bytes[t.len() - 1] == match q {
            b'"' => b'"',
            b'`' => b'`',
            b'[' => b']',
            _ => q,
        } {
            return &t[1..t.len() - 1];
        }
    }
    t
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> StagingBuffer {
        StagingBuffer::new(
            ["id", "name", "email"],
            [
                ["1", "Alice", "alice@test.com"],
                ["2", "Bob", "bob@test.com"],
                ["3", "Charlie", "charlie@test.com"],
            ],
            ["id"],
        )
    }

    #[test]
    fn initial_state_is_clean() {
        let buf = sample();
        assert!(!buf.is_dirty());
        assert_eq!(buf.change_count(), 0);
        assert_eq!(buf.total_row_count(), 3);
        assert_eq!(buf.row_status(0), StagedRowStatus::Unchanged);
        assert_eq!(buf.cell_status(0, 1), StagedCellStatus::Clean);
        assert_eq!(buf.get_cell_value(0, 1), "Alice");
        assert_eq!(buf.get_original_cell_value(0, 1), Some("Alice"));
    }

    #[test]
    fn modifying_cell_sets_dirty_and_reverts_to_clean() {
        let mut buf = sample();
        buf.set_cell(0, 1, "Alice Cooper");
        assert!(buf.is_dirty());
        assert_eq!(buf.change_count(), 1);
        assert_eq!(buf.modified_cell_count(), 1);
        assert_eq!(buf.get_cell_value(0, 1), "Alice Cooper");
        assert_eq!(buf.get_original_cell_value(0, 1), Some("Alice"));
        assert_eq!(buf.cell_status(0, 1), StagedCellStatus::Modified);
        assert_eq!(buf.row_status(0), StagedRowStatus::Modified);

        buf.set_cell(0, 1, "Alice");
        assert!(!buf.is_dirty());
        assert_eq!(buf.change_count(), 0);
        assert_eq!(buf.cell_status(0, 1), StagedCellStatus::Clean);
        assert_eq!(buf.row_status(0), StagedRowStatus::Unchanged);
    }

    #[test]
    fn add_row_and_edit_inserted() {
        let mut buf = sample();
        let idx = buf.add_row(Some(vec![
            "4".into(),
            "Diana".into(),
            "diana@test.com".into(),
        ]));
        assert_eq!(idx, 3);
        assert_eq!(buf.total_row_count(), 4);
        assert!(buf.is_dirty());
        assert_eq!(buf.inserted_row_count(), 1);
        assert_eq!(buf.row_status(3), StagedRowStatus::Inserted);
        assert_eq!(buf.get_cell_value(3, 1), "Diana");
        assert!(buf.get_original_cell_value(3, 1).is_none());

        buf.set_cell(3, 1, "Diana Prince");
        assert_eq!(buf.get_cell_value(3, 1), "Diana Prince");
    }

    #[test]
    fn toggle_delete_baseline_and_remove_inserted() {
        let mut buf = sample();
        buf.toggle_delete_row(1);
        assert!(buf.is_dirty());
        assert_eq!(buf.deleted_row_count(), 1);
        assert_eq!(buf.row_status(1), StagedRowStatus::Deleted);

        buf.toggle_delete_row(1);
        assert!(!buf.is_dirty());
        assert_eq!(buf.deleted_row_count(), 0);

        let ins = buf.add_row(Some(vec!["4".into(), "New".into(), "new@test.com".into()]));
        assert_eq!(buf.total_row_count(), 4);
        buf.toggle_delete_row(ins);
        assert_eq!(buf.total_row_count(), 3);
        assert!(!buf.is_dirty());
    }

    #[test]
    fn revert_cell_row_all() {
        let mut buf = sample();
        buf.set_cell(0, 1, "Alice Modified");
        buf.set_cell(0, 2, "modified@test.com");
        buf.toggle_delete_row(1);
        buf.add_row(Some(vec!["4".into(), "Extra".into(), "extra@test.com".into()]));
        assert_eq!(buf.change_count(), 4);

        buf.revert_cell(0, 1);
        assert_eq!(buf.get_cell_value(0, 1), "Alice");
        assert_eq!(buf.get_cell_value(0, 2), "modified@test.com");

        buf.revert_row(0);
        assert_eq!(buf.get_cell_value(0, 2), "alice@test.com");
        assert_eq!(buf.row_status(0), StagedRowStatus::Unchanged);

        buf.revert_all();
        assert!(!buf.is_dirty());
        assert_eq!(buf.change_count(), 0);
        assert_eq!(buf.total_row_count(), 3);
    }

    #[test]
    fn effective_rows_snapshot() {
        let mut buf = sample();
        buf.set_cell(0, 1, "Alice Updated");
        buf.add_row(Some(vec![
            "4".into(),
            "David".into(),
            "david@test.com".into(),
        ]));
        let eff = buf.effective_rows();
        assert_eq!(eff.len(), 4);
        assert_eq!(eff[0], ["1", "Alice Updated", "alice@test.com"]);
        assert_eq!(eff[3], ["4", "David", "david@test.com"]);
    }

    #[test]
    fn effective_keeps_deleted_and_maps_null_sentinel() {
        let mut buf = sample();
        buf.toggle_delete_row(1);
        buf.set_cell_null(0, 2);
        buf.add_row(Some(vec![
            "4".into(),
            NULL_SENTINEL.into(),
            "d@test.com".into(),
        ]));
        let eff = buf.effective_rows();
        assert_eq!(eff.len(), 4);
        assert_eq!(eff[0], ["1", "Alice", "NULL"]);
        assert_eq!(eff[1], ["2", "Bob", "bob@test.com"]);
        assert_eq!(eff[3], ["4", "NULL", "d@test.com"]);
        assert!(!eff.iter().flatten().any(|v| v.contains('\u{0000}')));
    }

    #[test]
    fn committed_rows_drops_deleted() {
        let mut buf = sample();
        buf.toggle_delete_row(1);
        buf.set_cell(1, 1, "ignored");
        buf.set_cell_null(0, 2);
        buf.add_row(Some(vec![
            "4".into(),
            NULL_SENTINEL.into(),
            "d@test.com".into(),
        ]));
        let committed = buf.committed_rows();
        assert_eq!(
            committed,
            [
                ["1", "Alice", "NULL"],
                ["3", "Charlie", "charlie@test.com"],
                ["4", "NULL", "d@test.com"],
            ]
        );
    }

    #[test]
    fn duplicate_row_blanks_primary_key() {
        let mut buf = sample();
        buf.duplicate_row(0);
        assert_eq!(buf.total_row_count(), 4);
        assert_eq!(buf.get_cell_value(3, 0), "");
        assert_eq!(buf.get_cell_value(3, 1), "Alice");
        assert_eq!(buf.get_cell_value(3, 2), "alice@test.com");
        assert_eq!(buf.row_status(3), StagedRowStatus::Inserted);
    }
}
