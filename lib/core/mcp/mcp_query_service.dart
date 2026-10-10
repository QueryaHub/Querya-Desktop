import 'dart:async';

import 'package:querya_desktop/core/database/database_error_mapper.dart';
import 'package:querya_desktop/core/database/sql_query_runner.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/mcp/mcp_access_store.dart';
import 'package:querya_desktop/core/mcp/mcp_redaction.dart';
import 'package:querya_desktop/core/mcp/mcp_sql_guard.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// A failure the MCP client should see as a tool error (the model reads the
/// message and can fix its call).
class McpToolException implements Exception {
  const McpToolException(this.message, {this.rule});

  final String message;

  /// The guard rule that refused the call, when a rule did.
  final String? rule;

  @override
  String toString() => message;
}

/// Creates a **read-only** execution delegate for [row]; the service disposes
/// it after each call.
typedef McpDelegateFactory = SqlQueryRunner Function(
  ConnectionRow row,
  SqlDialect dialect,
);

/// Read-only SQL for MCP tools: connection list, schema, samples, queries and
/// plans for PostgreSQL, MySQL and SQLite.
///
/// Never exposes host, user, password, SSH settings or connection strings.
/// Every query passes [McpSqlGuard] and runs on a read-only database session
/// with a statement timeout and a row limit.
class McpQueryService {
  McpQueryService({
    required McpDelegateFactory createDelegate,
    McpAccessPolicy? access,
    Future<List<ConnectionRow>> Function()? loadConnections,
    this.maxRows = 1000,
    this.maxSampleRows = 100,
    this.timeout = const Duration(seconds: 15),
    this.maxCellChars = 4096,
  })  : _createDelegate = createDelegate,
        _access = access ?? McpAccessStore.instance,
        _loadConnections =
            loadConnections ?? (() => LocalDb.instance.getConnections());

  final McpDelegateFactory _createDelegate;
  final McpAccessPolicy _access;
  final Future<List<ConnectionRow>> Function() _loadConnections;

  final int maxRows;
  final int maxSampleRows;
  final Duration timeout;
  final int maxCellChars;

  /// Upper bound for catalog queries (one row per column of the schema).
  static const _catalogRows = 200000;

  static SqlDialect? dialectOf(String type) => switch (type) {
        'postgresql' => SqlDialect.postgres,
        'mysql' => SqlDialect.mysql,
        'sqlite' => SqlDialect.sqlite,
        _ => null,
      };

  /// Connections the user opened to MCP, without any credentials.
  Future<List<McpConnectionInfo>> listConnections() async {
    final out = <McpConnectionInfo>[];
    for (final row in await _loadConnections()) {
      if (row.id == null || dialectOf(row.type) == null) continue;
      if (!await _access.canRead(row)) continue;
      out.add(McpConnectionInfo.fromRow(row));
    }
    return out;
  }

  Future<List<McpTableSummary>> listTables(int connectionId) async {
    final cat = await _withDelegate(connectionId, _loadCatalog);
    return [
      for (final t in cat.schema.tables)
        McpTableSummary(
          name: t.name,
          columnCount: t.columns.length,
          isView: cat.views.contains(t.name),
        ),
    ];
  }

  /// All tables with columns and keys in one catalog pass (no indexes); backs
  /// the `schema://` resource.
  Future<List<McpTableDescription>> schemaOverview(int connectionId) {
    return _withDelegate(connectionId, (delegate, dialect) async {
      final schema = (await _loadCatalog(delegate, dialect)).schema;
      return [for (final t in schema.tables) _describe(schema, t, const [])];
    });
  }

  Future<McpTableDescription> describeTable(
    int connectionId,
    String table,
  ) {
    return _withDelegate(connectionId, (delegate, dialect) async {
      final cat = await _loadCatalog(delegate, dialect);
      final schema = cat.schema;
      final t = _findTable(schema, table);
      if (cat.views.contains(t.name)) return _describe(schema, t, const []);
      final indexes = await _run(
        () => delegate.executeQuery(
          _indexesSql(dialect, t.name),
          limit: _catalogRows,
          timeout: timeout,
        ),
        dialect,
      );
      return _describe(schema, t, [
        for (final r in indexes.rows)
          if (r.length >= 2) McpIndexInfo(name: r[0], definition: r[1]),
      ]);
    });
  }

  static McpTableDescription _describe(
    ErdSchema schema,
    ErdTable t,
    List<McpIndexInfo> indexes,
  ) =>
      McpTableDescription(
        name: t.name,
        columns: [
          for (final c in t.columns)
            McpColumnInfo(
              name: c.name,
              type: c.type,
              primaryKey: c.isPrimaryKey,
              references: [
                for (final r in schema.relations)
                  if (r.fromTable == t.name && r.fromColumn == c.name)
                    '${r.toTable}.${r.toColumn}',
              ].firstOrNull,
            ),
        ],
        indexes: indexes,
      );

