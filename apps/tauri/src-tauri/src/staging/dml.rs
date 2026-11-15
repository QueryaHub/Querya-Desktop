//! Generate parameterized-looking DML from a [`StagingBuffer`]
//! (Flutter `TableMutationEngine.generatePlan` parity).
//!
//! Literals are inlined with dialect-aware escaping (same as Flutter today);
//! apply-in-transaction is #1889.

use super::buffer::{StagingBuffer, NULL_SENTINEL};
use std::collections::{BTreeMap, BTreeSet};

/// Target SQL dialect for quoting / literals / transaction wrappers.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SqlDialect {
    Postgres,
    Mysql,
    Sqlite,
}

/// Kind of generated statement.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MutationType {
    Insert,
    Update,
    Delete,
}

/// One DML statement in a mutation plan.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TableMutationStatement {
    pub mutation_type: MutationType,
    pub sql: String,
    pub description: String,
}

/// Full plan of statements for applying staged edits.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TableMutationPlan {
    pub dialect: SqlDialect,
    pub table_name: String,
    pub schema: Option<String>,
    pub statements: Vec<TableMutationStatement>,
    pub has_primary_key: bool,
}

impl TableMutationPlan {
    pub fn is_empty(&self) -> bool {
        self.statements.is_empty()
    }

    pub fn statement_count(&self) -> usize {
        self.statements.len()
    }

    /// Atomic transaction script (BEGIN…COMMIT) matching Flutter.
    pub fn to_transaction_sql(&self) -> String {
        if self.is_empty() {
            return String::new();
        }
        let mut out = String::new();
        match self.dialect {
            SqlDialect::Postgres => out.push_str("BEGIN;\n"),
            SqlDialect::Mysql => out.push_str("START TRANSACTION;\n"),
            SqlDialect::Sqlite => out.push_str("BEGIN TRANSACTION;\n"),
        }
        for stmt in &self.statements {
            out.push_str(&stmt.sql);
            out.push_str(";\n");
        }
        out.push_str("COMMIT;\n");
        out
    }
}

/// Optional per-column hints for INSERT omission / typing.
#[derive(Debug, Clone, Default)]
pub struct StagingColumnMeta {
    pub data_type: String,
    pub is_nullable: bool,
    pub omit_on_insert: bool,
    pub has_server_default: bool,
}

/// Inputs for [`generate_plan`] (mirrors Flutter `generatePlan` args).
#[derive(Debug, Clone)]
pub struct GeneratePlanInput<'a> {
    pub dialect: SqlDialect,
    pub table_name: &'a str,
    pub schema: Option<&'a str>,
    pub columns: &'a [String],
    pub primary_keys: &'a [String],
    pub original_rows: &'a [Vec<String>],
    pub modified_cells: &'a BTreeMap<usize, BTreeMap<usize, String>>,
    pub inserted_rows: &'a [Vec<String>],
    pub deleted_row_indices: &'a BTreeSet<usize>,
    pub column_data_types: Option<&'a BTreeMap<String, String>>,
    pub column_meta: Option<&'a BTreeMap<String, StagingColumnMeta>>,
}

impl StagingBuffer {
    /// Build a mutation plan for the current staged changes.
    pub fn generate_mutation_plan(
        &self,
        dialect: SqlDialect,
        table_name: &str,
        schema: Option<&str>,
        column_data_types: Option<&BTreeMap<String, String>>,
        column_meta: Option<&BTreeMap<String, StagingColumnMeta>>,
    ) -> TableMutationPlan {
        generate_plan(GeneratePlanInput {
            dialect,
            table_name,
            schema,
            columns: self.columns(),
            primary_keys: self.primary_keys(),
            original_rows: self.original_rows(),
            modified_cells: self.modified_cells(),
            inserted_rows: self.inserted_rows(),
            deleted_row_indices: self.deleted_row_indices(),
            column_data_types,
            column_meta,
        })
    }
}

