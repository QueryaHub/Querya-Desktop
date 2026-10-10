import 'package:flutter/foundation.dart';

@immutable
class ErdColumn {
  const ErdColumn({
    required this.name,
    required this.type,
    this.isPrimaryKey = false,
    this.isForeignKey = false,
    this.isNullable = false,
    this.isUnique = false,
    this.defaultValue,
    this.isIdentity = false,
    this.comment,
  });

  final String name;
  final String type;
  final bool isPrimaryKey;
  final bool isForeignKey;
  final bool isNullable;

  /// A single-column unique constraint or index on it (a primary key is not
  /// counted: it is unique anyway).
  final bool isUnique;

  /// The default expression as the database prints it; null when none.
  final String? defaultValue;

  /// Filled by the database: identity, serial / sequence default,
  /// auto_increment, or SQLite's INTEGER PRIMARY KEY.
  final bool isIdentity;

  /// The column's comment in the database (`COMMENT ON COLUMN`); null when
  /// none (#1279).
  final String? comment;

  /// Short markers after the type on a card and in exports (#1277).
  List<String> get badges => [
        if (isUnique && !isPrimaryKey) 'UQ',
        if (isIdentity) 'AI',
        if (defaultValue != null && !isIdentity) 'DF',
      ];

  ErdColumn copyWith({bool? isForeignKey}) => ErdColumn(
        name: name,
        type: type,
        isPrimaryKey: isPrimaryKey,
        isForeignKey: isForeignKey ?? this.isForeignKey,
        isNullable: isNullable,
        isUnique: isUnique,
        defaultValue: defaultValue,
        isIdentity: isIdentity,
        comment: comment,
      );
}

@immutable
class ErdTable {
  const ErdTable({required this.name, required this.columns, this.comment});

  final String name;
  final List<ErdColumn> columns;

  /// The table's comment in the database (`COMMENT ON TABLE`) (#1279).
  final String? comment;
}

/// A foreign key: [fromTable].[fromColumn] references [toTable].[toColumn].
/// [optional] when the referencing column may be NULL ("zero or many").
@immutable
class ErdRelation {
  const ErdRelation({
    required this.fromTable,
    required this.fromColumn,
    required this.toTable,
    required this.toColumn,
    this.optional = false,
  });

  final String fromTable;
  final String fromColumn;
  final String toTable;
  final String toColumn;
  final bool optional;
}

@immutable
class ErdSchema {
  const ErdSchema({
    required this.tables,
    required this.relations,
    this.truncated = false,
  });

  final List<ErdTable> tables;
  final List<ErdRelation> relations;

  /// The catalog was cut at its row limit: some tables or columns are missing.
  final bool truncated;

  bool get isEmpty => tables.isEmpty;

  /// Builds a schema from flat catalog rows.
  ///
  /// [columnRows]: `table, column, type, isPk`, then optionally `isNullable`,
  /// `isUnique`, `default` and `isIdentity` (#1277), then the column comment
  /// and the table comment (#1279). [fkRows]: `table, column, refTable, refColumn`. Relations to
  /// unknown tables are dropped.
  factory ErdSchema.fromCatalog({
    required List<List<String>> columnRows,
    required List<List<String>> fkRows,
    bool truncated = false,
  }) {
    final order = <String>[];
    final tableComments = <String, String>{};
    final cols = <String, List<ErdColumn>>{};
    for (final r in columnRows) {
      if (r.length < 4) continue;
      final list = cols.putIfAbsent(r[0], () {
        order.add(r[0]);
        return [];
      });
      list.add(ErdColumn(
        name: r[1],
        type: r[2],
        isPrimaryKey: _truthy(r[3]),
        isNullable: r.length > 4 && _truthy(r[4]),
        isUnique: r.length > 5 && _truthy(r[5]),
        defaultValue: r.length > 6 ? _default(r[6]) : null,
        isIdentity: r.length > 7 && _truthy(r[7]),
        comment: r.length > 8 ? _text(r[8]) : null,
      ));
      if (r.length > 9) {
        final tc = _text(r[9]);
        if (tc != null) tableComments.putIfAbsent(r[0], () => tc);
      }
    }
    final nullable = {
      for (final t in cols.entries)
        for (final c in t.value)
          if (c.isNullable) '${t.key}\u0000${c.name}',
    };
    final relations = <ErdRelation>[];
    final fkCols = <String>{};
    for (final r in fkRows) {
      if (r.length < 4) continue;
      if (!cols.containsKey(r[0]) || !cols.containsKey(r[2])) continue;
      relations.add(ErdRelation(
        fromTable: r[0],
        fromColumn: r[1],
        toTable: r[2],
        toColumn: r[3],
        optional: nullable.contains('${r[0]}\u0000${r[1]}'),
      ));
      fkCols.add('${r[0]}\u0000${r[1]}');
    }
    return ErdSchema(
      tables: [
        for (final t in order)
          ErdTable(
            name: t,
            comment: tableComments[t],
            columns: [
              for (final c in cols[t]!)
                fkCols.contains('$t\u0000${c.name}')
                    ? c.copyWith(isForeignKey: true)
                    : c,
            ],
          ),
      ],
      relations: relations,
      truncated: truncated,
    );
  }

  static bool _truthy(String v) {
    final s = v.trim().toLowerCase();
    return s == '1' || s == 't' || s == 'true' || s == 'yes';
  }
}

/// A catalog default cell: empty and SQL NULL mean "no default".
String? _default(String raw) {
  final v = raw.trim();
  if (v.isEmpty || v == 'NULL' || v.toLowerCase() == 'null') return null;
  return v;
}

/// A catalog text cell: empty and SQL NULL mean none.
String? _text(String raw) {
  final v = raw.trim();
  if (v.isEmpty || v == 'NULL') return null;
  return v;
}