  Future<McpQueryResult> sampleRows(
    int connectionId,
    String table, {
    int rows = 20,
  }) {
    final n = rows.clamp(1, maxSampleRows);
    return _withDelegate(connectionId, (delegate, dialect) async {
      final t =
          _findTable((await _loadCatalog(delegate, dialect)).schema, table);
      final result = await _run(
        () => delegate.executeQuery(
          'SELECT * FROM ${quoteIdentifier(t.name, dialect)}',
          limit: n,
          timeout: timeout,
        ),
        dialect,
      );
      return _toResult(result, n);
    });
  }

  Future<McpQueryResult> runQuery(int connectionId, String sql) {
    return _withDelegate(connectionId, (delegate, dialect) async {
      _guard(sql, dialect);
      final result = await _run(
        () => delegate.executeQuery(sql, limit: maxRows, timeout: timeout),
        dialect,
      );
      return _toResult(result, maxRows);
    });
  }

  Future<String> explainQuery(int connectionId, String sql) {
    return _withDelegate(connectionId, (delegate, dialect) async {
      _guard(sql, dialect);
      if (!delegate.supportsExplain) {
        throw const McpToolException('EXPLAIN is not supported for this connection.');
      }
      final stripped = sql.trim().replaceAll(RegExp(r';\s*$'), '');
      if (RegExp(r'^explain\b', caseSensitive: false).hasMatch(stripped)) {
        throw const McpToolException(
            'Pass the statement itself; explain_query adds EXPLAIN.');
      }
      return _run(
        () => delegate.explainQuery(stripped).timeout(timeout),
        dialect,
      );
    });
  }

  // ---------------------------------------------------------------------------

  static String quoteIdentifier(String name, SqlDialect dialect) =>
      dialect == SqlDialect.mysql
          ? '`${name.replaceAll('`', '``')}`'
          : '"${name.replaceAll('"', '""')}"';

  static String _literal(String value, SqlDialect dialect) {
    var v = value.replaceAll("'", "''");
    if (dialect == SqlDialect.mysql) v = v.replaceAll(r'\', r'\\');
    return "'$v'";
  }

  static String _indexesSql(SqlDialect dialect, String table) {
    final t = _literal(table, dialect);
    return switch (dialect) {
      SqlDialect.postgres => 'SELECT indexname, indexdef FROM pg_indexes '
          'WHERE schemaname = current_schema() AND tablename = $t ORDER BY indexname',
      SqlDialect.mysql => "SELECT index_name, CONCAT(IF(MIN(non_unique) = 0, 'UNIQUE ', ''), "
          "'(', GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR ', '), ')') "
          'FROM information_schema.statistics '
          'WHERE table_schema = DATABASE() AND table_name = $t '
          'GROUP BY index_name ORDER BY index_name',
      SqlDialect.sqlite => "SELECT name, COALESCE(sql, '(automatic)') FROM sqlite_master "
          "WHERE type = 'index' AND tbl_name = $t ORDER BY name",
    };
  }

  void _guard(String sql, SqlDialect dialect) {
    final refusal = McpSqlGuard.refusal(sql, dialect);
    if (refusal != null) {
      throw McpToolException(refusal.message, rule: refusal.rule);
    }
  }

  /// Tables and keys, then the views: a name that is already a table stays a
  /// table. Views have no keys and no indexes.
  Future<({ErdSchema schema, Set<String> views})> _loadCatalog(
    SqlQueryRunner delegate,
    SqlDialect dialect,
  ) async {
    final base = await _loadSchema(delegate, dialect);
    final viewRows = await _run(
      () => delegate.executeQuery(ErdCatalog.viewColumnsSql(dialect),
          limit: _catalogRows, timeout: timeout),
      dialect,
    );
    final known = {for (final t in base.tables) t.name};
    final views = [
      for (final t in ErdSchema.fromCatalog(
              columnRows: viewRows.rows, fkRows: const [])
          .tables)
        if (!known.contains(t.name)) t,
    ];
    return (
      schema: ErdSchema(
        tables: [...base.tables, ...views],
        relations: base.relations,
        truncated: base.truncated,
      ),
      views: {for (final v in views) v.name},
    );
  }

  Future<ErdSchema> _loadSchema(
    SqlQueryRunner delegate,
    SqlDialect dialect,
  ) async {
    final cols = await _run(
      () => delegate.executeQuery(ErdCatalog.columnsSql(dialect),
          limit: _catalogRows, timeout: timeout),
      dialect,
    );
    final fks = await _run(
      () => delegate.executeQuery(ErdCatalog.foreignKeysSql(dialect),
          limit: _catalogRows, timeout: timeout),
      dialect,
    );
    return ErdSchema.fromCatalog(columnRows: cols.rows, fkRows: fks.rows);
  }

  /// Exact name first, then a unique case-insensitive match. The table must
  /// exist in the catalog, so model input never reaches SQL unchecked.
  ErdTable _findTable(ErdSchema schema, String name) {
    final exact = schema.tables.where((t) => t.name == name);
    if (exact.isNotEmpty) return exact.first;
    final lower = name.toLowerCase();
    final loose =
        schema.tables.where((t) => t.name.toLowerCase() == lower).toList();
    if (loose.length == 1) return loose.single;
    throw McpToolException(
        'Table "$name" not found. Call list_tables to see the available tables.');
  }

  Future<T> _run<T>(Future<T> Function() body, SqlDialect dialect) async {
    try {
      return await body();
    } on McpToolException {
      rethrow;
    } on TimeoutException {
      throw McpToolException(
          'The query exceeded the ${timeout.inSeconds} s time limit.');
    } catch (e) {
      throw McpToolException(describeDatabaseError(e, driver: _driver(dialect)));
    }
  }

  static DatabaseDriver _driver(SqlDialect d) => switch (d) {
        SqlDialect.postgres => DatabaseDriver.postgres,
        SqlDialect.mysql => DatabaseDriver.mysql,
        SqlDialect.sqlite => DatabaseDriver.sqlite,
      };

  McpQueryResult _toResult(SqlExecutionResult r, int limit) {
    final rows = r.rows.length > limit ? r.rows.sublist(0, limit) : r.rows;
    return McpQueryResult(
      columns: r.columns,
      rows: [
        for (final row in rows) [for (final cell in row) _cell(cell)],
      ],
      truncated: r.isTruncated || r.rows.length > limit,
    );
  }

  String _cell(String value) {
    if (value.length <= maxCellChars) return value;
    final cut = value.length - maxCellChars;
    return '${value.substring(0, maxCellChars)}… [truncated $cut chars]';
  }

  Future<T> _withDelegate<T>(
    int connectionId,
    Future<T> Function(SqlQueryRunner delegate, SqlDialect dialect) body,
  ) async {
    final row = await _readableConnection(connectionId);
    final dialect = dialectOf(row.type)!;
    final SqlQueryRunner delegate;
    try {
      delegate = _createDelegate(row, dialect);
    } catch (e) {
      throw McpToolException(McpRedaction.redact('$e', row: row));
    }
    try {
      return await body(delegate, dialect);
    } on McpToolException catch (e) {
      // Driver errors may quote connection strings or options. The guard rule
      // goes on to the activity log.
      throw McpToolException(McpRedaction.redact(e.message, row: row),
          rule: e.rule);
    } finally {
      delegate.dispose();
    }
  }

  Future<ConnectionRow> _readableConnection(int id) async {
    for (final row in await _loadConnections()) {
      if (row.id != id) continue;
      if (dialectOf(row.type) == null || !await _access.canRead(row)) break;
      return row;
    }
    // Same message for "missing" and "not shared" so ids cannot be probed.
    throw McpToolException(
        'Connection $id is not available. Call list_connections to see the shared connections.');
  }
}

class McpConnectionInfo {
  const McpConnectionInfo({
    required this.id,
    required this.name,
    required this.type,
    this.environment,
    this.database,
  });