pub fn generate_plan(input: GeneratePlanInput<'_>) -> TableMutationPlan {
    let table_ref = quote_qualified_table(input.table_name, input.schema, input.dialect);
    let mut statements = Vec::new();

    // 1. UPDATE
    for (&row_index, mods) in input.modified_cells {
        if input.deleted_row_indices.contains(&row_index) {
            continue;
        }
        if row_index >= input.original_rows.len() {
            continue;
        }
        let orig_row = &input.original_rows[row_index];
        let mut set_clauses = Vec::new();
        for (&col_index, staged_val) in mods {
            if col_index >= input.columns.len() {
                continue;
            }
            let col_name = &input.columns[col_index];
            let quoted_col = quote_identifier(&unquote_identifier(col_name), input.dialect);
            let col_type = lookup_data_type(input.column_data_types, col_name);
            let literal = format_literal(staged_val, input.dialect, col_type.as_deref());
            set_clauses.push(format!("{quoted_col} = {literal}"));
        }
        if set_clauses.is_empty() {
            continue;
        }
        let where_clause = build_where_clause(
            input.columns,
            input.primary_keys,
            orig_row,
            input.dialect,
            input.column_data_types,
        );
        statements.push(TableMutationStatement {
            mutation_type: MutationType::Update,
            sql: format!(
                "UPDATE {table_ref} SET {} WHERE {where_clause}",
                set_clauses.join(", ")
            ),
            description: format!("Update row {}", row_index + 1),
        });
    }

    // 2. INSERT
    for (i, row) in input.inserted_rows.iter().enumerate() {
        let mut col_names = Vec::new();
        let mut values = Vec::new();
        for (c, col_name) in input.columns.iter().enumerate() {
            let meta = lookup_column_meta(input.column_meta, col_name);
            if meta.is_some_and(|m| m.omit_on_insert) {
                continue;
            }
            let cell_val = row.get(c).map(String::as_str).unwrap_or_else(|| {
                if meta.is_none() {
                    "NULL"
                } else {
                    ""
                }
            });
            if let Some(m) = meta {
                if is_blank_insert_cell(cell_val) && (m.has_server_default || m.is_nullable) {
                    continue;
                }
            }
            let quoted_col = quote_identifier(&unquote_identifier(col_name), input.dialect);
            let col_type = lookup_data_type(input.column_data_types, col_name)
                .or_else(|| meta.map(|m| m.data_type.clone()));
            col_names.push(quoted_col);
            values.push(format_literal(
                cell_val,
                input.dialect,
                col_type.as_deref(),
            ));
        }
        let sql = if col_names.is_empty() {
            match input.dialect {
                SqlDialect::Mysql => format!("INSERT INTO {table_ref} () VALUES ()"),
                _ => format!("INSERT INTO {table_ref} DEFAULT VALUES"),
            }
        } else {
            format!(
                "INSERT INTO {table_ref} ({}) VALUES ({})",
                col_names.join(", "),
                values.join(", ")
            )
        };
        statements.push(TableMutationStatement {
            mutation_type: MutationType::Insert,
            sql,
            description: format!("Insert new row {}", i + 1),
        });
    }

    // 3. DELETE
    for &row_index in input.deleted_row_indices {
        if row_index >= input.original_rows.len() {
            continue;
        }
        let orig_row = &input.original_rows[row_index];
        let where_clause = build_where_clause(
            input.columns,
            input.primary_keys,
            orig_row,
            input.dialect,
            input.column_data_types,
        );
        statements.push(TableMutationStatement {
            mutation_type: MutationType::Delete,
            sql: format!("DELETE FROM {table_ref} WHERE {where_clause}"),
            description: format!("Delete row {}", row_index + 1),
        });
    }

    TableMutationPlan {
        dialect: input.dialect,
        table_name: input.table_name.to_string(),
        schema: input.schema.map(str::to_string),
        statements,
        has_primary_key: has_matching_primary_key(input.columns, input.primary_keys),
    }
}

pub fn quote_identifier(identifier: &str, dialect: SqlDialect) -> String {
    match dialect {
        SqlDialect::Mysql => format!("`{}`", identifier.replace('`', "``")),
        SqlDialect::Postgres | SqlDialect::Sqlite => {
            format!("\"{}\"", identifier.replace('"', "\"\""))
        }
    }
}

pub fn quote_qualified_table(table: &str, schema: Option<&str>, dialect: SqlDialect) -> String {
    let quoted_table = quote_identifier(table, dialect);
    match (schema, dialect) {
        (Some(s), d) if !s.is_empty() && !matches!(d, SqlDialect::Sqlite) => {
            format!("{}.{}", quote_identifier(s, dialect), quoted_table)
        }
        _ => quoted_table,
    }
}

