import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/mysql/mysql_sql_workspace.dart';
import 'package:querya_desktop/features/postgresql/postgres_sql_workspace.dart';
import 'package:querya_desktop/features/sqlite/sqlite_sql_workspace.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

/// Production [McpDelegateFactory]: the SQL editor's delegates, always on the
/// MCP session (its own pool slot) and read-only (Postgres `default_transaction_read_only`, MySQL
/// `SET SESSION TRANSACTION READ ONLY`, SQLite `SQLITE_OPEN_READONLY`).
SqlExecutionDelegate createReadOnlyMcpDelegate(
  ConnectionRow row,
  SqlDialect dialect,
) {
  switch (dialect) {
    case SqlDialect.postgres:
      final db = row.databaseName?.trim();
      return PostgresSqlExecutionDelegate(
        connectionRow: row,
        isReadOnly: true,
        isMcp: true,
        effectiveDatabaseProvider: () =>
            db == null || db.isEmpty ? 'postgres' : db,
        autocommitProvider: () => true,
      );
    case SqlDialect.mysql:
      return MysqlSqlExecutionDelegate(
        connectionRow: row,
        isReadOnly: true,
        isMcp: true,
      );
    case SqlDialect.sqlite:
      return SqliteSqlExecutionDelegate(
        connectionRow: row,
        isReadOnly: true,
        isMcp: true,
      );
  }
}
