import 'package:querya_desktop/core/database/sqlite_connection.dart';

/// Columns for Table Browser `ORDER BY`.
///
/// Declared PK first. Ordinary tables with no PK use implicit `rowid`.
/// Views omit `ORDER BY` (no PK, no `rowid`).
List<String> sqliteBrowseOrderColumns({
  required List<String> primaryKeys,
  required bool isView,
}) {
  if (primaryKeys.isNotEmpty) return List<String>.from(primaryKeys);
  if (!isView) return const ['rowid'];
  return const [];
}

/// Browse SELECT for Table Browser. PK / `rowid` keep LIMIT/OFFSET stable.
String sqliteBrowseDataSql({
  required String qualifiedFrom,
  required List<String> primaryKeys,
  required bool isView,
  required int limit,
  required int offset,
}) {
  final orderCols = sqliteBrowseOrderColumns(
    primaryKeys: primaryKeys,
    isView: isView,
  );
  final order = orderCols.isEmpty
      ? ''
      : ' ORDER BY ${orderCols.map(SqliteConnection.quoteIdentifier).join(', ')}';
  return 'SELECT * FROM $qualifiedFrom$order LIMIT $limit OFFSET $offset';
}