pub fn unquote_identifier(identifier: &str) -> String {
    let s = identifier.trim();
    if s.len() >= 2 {
        let b = s.as_bytes();
        let (open, close) = match b[0] {
            b'"' => (b'"', b'"'),
            b'`' => (b'`', b'`'),
            b'[' => (b'[', b']'),
            _ => return s.to_string(),
        };
        if b[0] == open && b[s.len() - 1] == close {
            return s[1..s.len() - 1].to_string();
        }
    }
    s.to_string()
}

fn normalize_identifier(identifier: &str) -> String {
    unquote_identifier(identifier).to_ascii_lowercase()
}

pub fn format_literal(value: &str, dialect: SqlDialect, data_type_name: Option<&str>) -> String {
    if value == NULL_SENTINEL {
        return "NULL".into();
    }
    let trimmed = value.trim();

    if let Some(dt) = data_type_name.filter(|s| !s.is_empty()) {
        if is_array_type(dt) {
            if trimmed.eq_ignore_ascii_case("null") {
                return "NULL".into();
            }
            return format_string_literal(value, dialect);
        }
        if is_binary_type(dt) {
            if trimmed.eq_ignore_ascii_case("null") {
                return "NULL".into();
            }
            let mut hex = trimmed.to_string();
            if hex.starts_with("\\x")
                || hex.starts_with("\\X")
                || hex.starts_with("0x")
                || hex.starts_with("0X")
            {
                hex = hex[2..].to_string();
            } else if (hex.starts_with("x'") || hex.starts_with("X'")) && hex.ends_with('\'') {
                hex = hex[2..hex.len() - 1].to_string();
            }
            let clean: String = hex.chars().filter(|c| c.is_ascii_hexdigit()).collect();
            return match dialect {
                SqlDialect::Postgres => format!("'\\x{clean}'::bytea"),
                SqlDialect::Mysql | SqlDialect::Sqlite => format!("X'{clean}'"),
            };
        }
        if is_text_type(dt) {
            return format_string_literal(value, dialect);
        }
        if is_bool_type(dt) {
            if trimmed.eq_ignore_ascii_case("null") {
                return "NULL".into();
            }
            let lower = trimmed.to_ascii_lowercase();
            if lower == "true" || trimmed == "1" {
                return if matches!(dialect, SqlDialect::Sqlite) {
                    "1".into()
                } else {
                    "TRUE".into()
                };
            }
            if lower == "false" || trimmed == "0" {
                return if matches!(dialect, SqlDialect::Sqlite) {
                    "0".into()
                } else {
                    "FALSE".into()
                };
            }
        }
        if is_numeric_type(dt) {
            if trimmed.eq_ignore_ascii_case("null") {
                return "NULL".into();
            }
            if is_plain_number(trimmed) {
                return trimmed.to_string();
            }
        }
    }

    if value == "NULL" || value == "null" {
        return "NULL".into();
    }
    if trimmed.len() > 1 && trimmed.starts_with('0') && trimmed.chars().all(|c| c.is_ascii_digit())
    {
        return format_string_literal(value, dialect);
    }
    if is_plain_number(trimmed) {
        return trimmed.to_string();
    }
    let lower = trimmed.to_ascii_lowercase();
    if lower == "true" {
        return if matches!(dialect, SqlDialect::Sqlite) {
            "1".into()
        } else {
            "TRUE".into()
        };
    }
    if lower == "false" {
        return if matches!(dialect, SqlDialect::Sqlite) {
            "0".into()
        } else {
            "FALSE".into()
        };
    }
    format_string_literal(value, dialect)
}

fn format_string_literal(value: &str, dialect: SqlDialect) -> String {
    let mut escaped = value.to_string();
    if matches!(dialect, SqlDialect::Mysql) {
        escaped = escaped.replace('\\', "\\\\");
    }
    escaped = escaped.replace('\'', "''");
    format!("'{escaped}'")
}

fn is_plain_number(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    let mut chars = s.chars().peekable();
    if chars.peek() == Some(&'-') {
        chars.next();
    }
    let mut saw_digit = false;
    let mut saw_dot = false;
    for c in chars {
        if c.is_ascii_digit() {
            saw_digit = true;
        } else if c == '.' && !saw_dot {
            saw_dot = true;
        } else {
            return false;
        }
    }
    saw_digit
}

