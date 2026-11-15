//! sqlparser-rs multi-statement guard (Flutter MCP / table-browser parity).
//!
//! Product rule for `db_execute_query`: exactly one statement per call.
//! Trailing semicolons and comments are fine; scripts with two+ statements
//! are refused so the UI (or a later splitter) must send them separately.
//! `#1885` will layer dangerous-DML confirmation on top of this gate.

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use sqlparser::dialect::{GenericDialect, MySqlDialect, PostgreSqlDialect, SQLiteDialect};
use sqlparser::parser::Parser;

/// Stable rule ids for typed IPC / future audit logs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SqlGuardRule {
    Empty,
    MultiStatement,
    Parse,
}

impl serde::Serialize for SqlGuardRule {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(self.as_str())
    }
}

impl SqlGuardRule {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Empty => "empty_query",
            Self::MultiStatement => "single_statement",
            Self::Parse => "parse_error",
        }
    }
}

const EMPTY_QUERY_MSG: &str = "The query is empty.";

fn empty_err() -> ConnectionError {
    ConnectionError::sql_guard(SqlGuardRule::Empty, EMPTY_QUERY_MSG)
}

fn parse_err(e: impl std::fmt::Display) -> ConnectionError {
    ConnectionError::sql_guard(SqlGuardRule::Parse, format!("SQL parse error: {e}"))
}

/// Parse `sql` and ensure it is exactly one statement for `driver`.
pub fn assert_single_statement(sql: &str, driver: DriverKind) -> ConnectionResult<()> {
    let trimmed = sql.trim();
    if trimmed.is_empty() {
        return Err(empty_err());
    }

    let count = statement_count(trimmed, driver)?;
    match count {
        0 => Err(empty_err()),
        1 => Ok(()),
        n => Err(ConnectionError::sql_guard(
            SqlGuardRule::MultiStatement,
            format!(
                "Only one statement per call is allowed; got {n}. Send them separately."
            ),
        )),
    }
}

fn statement_count(sql: &str, driver: DriverKind) -> ConnectionResult<usize> {
    let primary = match driver {
        DriverKind::Postgres => Parser::parse_sql(&PostgreSqlDialect {}, sql),
        DriverKind::Sqlite => Parser::parse_sql(&SQLiteDialect {}, sql),
        DriverKind::Mysql => Parser::parse_sql(&MySqlDialect {}, sql),
    };

    let statements = match primary {
        Ok(stmts) => stmts,
        Err(primary_err) if !matches!(driver, DriverKind::Mysql) => {
            Parser::parse_sql(&GenericDialect {}, sql).map_err(|_| parse_err(primary_err))?
        }
        Err(primary_err) => return Err(parse_err(primary_err)),
    };

    Ok(statements.len())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn allow(sql: &str, driver: DriverKind) {
        assert_single_statement(sql, driver).unwrap_or_else(|e| {
            panic!("expected allow for {sql:?} ({driver}): {e}");
        });
    }

    fn block_rule(sql: &str, driver: DriverKind, rule: SqlGuardRule) {
        let err = assert_single_statement(sql, driver).expect_err("expected block");
        match err {
            ConnectionError::SqlGuard { rule: r, .. } => assert_eq!(r, rule),
            other => panic!("expected SqlGuard, got {other:?}"),
        }
    }

    #[test]
    fn allows_single_select() {
        allow("SELECT 1", DriverKind::Sqlite);
        allow("SELECT * FROM t", DriverKind::Postgres);
        allow("SELECT 1", DriverKind::Mysql);
    }

    #[test]
    fn allows_trailing_semicolon_and_comment() {
        allow("SELECT * FROM t;", DriverKind::Postgres);
        allow("SELECT * FROM t; -- done", DriverKind::Postgres);
        allow("SELECT 1; /* trailing */", DriverKind::Sqlite);
    }

    #[test]
    fn allows_with_select_and_values() {
        allow(
            "WITH x AS (SELECT 1) SELECT * FROM x",
            DriverKind::Postgres,
        );
        allow("VALUES (1)", DriverKind::Postgres);
        allow("(SELECT 1)", DriverKind::Postgres);
    }

    #[test]
    fn allows_semicolon_inside_string_literal() {
        allow(
            "SELECT * FROM logs WHERE message = 'error; system halted'",
            DriverKind::Postgres,
        );
        allow("SELECT 'a;b' AS x", DriverKind::Sqlite);
    }

    #[test]
    fn allows_single_dml_for_now() {
        // Dangerous-DML confirmation is #1885; this gate only counts statements.
        allow("DELETE FROM t", DriverKind::Postgres);
        allow("UPDATE t SET a = 1", DriverKind::Sqlite);
        allow("INSERT INTO t VALUES (1)", DriverKind::Mysql);
    }

    #[test]
    fn rejects_multi_statement_even_when_first_is_select() {
        block_rule(
            "SELECT 1; DELETE FROM t",
            DriverKind::Postgres,
            SqlGuardRule::MultiStatement,
        );
        block_rule(
            "SELECT 1; SELECT 2",
            DriverKind::Sqlite,
            SqlGuardRule::MultiStatement,
        );
        block_rule(
            "SELECT 1; SELECT 2; SELECT 3",
            DriverKind::Mysql,
            SqlGuardRule::MultiStatement,
        );
    }

    #[test]
    fn rejects_empty_and_whitespace() {
        block_rule("", DriverKind::Sqlite, SqlGuardRule::Empty);
        block_rule("   \n\t  ", DriverKind::Postgres, SqlGuardRule::Empty);
        block_rule("-- only a comment", DriverKind::Postgres, SqlGuardRule::Empty);
        block_rule("/* block */", DriverKind::Sqlite, SqlGuardRule::Empty);
    }

    #[test]
    fn rejects_unparseable_sql() {
        block_rule("SELECT FROM WHERE", DriverKind::Postgres, SqlGuardRule::Parse);
    }

    /// Parity with Flutter MCP security splitter vectors (`mcp_security_test` /
    /// `mcp_sql_guard_test`): comment-hidden `;`, dollar quotes, backslash smuggle.
    #[test]
    fn rejects_hidden_second_statements() {
        block_rule(
            "SELECT 1 /* ; */; DROP TABLE t",
            DriverKind::Postgres,
            SqlGuardRule::MultiStatement,
        );
        block_rule(
            "SELECT $$ ; $$; DROP TABLE t",
            DriverKind::Postgres,
            SqlGuardRule::MultiStatement,
        );
        // Postgres/SQLite: `\'` does not escape inside `'...'`, so this is two
        // statements (string ends at the second `'`, then DELETE…).
        block_rule(
            "SELECT 'a\\'; DELETE FROM users; --'",
            DriverKind::Postgres,
            SqlGuardRule::MultiStatement,
        );
        block_rule(
            "SELECT 'a\\'; DELETE FROM users; --'",
            DriverKind::Sqlite,
            SqlGuardRule::MultiStatement,
        );
    }

    #[test]
    fn sql_guard_error_serde() {
        let err = ConnectionError::sql_guard(
            SqlGuardRule::MultiStatement,
            "Only one statement per call is allowed; got 2. Send them separately.",
        );
        let json = serde_json::to_value(&err).unwrap();
        assert_eq!(json["kind"], "sql_guard");
        assert_eq!(json["rule"], "single_statement");
    }
}