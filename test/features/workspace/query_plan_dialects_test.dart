import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/query_plan.dart';

/// MySQL `EXPLAIN FORMAT=JSON` of a join of orders, customers and items.
/// Prefix costs are cumulative: 30, then 70, then the query cost 120.5.
const _mysqlJoin = '''
{"query_block": {"select_id": 1, "cost_info": {"query_cost": "120.50"},
  "nested_loop": [
    {"table": {"table_name": "orders", "access_type": "ALL",
      "rows_examined_per_scan": 1000, "filtered": "100.00",
      "cost_info": {"prefix_cost": "30.00"}}},
    {"table": {"table_name": "customers", "access_type": "eq_ref",
      "rows_examined_per_scan": 1, "filtered": "100.00",
      "cost_info": {"prefix_cost": "70.00"}}},
    {"table": {"table_name": "items", "access_type": "ref",
      "key": "items_order", "rows_examined_per_scan": 3,
      "cost_info": {"prefix_cost": "120.50"}}}
  ]}}''';

void main() {
  group('MySQL plan of a three-table join (#1164)', () {
    test('each table is a child of the query block, in join order', () {
      final root = QueryPlanParser.fromMysqlJson(_mysqlJoin)!;
      expect(root.operation, 'Query block');
      expect(root.children.map((c) => c.relation),
          ['orders', 'customers', 'items']);
      expect(root.children.map((c) => c.operation), ['ALL', 'eq_ref', 'ref']);
    });

    test('each table keeps its own part of the query cost', () {
      final root = QueryPlanParser.fromMysqlJson(_mysqlJoin)!;
      expect(root.cost, 120.5);
      expect(root.children.map((c) => c.ownCost), [30, 40, 50.5]);
    });

    test('the most expensive table is highlighted', () {
      final root = QueryPlanParser.fromMysqlJson(_mysqlJoin)!;
      expect(QueryPlanParser.hottest(root)!.relation, 'items');
    });

    test('rows examined per scan come through as estimates', () {
      final root = QueryPlanParser.fromMysqlJson(_mysqlJoin)!;
      expect(root.children.map((c) => c.estimatedRows), [1000, 1, 3]);
    });

    test('a plan with no query block gives no tree', () {
      expect(QueryPlanParser.fromMysqlJson('{}'), isNull);
      expect(QueryPlanParser.fromMysqlJson('{"query_block": 1}'), isNull);
      expect(QueryPlanParser.fromMysqlJson('not json'), isNull);
    });

    test('equal costs: the first table is the most expensive', () {
      const plan = '''
{"query_block": {"cost_info": {"query_cost": "20.00"},
  "nested_loop": [
    {"table": {"table_name": "a", "access_type": "ALL",
      "cost_info": {"prefix_cost": "10.00"}}},
    {"table": {"table_name": "b", "access_type": "ALL",
      "cost_info": {"prefix_cost": "20.00"}}}
  ]}}''';
      final root = QueryPlanParser.fromMysqlJson(plan)!;
      expect(root.children.map((c) => c.ownCost), [10, 10]);
      expect(QueryPlanParser.hottest(root)!.relation, 'a');
    });
  });

  group('SQLite plan of a three-table join (#1164)', () {
    final rows = [
      (id: 2, parent: 0, detail: 'SCAN orders'),
      (id: 3, parent: 0, detail: 'SEARCH customers USING INTEGER PRIMARY KEY (rowid=?)'),
      (id: 4, parent: 0, detail: 'SEARCH items USING INDEX items_order (order_id=?)'),
    ];

    test('the three steps are children of the plan, in order', () {
      final root = QueryPlanParser.fromSqliteRows(rows)!;
      expect(root.operation, 'QUERY PLAN');
      expect(root.children.map((c) => c.operation), ['SCAN', 'SEARCH', 'SEARCH']);
      expect(root.children.map((c) => c.relation),
          ['orders', 'customers', 'items']);
    });

    test('each step keeps its full detail text', () {
      final root = QueryPlanParser.fromSqliteRows(rows)!;
      expect(root.children[2].details['detail'],
          'SEARCH items USING INDEX items_order (order_id=?)');
    });

    test('SQLite has no costs, so nothing is highlighted', () {
      final root = QueryPlanParser.fromSqliteRows(rows)!;
      expect(QueryPlanParser.hottest(root), isNull);
    });
  });
}