  factory McpConnectionInfo.fromRow(ConnectionRow row) => McpConnectionInfo(
        id: row.id!,
        name: row.name,
        type: row.type,
        environment: row.environment?.storageValue,
        // SQLite keeps the file path in `host`; the model only gets the name.
        database: row.type == 'sqlite'
            ? row.host?.split(RegExp(r'[\\/]')).last
            : row.databaseName,
      );

  final int id;
  final String name;
  final String type;
  final String? environment;
  final String? database;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        if (environment != null) 'environment': environment,
        if (database != null && database!.isNotEmpty) 'database': database,
      };
}

class McpTableSummary {
  const McpTableSummary({
    required this.name,
    required this.columnCount,
    this.isView = false,
  });

  final String name;
  final int columnCount;
  final bool isView;

  Map<String, Object?> toJson() => {
        'name': name,
        'columns': columnCount,
        if (isView) 'kind': 'view',
      };
}

class McpColumnInfo {
  const McpColumnInfo({
    required this.name,
    required this.type,
    this.primaryKey = false,
    this.references,
  });

  final String name;
  final String type;
  final bool primaryKey;

  /// `table.column` this column points to, when it is a foreign key.
  final String? references;

  Map<String, Object?> toJson() => {
        'name': name,
        'type': type,
        if (primaryKey) 'primary_key': true,
        if (references != null) 'references': references,
      };
}

class McpIndexInfo {
  const McpIndexInfo({required this.name, required this.definition});

  final String name;
  final String definition;

  Map<String, Object?> toJson() => {'name': name, 'definition': definition};
}

class McpTableDescription {
  const McpTableDescription({
    required this.name,
    required this.columns,
    required this.indexes,
  });

  final String name;
  final List<McpColumnInfo> columns;
  final List<McpIndexInfo> indexes;

  Map<String, Object?> toJson() => {
        'name': name,
        'columns': [for (final c in columns) c.toJson()],
        'indexes': [for (final i in indexes) i.toJson()],
      };
}

class McpQueryResult {
  const McpQueryResult({
    required this.columns,
    required this.rows,
    required this.truncated,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final bool truncated;

  Map<String, Object?> toJson() => {
        'columns': columns,
        'rows': rows,
        'row_count': rows.length,
        'truncated': truncated,
      };
}
