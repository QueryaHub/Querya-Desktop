import 'dart:convert';
import 'dart:math' as math;

/// One operation of a query plan, with its children below it.
class PlanNode {
  PlanNode({
    required this.operation,
    this.relation,
    this.estimatedRows,
    this.actualRows,
    this.cost,
    this.details = const {},
    List<PlanNode>? children,
  }) : children = children ?? const [];

  /// What the node does, as the driver names it (`Seq Scan`, `ref`, `SCAN`).
  final String operation;

  /// Table or index the node reads, when there is one.
  final String? relation;

  final double? estimatedRows;
  final double? actualRows;

  /// Cumulative cost up to and including this node, when the driver reports one.
  final double? cost;

  /// Every field the driver reported, for the details of a node.
  final Map<String, String> details;

  final List<PlanNode> children;

  /// Cost of this node alone: its cumulative cost minus its children's. Null
  /// when the driver reports no cost.
  double? get ownCost {
    final total = cost;
    if (total == null) return null;
    var own = total;
    for (final child in children) {
      final c = child.cost;
      if (c != null) own -= c;
    }
    return math.max(own, 0);
  }
}

/// Builds [PlanNode] trees from what each driver returns for EXPLAIN.
abstract final class QueryPlanParser {
  /// PostgreSQL `EXPLAIN (FORMAT JSON)`: a list with one object holding `Plan`.
  /// Accepts the JSON text or the already decoded value.
  static PlanNode? fromPostgresJson(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! List || decoded.isEmpty) return null;
    final first = decoded.first;
    if (first is! Map || first['Plan'] is! Map) return null;
    return _postgresNode(_asMap(first['Plan']!));
  }

  static PlanNode _postgresNode(Map<String, Object?> m) {
    final children = m['Plans'];
    return PlanNode(
      operation: '${m['Node Type'] ?? 'Node'}',
      relation: (m['Relation Name'] ?? m['Index Name']) as String?,
      estimatedRows: _num(m['Plan Rows']),
      actualRows: _num(m['Actual Rows']),
      cost: _num(m['Total Cost']),
      details: {
        for (final e in m.entries)
          if (e.key != 'Plans' && e.value is! Map && e.value is! List)
            e.key: '${e.value}',
      },
      children: [
        if (children is List)
          for (final c in children) _postgresNode(_asMap(c)),
      ],
    );
  }

  /// MySQL `EXPLAIN FORMAT=JSON`: `query_block` with a `nested_loop` of tables
  /// (joins), or a single `table`.
  static PlanNode? fromMysqlJson(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! Map || decoded['query_block'] is! Map) return null;
    final block = _asMap(decoded['query_block']!);
    final rootCost = _num(_asMap(block['cost_info'] ?? const {})['query_cost']);
    final tables = <PlanNode>[];
    final loop = block['nested_loop'];
    if (loop is List) {
      for (final item in loop) {
        final table = _asMap(item)['table'];
        if (table is Map) tables.add(_mysqlTable(_asMap(table)));
      }
    } else if (block['table'] is Map) {
      tables.add(_mysqlTable(_asMap(block['table']!)));
    }
    return PlanNode(
      operation: 'Query block',
      cost: rootCost,
      children: tables,
    );
  }

  static PlanNode _mysqlTable(Map<String, Object?> t) {
    final cost = _asMap(t['cost_info'] ?? const {});
    return PlanNode(
      operation: '${t['access_type'] ?? 'table'}',
      relation: t['table_name'] as String?,
      estimatedRows: _num(t['rows_examined_per_scan'] ?? t['rows_produced_per_join']),
      cost: _num(cost['prefix_cost']),
      details: {
        for (final e in t.entries)
          if (e.value is! Map && e.value is! List) e.key: '${e.value}',
      },
    );
  }

  /// SQLite `EXPLAIN QUERY PLAN`: one row per step with `id`, `parent` and
  /// `detail`. Rows with parent 0 hang below a synthetic root. SQLite reports
  /// no costs, so no node is "most expensive".
  static PlanNode? fromSqliteRows(
    List<({int id, int parent, String detail})> rows,
  ) {
    if (rows.isEmpty) return null;
    final byParent = <int, List<({int id, int parent, String detail})>>{};
    for (final r in rows) {
      byParent.putIfAbsent(r.parent, () => []).add(r);
    }
    PlanNode build(({int id, int parent, String detail}) r) {
      final words = r.detail.trim().split(RegExp(r'\s+'));
      return PlanNode(
        operation: words.first,
        relation: words.length > 1 ? words[1] : null,
        details: {'detail': r.detail},
        children: [
          for (final c in byParent[r.id] ?? const []) build(c),
        ],
      );
    }

    return PlanNode(
      operation: 'QUERY PLAN',
      children: [for (final r in byParent[0] ?? const []) build(r)],
    );
  }

  /// The node with the largest own cost, the first one among equals. Null when
  /// no node has a cost.
  static PlanNode? hottest(PlanNode root) {
    PlanNode? best;
    double bestCost = -1;
    void visit(PlanNode n) {
      final own = n.ownCost;
      if (own != null && own > bestCost) {
        best = n;
        bestCost = own;
      }
      for (final c in n.children) {
        visit(c);
      }
    }

    visit(root);
    return best;
  }

  static Map<String, Object?> _asMap(Object? v) =>
      v is Map ? v.map((k, val) => MapEntry('$k', val)) : const {};

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