fn is_text_type(dt: &str) -> bool {
    let lower = dt.to_ascii_lowercase();
    ["char", "text", "varchar", "string", "uuid", "json", "xml", "clob", "enum", "citext", "name", "bpchar"]
        .iter()
        .any(|k| lower.contains(k))
}

fn is_bool_type(dt: &str) -> bool {
    let lower = dt.to_ascii_lowercase();
    lower == "bool" || lower == "boolean" || lower.starts_with("tinyint(1)")
}

fn is_numeric_type(dt: &str) -> bool {
    let lower = dt.to_ascii_lowercase();
    ["int", "float", "double", "decimal", "numeric", "real", "serial", "number"]
        .iter()
        .any(|k| lower.contains(k))
}

fn is_binary_type(dt: &str) -> bool {
    let lower = dt.to_ascii_lowercase();
    lower.contains("blob")
        || lower.contains("bytea")
        || lower.contains("binary")
        || lower.contains("varbinary")
        || lower == "raw"
        || lower == "image"
        || lower.starts_with("bit")
}

fn is_array_type(dt: &str) -> bool {
    let lower = dt.to_ascii_lowercase();
    lower.contains("[]") || lower == "array" || (lower.starts_with('_') && !lower.contains(' '))
}

fn is_blank_insert_cell(value: &str) -> bool {
    value == NULL_SENTINEL || value.trim().is_empty()
}

fn lookup_data_type(
    types: Option<&BTreeMap<String, String>>,
    col_name: &str,
) -> Option<String> {
    let types = types?;
    if let Some(v) = types.get(col_name) {
        return Some(v.clone());
    }
    let unquoted = unquote_identifier(col_name);
    if let Some(v) = types.get(&unquoted) {
        return Some(v.clone());
    }
    let norm = normalize_identifier(col_name);
    types
        .iter()
        .find(|(k, _)| normalize_identifier(k) == norm)
        .map(|(_, v)| v.clone())
}

fn lookup_column_meta<'a>(
    meta: Option<&'a BTreeMap<String, StagingColumnMeta>>,
    col_name: &str,
) -> Option<&'a StagingColumnMeta> {
    let meta = meta?;
    if let Some(v) = meta.get(col_name) {
        return Some(v);
    }
    let unquoted = unquote_identifier(col_name);
    if let Some(v) = meta.get(&unquoted) {
        return Some(v);
    }
    let norm = normalize_identifier(col_name);
    meta.iter()
        .find(|(k, _)| normalize_identifier(k) == norm)
        .map(|(_, v)| v)
}

fn has_matching_primary_key(columns: &[String], primary_keys: &[String]) -> bool {
    if primary_keys.is_empty() {
        return false;
    }
    primary_keys.iter().all(|pk| {
        columns.iter().any(|c| c == pk)
            || columns
                .iter()
                .any(|c| normalize_identifier(c) == normalize_identifier(pk))
    })
}

