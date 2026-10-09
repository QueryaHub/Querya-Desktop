import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/query_plan.dart';

/// PostgreSQL plan of a join of orders, customers and items.
const _pgPlan = '''
[{"Plan": {
  "Node Type": "Hash Join", "Plan Rows": 100, "Actual Rows": 120, "Total Cost": 500.0,
  "Plans": [
    {"Node Type": "Seq Scan", "Relation Name": "orders", "Plan Rows": 1000, "Actual Rows": 1000, "Total Cost": 300.0},
    {"Node Type": "Hash", "Plan Rows": 50, "Total Cost": 120.0,
     "Plans": [
       {"Node Type": "Index Scan", "Relation Name": "customers", "Index Name": "customers_pkey", "Plan Rows": 50, "Total Cost": 100.0}
     ]}
  ]
}}]''';

void main() {
  group('PostgreSQL plan', () {
    test('a join renders as a tree with the right parents and children', () {
      final root = QueryPlanParser.fromPostgresJson(_pgPlan)!;
      expect(root.operation, 'Hash Join');
      expect(root.children.map((c) => c.operation), ['Seq Scan', 'Hash']);
      final hash = root.children[1];
      expect(hash.children.single.operation, 'Index Scan');
      expect(hash.children.single.relation, 'customers');
      expect(root.children.first.relation, 'orders');
    });

    test('rows and cost come through; the own cost subtracts children', () {
      final root = QueryPlanParser.fromPostgresJson(_pgPlan)!;
      expect(root.estimatedRows, 100);
      expect(root.actualRows, 120);
      expect(root.cost, 500);
      expect(root.ownCost, 500 - 300 - 120);
      expect(root.children[1].ownCost, 120 - 100);
    });

    test('the most expensive node is the scan with the largest own cost', () {
      final root = QueryPlanParser.fromPostgresJson(_pgPlan)!;
      expect(QueryPlanParser.hottest(root)!.operation, 'Seq Scan');
    });

    test('a value that is not a plan gives no tree', () {
      expect(QueryPlanParser.fromPostgresJson('not json'), isNull);
      expect(QueryPlanParser.fromPostgresJson('[]'), isNull);
    });
  });

  group('MySQL plan', () {
    test('tables of a nested loop become children of the query block', () {
      const plan = '''
{"query_block": {"select_id": 1, "cost_info": {"query_cost": "42.00"},
  "nested_loop": [
    {"table": {"table_name": "orders", "access_type": "ALL",
      "rows_examined_per_scan": 1000, "cost_info": {"prefix_cost": "30.00"}}},
    {"table": {"table_name": "customers", "access_type": "eq_ref",
      "rows_examined_per_scan": 1, "cost_info": {"prefix_cost": "42.00"}}}
  ]}}''';
      final root = QueryPlanParser.fromMysqlJson(plan)!;
      expect(root.cost, 42);
      expect(root.children.map((c) => c.relation), ['orders', 'customers']);
      expect(root.children.first.operation, 'ALL');
      expect(QueryPlanParser.hottest(root)!.relation, 'orders');
    });
  });

  group('SQLite plan', () {
    test('rows hang below their parent; a row with no parent is top level', () {
      final root = QueryPlanParser.fromSqliteRows([
        (id: 2, parent: 0, detail: 'SCAN orders'),
        (id: 3, parent: 2, detail: 'SEARCH customers USING INTEGER PRIMARY KEY (rowid=?)'),
        (id: 4, parent: 0, detail: 'USE TEMP B-TREE FOR ORDER BY'),
      ])!;
      expect(root.operation, 'QUERY PLAN');
      expect(root.children.map((c) => c.operation), ['SCAN', 'USE']);
      expect(root.children.first.relation, 'orders');
      expect(root.children.first.children.single.operation, 'SEARCH');
      expect(root.children.first.children.single.relation, 'customers');
    });

    test('SQLite reports no cost, so no node is the most expensive', () {
      final root = QueryPlanParser.fromSqliteRows([
        (id: 2, parent: 0, detail: 'SCAN orders'),
      ])!;
      expect(QueryPlanParser.hottest(root), isNull);
    });

    test('no rows, no tree', () {
      expect(QueryPlanParser.fromSqliteRows(const []), isNull);
    });
  });
}
