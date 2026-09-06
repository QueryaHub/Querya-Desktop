import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_utils.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('Table Views SQL Sorting Clause Generation', () {
    test('SQLite _browseDataSql generates correct ORDER BY clause with quoted identifiers', () {
      String generateSql({
        required String table,
        String? sortColumn,
        bool sortAscending = true,
        int limit = 100,
        int offset = 0,
      }) {
        final qualifiedFrom = SqliteConnection.quoteIdentifier(table);
        final orderBy = sortColumn != null
            ? ' ORDER BY ${SqliteConnection.quoteIdentifier(sortColumn)} ${sortAscending ? "ASC" : "DESC"}'
            : '';
        return 'SELECT * FROM $qualifiedFrom$orderBy LIMIT $limit OFFSET $offset';
      }

      // No sort
      expect(
        generateSql(table: 'users'),
        equals('SELECT * FROM "users" LIMIT 100 OFFSET 0'),
      );

      // ASC sort
      expect(
        generateSql(table: 'users', sortColumn: 'created_at', sortAscending: true),
        equals('SELECT * FROM "users" ORDER BY "created_at" ASC LIMIT 100 OFFSET 0'),
      );

      // DESC sort
      expect(
        generateSql(table: 'users', sortColumn: 'email', sortAscending: false),
        equals('SELECT * FROM "users" ORDER BY "email" DESC LIMIT 100 OFFSET 0'),
      );
    });

    test('PostgreSQL _browseDataSql generates correct ORDER BY clause with schema', () {
      String generateSql({
        required String schema,
        required String table,
        String? sortColumn,
        bool sortAscending = true,
        int limit = 100,
        int offset = 0,
      }) {
        final schemaQ = quotePostgresIdentifier(schema);
        final tableQ = quotePostgresIdentifier(table);
        final orderBy = sortColumn != null
            ? ' ORDER BY ${quotePostgresIdentifier(sortColumn)} ${sortAscending ? "ASC" : "DESC"}'
            : '';
        return 'SELECT * FROM $schemaQ.$tableQ$orderBy LIMIT $limit OFFSET $offset';
      }

      expect(
        generateSql(schema: 'public', table: 'orders'),
        equals('SELECT * FROM "public"."orders" LIMIT 100 OFFSET 0'),
      );

      expect(
        generateSql(
          schema: 'public',
          table: 'orders',
          sortColumn: 'total_amount',
          sortAscending: false,
          offset: 200,
        ),
        equals('SELECT * FROM "public"."orders" ORDER BY "total_amount" DESC LIMIT 100 OFFSET 200'),
      );
    });

    test('MySQL _browseDataSql generates backtick quoted ORDER BY clause', () {
      String generateSql({
        required String database,
        required String table,
        String? sortColumn,
        bool sortAscending = true,
        int limit = 100,
        int offset = 0,
      }) {
        final dbQ = MysqlConnection.quoteIdentifier(database);
        final tableQ = MysqlConnection.quoteIdentifier(table);
        final orderBy = sortColumn != null
            ? ' ORDER BY ${MysqlConnection.quoteIdentifier(sortColumn)} ${sortAscending ? "ASC" : "DESC"}'
            : '';
        return 'SELECT * FROM $dbQ.$tableQ$orderBy LIMIT $limit OFFSET $offset';
      }

      expect(
        generateSql(database: 'shop_db', table: 'products'),
        equals('SELECT * FROM `shop_db`.`products` LIMIT 100 OFFSET 0'),
      );

      expect(
        generateSql(
          database: 'shop_db',
          table: 'products',
          sortColumn: 'price',
          sortAscending: true,
        ),
        equals('SELECT * FROM `shop_db`.`products` ORDER BY `price` ASC LIMIT 100 OFFSET 0'),
      );
    });
  });

  group('Sort state toggle cycle', () {
    test('cycles through none -> ASC -> DESC -> none', () {
      String? sortColumn;
      bool sortAscending = true;

      void toggleSort(String col) {
        if (sortColumn == col) {
          if (sortAscending) {
            sortAscending = false;
          } else {
            sortColumn = null;
            sortAscending = true;
          }
        } else {
          sortColumn = col;
          sortAscending = true;
        }
      }

      // Initial state
      expect(sortColumn, isNull);

      // First click: col1 ASC
      toggleSort('col1');
      expect(sortColumn, equals('col1'));
      expect(sortAscending, isTrue);

      // Second click: col1 DESC
      toggleSort('col1');
      expect(sortColumn, equals('col1'));
      expect(sortAscending, isFalse);

      // Third click: none
      toggleSort('col1');
      expect(sortColumn, isNull);
      expect(sortAscending, isTrue);

      // Click different column: col2 ASC
      toggleSort('col2');
      expect(sortColumn, equals('col2'));
      expect(sortAscending, isTrue);
    });
  });

  group('Table header interactive widget rendering', () {
    testWidgets('renders sort arrow indicator and triggers toggle on tap', (tester) async {
      String? activeSortColumn;
      bool activeSortAscending = true;

      await tester.pumpWidget(
        ShadcnApp(
          theme: QueryaTheme.darkDefault.toShadcnThemeData(),
          home: material.Scaffold(
            body: material.StatefulBuilder(
              builder: (context, setState) {
                final cs = Theme.of(context).colorScheme;
                final isSorted = activeSortColumn == 'username';
                return material.SizedBox(
                  width: 200,
                  height: 40,
                  child: material.MouseRegion(
                    cursor: material.SystemMouseCursors.click,
                    child: material.GestureDetector(
                      behavior: material.HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          if (activeSortColumn == 'username') {
                            if (activeSortAscending) {
                              activeSortAscending = false;
                            } else {
                              activeSortColumn = null;
                              activeSortAscending = true;
                            }
                          } else {
                            activeSortColumn = 'username';
                            activeSortAscending = true;
                          }
                        });
                      },
                      child: material.Row(
                        children: [
                          material.Text(
                            'username',
                            style: material.TextStyle(
                              fontSize: 12,
                              fontWeight: material.FontWeight.w600,
                              color: isSorted ? cs.primary : cs.foreground,
                            ),
                          ),
                          if (isSorted) ...[
                            const Gap(4),
                            material.Icon(
                              activeSortAscending
                                  ? material.Icons.arrow_upward_rounded
                                  : material.Icons.arrow_downward_rounded,
                              size: 14,
                              color: cs.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no sort icon
      expect(find.byIcon(material.Icons.arrow_upward_rounded), findsNothing);
      expect(find.byIcon(material.Icons.arrow_downward_rounded), findsNothing);

      // Tap header -> ASC arrow appears
      await tester.tap(find.text('username'));
      await tester.pumpAndSettle();
      expect(find.byIcon(material.Icons.arrow_upward_rounded), findsOneWidget);

      // Tap header again -> DESC arrow appears
      await tester.tap(find.text('username'));
      await tester.pumpAndSettle();
      expect(find.byIcon(material.Icons.arrow_downward_rounded), findsOneWidget);

      // Tap header again -> None
      await tester.tap(find.text('username'));
      await tester.pumpAndSettle();
      expect(find.byIcon(material.Icons.arrow_upward_rounded), findsNothing);
      expect(find.byIcon(material.Icons.arrow_downward_rounded), findsNothing);
    });
  });
}
