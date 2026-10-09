import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/table_data_delegate.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';

/// Synthetic [TableDataMutationDelegate] for `GenericTableView` tests: serves
/// pages from an in-memory table and records the applied mutation plans.
class FakeTableDataDelegate extends TableDataMutationDelegate {
  FakeTableDataDelegate({
    this.columns = const ['id', 'name', 'email'],
    List<List<String>>? rows,
    this.primaryKeys = const ['id'],
    this.failLoadWith,
    this.onCustomSql,
  }) : rows = rows ??
            const [
              ['1', 'Alice', 'alice@example.com'],
              ['2', 'Bob', 'bob@example.com'],
              ['3', 'Carol', 'carol@example.com'],
            ];

  final List<String> columns;
  final List<List<String>> rows;
  final List<String> primaryKeys;

  /// When set, `loadPage` throws it.
  Object? failLoadWith;

  /// When set, answers `loadCustomSql` (the diagram's catalog queries).
  final TableDataPage Function(String sql)? onCustomSql;

  final pagesLoaded = <({int offset, int limit, bool refreshCount})>[];
  final customQueries = <String>[];
  final appliedPlans = <TableMutationPlan>[];
  var cancelCount = 0;
  var disposeCount = 0;

  @override
  Future<TableDataPage> loadPage({
    required int offset,
    required int limit,
    bool refreshCount = false,
  }) async {
    pagesLoaded.add((offset: offset, limit: limit, refreshCount: refreshCount));
    final error = failLoadWith;
    if (error != null) throw error;
    final end = (offset + limit).clamp(0, rows.length);
    final start = offset.clamp(0, rows.length);
    return TableDataPage(
      columns: columns,
      rows: rows.sublist(start, end),
      totalRowCount: rows.length,
    );
  }

  @override
  Future<TableDataPage> loadCustomSql(String sql) async {
    customQueries.add(sql);
    final answer = onCustomSql;
    if (answer != null) return answer(sql);
    return const TableDataPage(
      columns: ['n'],
      rows: [
        ['42'],
      ],
    );
  }

  @override
  Future<TableDataSchemaInfo> loadSchema() async => TableDataSchemaInfo(
        primaryKeys: primaryKeys,
        columnDataTypes: const {
          'id': 'integer',
          'name': 'text',
          'email': 'text',
        },
      );

  @override
  Future<void> applyStagedChanges({
    required TableMutationPlan plan,
    required DataGridStagingBuffer buffer,
    Duration? timeout,
  }) async {
    appliedPlans.add(plan);
  }

  @override
  String browseDataSql({required int offset, required int limit}) =>
      'SELECT * FROM users LIMIT $limit OFFSET $offset';

  @override
  bool isAllowedSelectQuery(String sql) =>
      sql.trim().toUpperCase().startsWith('SELECT');

  @override
  void cancel({bool interruptIfBusy = false}) => cancelCount++;

  @override
  void dispose() => disposeCount++;
}
