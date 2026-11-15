//! Apply a [`TableMutationPlan`] inside a single DB transaction (#1889).
//!
//! On success the caller should clear the staging buffer; on failure the
//! buffer is left intact and the database is rolled back.

use super::dml::{SqlDialect, TableMutationPlan};
use super::StagingBuffer;
use rusqlite::Connection;
use serde::Serialize;
use std::fmt;

/// Outcome of a successful apply.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ApplyResult {
    pub statements_applied: usize,
}

/// Typed apply failure (transaction already rolled back).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ApplyError {
    EmptyPlan,
    DialectMismatch {
        expected: String,
        got: String,
    },
    Execute {
        statement_index: usize,
        sql: String,
        message: String,
    },
    Transaction {
        message: String,
    },
}

impl fmt::Display for ApplyError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmptyPlan => write!(f, "staging plan is empty"),
            Self::DialectMismatch { expected, got } => {
                write!(f, "plan dialect {got} does not match connection {expected}")
            }
            Self::Execute {
                statement_index,
                message,
                ..
            } => write!(f, "statement {statement_index} failed: {message}"),
            Self::Transaction { message } => write!(f, "transaction error: {message}"),
        }
    }
}

impl std::error::Error for ApplyError {}

fn dialect_name(d: SqlDialect) -> &'static str {
    match d {
        SqlDialect::Postgres => "postgres",
        SqlDialect::Mysql => "mysql",
        SqlDialect::Sqlite => "sqlite",
    }
}

/// Execute every statement in `plan` atomically on a SQLite connection.
pub fn apply_plan_sqlite(
    conn: &Connection,
    plan: &TableMutationPlan,
) -> Result<ApplyResult, ApplyError> {
    if !matches!(plan.dialect, SqlDialect::Sqlite) {
        return Err(ApplyError::DialectMismatch {
            expected: "sqlite".into(),
            got: dialect_name(plan.dialect).into(),
        });
    }
    if plan.is_empty() {
        return Err(ApplyError::EmptyPlan);
    }

    let tx = conn
        .unchecked_transaction()
        .map_err(|e| ApplyError::Transaction {
            message: e.to_string(),
        })?;

    for (i, stmt) in plan.statements.iter().enumerate() {
        tx.execute(&stmt.sql, [])
            .map_err(|e| ApplyError::Execute {
                statement_index: i,
                sql: stmt.sql.clone(),
                message: e.to_string(),
            })?;
    }

    tx.commit().map_err(|e| ApplyError::Transaction {
        message: e.to_string(),
    })?;

    Ok(ApplyResult {
        statements_applied: plan.statements.len(),
    })
}