fn build_where_clause(
    columns: &[String],
    primary_keys: &[String],
    row: &[String],
    dialect: SqlDialect,
    column_data_types: Option<&BTreeMap<String, String>>,
) -> String {
    let mut clauses = Vec::new();

    if !primary_keys.is_empty() {
        for pk in primary_keys {
            let col_idx = columns
                .iter()
                .position(|c| c == pk)
                .or_else(|| {
                    let norm = normalize_identifier(pk);
                    columns
                        .iter()
                        .position(|c| normalize_identifier(c) == norm)
                });
            if let Some(col_idx) = col_idx {
                if col_idx >= row.len() {
                    continue;
                }
                let matched = &columns[col_idx];
                let col_name = quote_identifier(&unquote_identifier(matched), dialect);
                let val = &row[col_idx];
                let col_type = lookup_data_type(column_data_types, matched)
                    .or_else(|| lookup_data_type(column_data_types, pk));
                let is_text = col_type.as_deref().is_some_and(is_text_type);
                if val == NULL_SENTINEL || (!is_text && (val == "NULL" || val == "null")) {
                    clauses.push(format!("{col_name} IS NULL"));
                } else {
                    clauses.push(format!(
                        "{col_name} = {}",
                        format_literal(val, dialect, col_type.as_deref())
                    ));
                }
            }
        }
    }

    if clauses.is_empty() {
        for (c, col_name) in columns.iter().enumerate() {
            let quoted = quote_identifier(&unquote_identifier(col_name), dialect);
            let val = row.get(c).map(String::as_str).unwrap_or(NULL_SENTINEL);
            let col_type = lookup_data_type(column_data_types, col_name);
            let is_text = col_type.as_deref().is_some_and(is_text_type);
            if val == NULL_SENTINEL || (!is_text && (val == "NULL" || val == "null")) {
                clauses.push(format!("{quoted} IS NULL"));
            } else {
                clauses.push(format!(
                    "{quoted} = {}",
                    format_literal(val, dialect, col_type.as_deref())
                ));
            }
        }
    }

    clauses.join(" AND ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    fn columns() -> Vec<String> {
        vec![
            "id".into(),
            "username".into(),
            "age".into(),
            "active".into(),
        ]
    }

    fn original_rows() -> Vec<Vec<String>> {
        vec![
            vec!["1".into(), "alice".into(), "30".into(), "true".into()],
            vec!["2".into(), "bob".into(), "25".into(), "false".into()],
        ]
    }

    #[test]
    fn snapshot_postgres_update_with_pk() {
        let mut mods = BTreeMap::new();
        let mut row0 = BTreeMap::new();
        row0.insert(1, "alice_updated".into());
        row0.insert(2, "31".into());
        mods.insert(0, row0);
        let deleted = BTreeSet::new();
        let cols = columns();
        let rows = original_rows();
        let pks = vec!["id".into()];
        let plan = generate_plan(GeneratePlanInput {
            dialect: SqlDialect::Postgres,
            table_name: "users",
            schema: Some("public"),
            columns: &cols,
            primary_keys: &pks,
            original_rows: &rows,
            modified_cells: &mods,
            inserted_rows: &[],
            deleted_row_indices: &deleted,
            column_data_types: None,
            column_meta: None,
        });
        assert_eq!(plan.statement_count(), 1);
        assert_eq!(plan.statements[0].mutation_type, MutationType::Update);
        assert_eq!(
            plan.statements[0].sql,
            r#"UPDATE "public"."users" SET "username" = 'alice_updated', "age" = 31 WHERE "id" = 1"#
        );
        let tx = plan.to_transaction_sql();
        assert!(tx.starts_with("BEGIN;\n"));
        assert!(tx.ends_with("COMMIT;\n"));
    }

    #[test]
    fn snapshot_sqlite_rowid_update_and_delete() {
        let cols = vec!["rowid".into(), "body".into()];
        let rows = vec![
            vec!["7".into(), "dup".into()],
            vec!["8".into(), "dup".into()],
        ];
        let mut mods = BTreeMap::new();
        let mut row0 = BTreeMap::new();
        row0.insert(1, "edited".into());
        mods.insert(0, row0);
        let mut deleted = BTreeSet::new();
        deleted.insert(1);
        let pks = vec!["rowid".into()];
        let plan = generate_plan(GeneratePlanInput {
            dialect: SqlDialect::Sqlite,
            table_name: "notes",
            schema: None,
            columns: &cols,
            primary_keys: &pks,
            original_rows: &rows,
            modified_cells: &mods,
            inserted_rows: &[],
            deleted_row_indices: &deleted,
            column_data_types: None,
            column_meta: None,
        });
        assert_eq!(plan.statement_count(), 2);
        assert_eq!(
            plan.statements[0].sql,
            r#"UPDATE "notes" SET "body" = 'edited' WHERE "rowid" = 7"#
        );
        assert_eq!(
            plan.statements[1].sql,
            r#"DELETE FROM "notes" WHERE "rowid" = 8"#
        );
    }

    #[test]
    fn snapshot_mysql_update_backticks() {
        let cols = columns();
        let rows = original_rows();
        let mut mods = BTreeMap::new();
        let mut row1 = BTreeMap::new();
        row1.insert(3, "true".into());
        mods.insert(1, row1);
        let deleted = BTreeSet::new();
        let pks = vec!["id".into()];
        let plan = generate_plan(GeneratePlanInput {
            dialect: SqlDialect::Mysql,
            table_name: "users",
            schema: Some("mydb"),
            columns: &cols,
            primary_keys: &pks,
            original_rows: &rows,
            modified_cells: &mods,
            inserted_rows: &[],
            deleted_row_indices: &deleted,
            column_data_types: None,
            column_meta: None,
        });
        assert_eq!(
            plan.statements[0].sql,
            "UPDATE `mydb`.`users` SET `active` = TRUE WHERE `id` = 2"
        );
        assert!(plan.to_transaction_sql().starts_with("START TRANSACTION;\n"));
    }

    #[test]
    fn snapshot_sqlite_insert_null_and_bool() {
        let cols = columns();
        let rows = original_rows();
        let inserted = vec![vec![
            "3".into(),
            "charlie".into(),
            "NULL".into(),
            "false".into(),
        ]];
        let mods = BTreeMap::new();
        let deleted = BTreeSet::new();
        let pks = vec!["id".into()];
        let plan = generate_plan(GeneratePlanInput {
            dialect: SqlDialect::Sqlite,
            table_name: "users",
            schema: None,
            columns: &cols,
            primary_keys: &pks,
            original_rows: &rows,
            modified_cells: &mods,
            inserted_rows: &inserted,
            deleted_row_indices: &deleted,
            column_data_types: None,
            column_meta: None,
        });
        assert_eq!(
            plan.statements[0].sql,
            r#"INSERT INTO "users" ("id", "username", "age", "active") VALUES (3, 'charlie', NULL, 0)"#
        );
        assert!(plan
            .to_transaction_sql()
            .starts_with("BEGIN TRANSACTION;\n"));
    }

    #[test]
    fn snapshot_postgres_delete() {
        let cols = columns();
        let rows = original_rows();
        let mods = BTreeMap::new();
        let mut deleted = BTreeSet::new();
        deleted.insert(0);
        let pks = vec!["id".into()];
        let plan = generate_plan(GeneratePlanInput {
            dialect: SqlDialect::Postgres,
            table_name: "users",
            schema: Some("public"),
            columns: &cols,
            primary_keys: &pks,
            original_rows: &rows,
            modified_cells: &mods,
            inserted_rows: &[],
            deleted_row_indices: &deleted,
            column_data_types: None,
            column_meta: None,
        });
        assert_eq!(
            plan.statements[0].sql,
            r#"DELETE FROM "public"."users" WHERE "id" = 1"#
        );
    }

    #[test]
    fn buffer_generate_mutation_plan_skips_updates_on_deleted_rows() {
        let mut buf = StagingBuffer::new(
            ["id", "name"],
            [["1", "a"], ["2", "b"]],
            ["id"],
        );
        buf.set_cell(0, 1, "a2");
        buf.toggle_delete_row(0);
        buf.add_row(Some(vec!["3".into(), "c".into()]));
        let plan = buf.generate_mutation_plan(SqlDialect::Postgres, "t", None, None, None);
        assert_eq!(plan.statement_count(), 2);
        assert_eq!(plan.statements[0].mutation_type, MutationType::Insert);
        assert_eq!(plan.statements[1].mutation_type, MutationType::Delete);
        assert_eq!(
            plan.statements[0].sql,
            r#"INSERT INTO "t" ("id", "name") VALUES (3, 'c')"#
        );
        assert_eq!(plan.statements[1].sql, r#"DELETE FROM "t" WHERE "id" = 1"#);
    }

    #[test]
    fn text_column_preserves_literal_null_string() {
        let mut types = BTreeMap::new();
        types.insert("note".into(), "text".into());
        let cols = vec!["id".into(), "note".into()];
        let rows = vec![vec!["1".into(), "hi".into()]];
        let mut mods = BTreeMap::new();
        let mut row0 = BTreeMap::new();
        row0.insert(1, "NULL".into());
        mods.insert(0, row0);
        let deleted = BTreeSet::new();
        let pks = vec!["id".into()];
        let plan = generate_plan(GeneratePlanInput {
            dialect: SqlDialect::Postgres,
            table_name: "t",
            schema: None,
            columns: &cols,
            primary_keys: &pks,
            original_rows: &rows,
            modified_cells: &mods,
            inserted_rows: &[],
            deleted_row_indices: &deleted,
            column_data_types: Some(&types),
            column_meta: None,
        });
        assert_eq!(
            plan.statements[0].sql,
            r#"UPDATE "t" SET "note" = 'NULL' WHERE "id" = 1"#
        );
    }
}
