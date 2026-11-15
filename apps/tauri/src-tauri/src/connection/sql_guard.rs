//! sqlparser-rs query guards (Flutter MCP / table-browser parity).
//!
//! Product rules for `db_execute_query`:
//! 1. Exactly one statement per call (trailing `;` / comments OK).
//! 2. Dangerous DML/DDL (DROP / TRUNCATE / unconditional DELETE|UPDATE)
//!    requires an explicit `confirmed` flag from the UI (#1885).

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use sqlparser::ast::{ObjectType, Statement};
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

/// Why a statement needs an explicit UI confirmation before running.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DangerousSqlKind {
    Drop,
    Truncate,
    UnconditionalDelete,
    UnconditionalUpdate,
}

impl serde::Serialize for DangerousSqlKind {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(self.as_str())
    }
}

impl DangerousSqlKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Drop => "drop",
            Self::Truncate => "truncate",
            Self::UnconditionalDelete => "unconditional_delete",
            Self::UnconditionalUpdate => "unconditional_update",
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

/// Full gate for `db_execute_query`: single-statement + destructive confirm.
pub fn assert_query_allowed(
    sql: &str,
    driver: DriverKind,
    confirmed: bool,
) -> ConnectionResult<()> {
    let stmt = parse_single_statement(sql, driver)?;
    if confirmed {
        return Ok(());
    }
    if let Some((kind, message)) = classify_dangerous(&stmt) {
        return Err(ConnectionError::needs_confirmation(kind, message));
    }
    Ok(())
}

fn parse_single_statement(sql: &str, driver: DriverKind) -> ConnectionResult<Statement> {
    let trimmed = sql.trim();
    if trimmed.is_empty() {
        return Err(empty_err());
    }

    let mut statements = parse_statements(trimmed, driver)?;
    match statements.len() {
        0 => Err(empty_err()),
        1 => Ok(statements.pop().expect("len checked")),
        n => Err(ConnectionError::sql_guard(
            SqlGuardRule::MultiStatement,
            format!(
                "Only one statement per call is allowed; got {n}. Send them separately."
            ),
        )),
    }
}

fn parse_statements(sql: &str, driver: DriverKind) -> ConnectionResult<Vec<Statement>> {
    let primary = match driver {
        DriverKind::Postgres => Parser::parse_sql(&PostgreSqlDialect {}, sql),
        DriverKind::Sqlite => Parser::parse_sql(&SQLiteDialect {}, sql),
        DriverKind::Mysql => Parser::parse_sql(&MySqlDialect {}, sql),
        DriverKind::Redis => {
            return Err(ConnectionError::UnsupportedDriver {
                driver: DriverKind::Redis,
            });
        }
    };

    match primary {
        Ok(stmts) => Ok(stmts),
        Err(primary_err) if !matches!(driver, DriverKind::Mysql) => {
            Parser::parse_sql(&GenericDialect {}, sql).map_err(|_| parse_err(primary_err))
        }
        Err(primary_err) => Err(parse_err(primary_err)),
    }
}

fn classify_dangerous(stmt: &Statement) -> Option<(DangerousSqlKind, String)> {
    match stmt {
        Statement::Drop { object_type, names, .. } => {
            let target = names
                .first()
                .map(ToString::to_string)
                .unwrap_or_else(|| "object".into());
            let label = object_type_label(*object_type);
            Some((
                DangerousSqlKind::Drop,
                format!("DROP {label} \"{target}\" requires confirmation."),
            ))
        }
        Statement::Truncate(truncate) => {
            let target = truncate
                .table_names
                .first()
                .map(|t| t.name.to_string())
                .unwrap_or_else(|| "table".into());
            Some((
                DangerousSqlKind::Truncate,
                format!("TRUNCATE \"{target}\" requires confirmation."),
            ))
        }
        Statement::Delete(delete) if delete.selection.is_none() => {
            let target = delete_target_name(delete);
            Some((
                DangerousSqlKind::UnconditionalDelete,
                format!(
                    "DELETE FROM \"{target}\" without WHERE requires confirmation."
                ),
            ))
        }
        Statement::Update(update) if update.selection.is_none() => {
            let target = update.table.relation.to_string();
            Some((
                DangerousSqlKind::UnconditionalUpdate,
                format!(
                    "UPDATE \"{target}\" without WHERE requires confirmation."
                ),
            ))
        }
        _ => None,
    }
}

fn object_type_label(object_type: ObjectType) -> String {
    object_type.to_string()
}

fn delete_target_name(delete: &sqlparser::ast::Delete) -> String {
    if let Some(name) = delete.tables.first() {
        return name.to_string();
    }
    match &delete.from {
        sqlparser::ast::FromTable::WithFromKeyword(tables)
        | sqlparser::ast::FromTable::WithoutKeyword(tables) => tables
            .first()
            .map(|t| t.relation.to_string())
            .unwrap_or_else(|| "table".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn allow(sql: &str, driver: DriverKind) {
        assert_query_allowed(sql, driver, false).unwrap_or_else(|e| {
            panic!("expected allow for {sql:?} ({driver}): {e}");
        });
    }

    fn allow_confirmed(sql: &str, driver: DriverKind) {
        assert_query_allowed(sql, driver, true).unwrap_or_else(|e| {
            panic!("expected allow with confirm for {sql:?} ({driver}): {e}");
        });
    }

    fn block_rule(sql: &str, driver: DriverKind, rule: SqlGuardRule) {
        let err = assert_query_allowed(sql, driver, false).expect_err("expected block");
        match err {
            ConnectionError::SqlGuard { rule: r, .. } => assert_eq!(r, rule),
            other => panic!("expected SqlGuard, got {other:?}"),
        }
    }

    fn needs_confirm(sql: &str, driver: DriverKind, kind: DangerousSqlKind) {
        let err = assert_query_allowed(sql, driver, false).expect_err("expected confirm");
        match err {
            ConnectionError::NeedsConfirmation { kind: k, .. } => assert_eq!(k, kind),
            other => panic!("expected NeedsConfirmation, got {other:?}"),
        }
        allow_confirmed(sql, driver);
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
    fn allows_conditional_dml_without_confirm() {
        allow("DELETE FROM t WHERE id = 1", DriverKind::Postgres);
        allow("UPDATE t SET a = 1 WHERE id = 2", DriverKind::Sqlite);
        allow("INSERT INTO t VALUES (1)", DriverKind::Mysql);
    }

    #[test]
    fn requires_confirm_for_drop_truncate_unconditional() {
        needs_confirm(
            "DROP TABLE t",
            DriverKind::Postgres,
            DangerousSqlKind::Drop,
        );
        needs_confirm(
            "TRUNCATE TABLE t",
            DriverKind::Postgres,
            DangerousSqlKind::Truncate,
        );
        needs_confirm(
            "DELETE FROM t",
            DriverKind::Sqlite,
            DangerousSqlKind::UnconditionalDelete,
        );
        needs_confirm(
            "UPDATE t SET a = 1",
            DriverKind::Mysql,
            DangerousSqlKind::UnconditionalUpdate,
        );
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

    #[test]
    fn needs_confirmation_serde() {
        let err = ConnectionError::needs_confirmation(
            DangerousSqlKind::Drop,
            "DROP TABLE \"t\" requires confirmation.",
        );
        let json = serde_json::to_value(&err).unwrap();
        assert_eq!(json["kind"], "needs_confirmation");
        assert_eq!(json["danger"], "drop");
    }
}