/// Generate DML from `buffer`, apply it, and **only on success** clear staging.
pub fn apply_staging_sqlite(
    conn: &Connection,
    buffer: &mut StagingBuffer,
    table_name: &str,
    schema: Option<&str>,
) -> Result<ApplyResult, ApplyError> {
    let plan = buffer.generate_mutation_plan(
        SqlDialect::Sqlite,
        table_name,
        schema,
        None,
        None,
    );
    if plan.is_empty() {
        return Err(ApplyError::EmptyPlan);
    }
    let result = apply_plan_sqlite(conn, &plan)?;
    buffer.revert_all();
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::staging::{StagedRowStatus, StagingBuffer};
    use rusqlite::Connection;

    fn open_users_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            r#"
            CREATE TABLE users (
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL,
              email TEXT
            );
            INSERT INTO users (id, name, email) VALUES
              (1, 'Alice', 'alice@test.com'),
              (2, 'Bob', 'bob@test.com'),
              (3, 'Charlie', 'charlie@test.com');
            "#,
        )
        .unwrap();
        conn
    }

    fn load_buffer(conn: &Connection) -> StagingBuffer {
        let mut stmt = conn
            .prepare("SELECT id, name, email FROM users ORDER BY id")
            .unwrap();
        let rows: Vec<Vec<String>> = stmt
            .query_map([], |r| {
                Ok(vec![
                    r.get::<_, i64>(0)?.to_string(),
                    r.get::<_, String>(1)?,
                    r.get::<_, Option<String>>(2)?
                        .unwrap_or_else(|| "NULL".into()),
                ])
            })
            .unwrap()
            .map(|r| r.unwrap())
            .collect();
        StagingBuffer::new(["id", "name", "email"], rows, ["id"])
    }

    fn read_users(conn: &Connection) -> Vec<(i64, String, Option<String>)> {
        let mut stmt = conn
            .prepare("SELECT id, name, email FROM users ORDER BY id")
            .unwrap();
        stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
            .unwrap()
            .map(|r| r.unwrap())
            .collect()
    }

    /// E2E: stage update + insert + delete → generate → apply → DB matches.
    #[test]
    fn e2e_stage_generate_apply_clears_buffer_on_success() {
        let conn = open_users_db();
        let mut buf = load_buffer(&conn);

        buf.set_cell(0, 1, "Alice Cooper");
        buf.toggle_delete_row(1); // Bob
        buf.add_row(Some(vec![
            "4".into(),
            "Diana".into(),
            "diana@test.com".into(),
        ]));
        assert!(buf.is_dirty());
        assert_eq!(buf.change_count(), 3);

        let result = apply_staging_sqlite(&conn, &mut buf, "users", None).unwrap();
        assert_eq!(result.statements_applied, 3);
        assert!(!buf.is_dirty());
        assert_eq!(buf.total_row_count(), 3); // reverted to original snapshot length
        assert_eq!(buf.row_status(0), StagedRowStatus::Unchanged);

        let users = read_users(&conn);
        assert_eq!(
            users,
            vec![
                (1, "Alice Cooper".into(), Some("alice@test.com".into())),
                (3, "Charlie".into(), Some("charlie@test.com".into())),
                (4, "Diana".into(), Some("diana@test.com".into())),
            ]
        );
    }

    /// E2E: failed statement rolls back DB and leaves staging dirty.
    #[test]
    fn e2e_apply_failure_rolls_back_and_keeps_staging() {
        let conn = open_users_db();
        let mut buf = load_buffer(&conn);
        buf.set_cell(0, 1, "Alice Updated");

        // Force a plan that will fail: insert with duplicate primary key.
        buf.add_row(Some(vec![
            "1".into(), // duplicate id
            "Dup".into(),
            "dup@test.com".into(),
        ]));
        assert!(buf.is_dirty());

        let err = apply_staging_sqlite(&conn, &mut buf, "users", None).unwrap_err();
        assert!(
            matches!(err, ApplyError::Execute { .. }),
            "expected Execute, got {err:?}"
        );
        assert!(buf.is_dirty(), "staging must stay intact after failure");
        assert_eq!(buf.get_cell_value(0, 1), "Alice Updated");
        assert_eq!(buf.inserted_row_count(), 1);

        // DB unchanged (Bob still there, Alice not renamed).
        let users = read_users(&conn);
        assert_eq!(
            users,
            vec![
                (1, "Alice".into(), Some("alice@test.com".into())),
                (2, "Bob".into(), Some("bob@test.com".into())),
                (3, "Charlie".into(), Some("charlie@test.com".into())),
            ]
        );
    }

    #[test]
    fn e2e_empty_plan_errors_without_touching_db() {
        let conn = open_users_db();
        let mut buf = load_buffer(&conn);
        let err = apply_staging_sqlite(&conn, &mut buf, "users", None).unwrap_err();
        assert_eq!(err, ApplyError::EmptyPlan);
        assert_eq!(read_users(&conn).len(), 3);
    }

    #[test]
    fn e2e_set_null_and_conditional_update_only() {
        let conn = open_users_db();
        let mut buf = load_buffer(&conn);
        buf.set_cell_null(2, 2); // Charlie email → NULL

        let result = apply_staging_sqlite(&conn, &mut buf, "users", None).unwrap();
        assert_eq!(result.statements_applied, 1);
        assert!(!buf.is_dirty());

        let users = read_users(&conn);
        assert_eq!(users[2], (3, "Charlie".into(), None));
    }
}
