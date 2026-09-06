import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

material.Widget _testShell({required material.Widget child}) {
  final td = QueryaTheme.darkDefault
      .toShadcnThemeData()
      .copyWith(platform: () => TargetPlatform.linux);
  return ShadcnApp(
    theme: td,
    home: material.Scaffold(
      body: child,
    ),
  );
}

Future<void> _secondaryClick(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var clipboardContent = '';
  setUp(() {
    clipboardContent = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          clipboardContent = (methodCall.arguments as Map)['text'] as String;
          return null;
        }
        if (methodCall.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': clipboardContent};
        }
        return null;
      },
    );
  });

  group('ResultGridSelection Export Formats', () {
    const columns = ['id', 'name', 'score', 'active', 'note'];
    final rows = [
      ['1', 'Alice', '95.5', 'true', 'NULL'],
      ['2', 'Bob, Jr.', '80', 'false', 'Needs review'],
    ];

    test('toTsv with and without headers', () {
      const sel = ResultGridSelection(
        startRow: 0,
        startColumn: 0,
        endRow: 1,
        endColumn: 2,
      );

      expect(
        sel.toTsv(rows),
        equals('1\tAlice\t95.5\n2\tBob, Jr.\t80'),
      );

      expect(
        sel.toTsv(rows, columns: columns),
        equals('id\tname\tscore\n1\tAlice\t95.5\n2\tBob, Jr.\t80'),
      );
    });

    test('toCsv with headers and escaping', () {
      const sel = ResultGridSelection(
        startRow: 0,
        startColumn: 0,
        endRow: 1,
        endColumn: 2,
      );

      expect(
        sel.toCsv(rows),
        equals('1,Alice,95.5\n2,"Bob, Jr.",80'),
      );

      expect(
        sel.toCsv(rows, columns: columns),
        equals('id,name,score\n1,Alice,95.5\n2,"Bob, Jr.",80'),
      );
    });

    test('toJson encodes typed JSON object for single row', () {
      const sel = ResultGridSelection(
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 4,
      );

      final jsonStr = sel.toJson(columns, rows);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['id'], equals(1));
      expect(decoded['name'], equals('Alice'));
      expect(decoded['score'], equals(95.5));
      expect(decoded['active'], isTrue);
      expect(decoded['note'], isNull);
    });

    test('toJson encodes typed JSON array for multiple rows', () {
      const sel = ResultGridSelection(
        startRow: 0,
        startColumn: 0,
        endRow: 1,
        endColumn: 2,
      );

      final jsonStr = sel.toJson(columns, rows);
      final decoded = jsonDecode(jsonStr) as List<dynamic>;

      expect(decoded.length, equals(2));
      expect(decoded[0]['id'], equals(1));
      expect(decoded[0]['name'], equals('Alice'));
      expect(decoded[1]['id'], equals(2));
      expect(decoded[1]['name'], equals('Bob, Jr.'));
      expect(decoded[1]['score'], equals(80));
    });

    test('toTsv escapes cells with tabs, newlines, and quotes', () {
      final rowsWithSpecialChars = [
        ['1', 'Line1\nLine2', 'Tab\there', 'Quoted "value"'],
      ];
      const sel = ResultGridSelection(
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 3,
      );

      final tsv = sel.toTsv(rowsWithSpecialChars);
      expect(
        tsv,
        equals('1\t"Line1\nLine2"\t"Tab\there"\t"Quoted ""value"""'),
      );
    });

    test('toJson preserves strings with leading zeros', () {
      final rowsWithLeadingZeros = [
        ['007', '01234', '0', '42'],
      ];
      const cols = ['agent_id', 'zip', 'zero_num', 'plain_num'];
      const sel = ResultGridSelection(
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 3,
      );

      final jsonStr = sel.toJson(cols, rowsWithLeadingZeros);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['agent_id'], equals('007'));
      expect(decoded['zip'], equals('01234'));
      expect(decoded['zero_num'], equals(0));
      expect(decoded['plain_num'], equals(42));
    });
  });

  group('VirtualResultGrid Non-Destructive Secondary Click', () {
    testWidgets('right-click does NOT wipe the OS clipboard', (tester) async {
      await Clipboard.setData(const ClipboardData(text: 'precious-clipboard-data'));

      await tester.pumpWidget(
        _testShell(
          child: const material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: ['id', 'username', 'role'],
              rows: [
                ['1', 'alice', 'admin'],
                ['2', 'bob', 'user'],
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Right-click on cell 'alice'
      final aliceCell = find.text('alice');
      expect(aliceCell, findsOneWidget);

      await _secondaryClick(tester, aliceCell);

      // Clipboard MUST be unchanged!
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboardData?.text, equals('precious-clipboard-data'));
    });

    testWidgets('right-click selects unselected cell and opens context menu', (tester) async {
      List<String>? selectedValues;

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'username', 'role'],
              rows: const [
                ['1', 'alice', 'admin'],
                ['2', 'bob', 'user'],
              ],
              onSelectionValuesChanged: (vals) => selectedValues = vals,
            ),
          ),
        ),
      );
      await tester.pump();

      // Right-click on 'bob'
      await _secondaryClick(tester, find.text('bob'));

      expect(selectedValues, equals(['bob']));

      // Context menu buttons should be visible
      expect(find.text('Copy Value'), findsOneWidget);
      expect(find.text('Copy with Headers'), findsOneWidget);
      expect(find.text('Copy as JSON'), findsOneWidget);
      expect(find.text('Copy as CSV'), findsOneWidget);
      expect(find.text('Inspect Cell Value…'), findsOneWidget);
    });

    testWidgets('tapping Copy Value copies cell text to clipboard', (tester) async {
      await tester.pumpWidget(
        _testShell(
          child: const material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: ['id', 'username', 'role'],
              rows: [
                ['1', 'alice', 'admin'],
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      await _secondaryClick(tester, find.text('alice'));

      await tester.tap(find.text('Copy Value'));
      await tester.pump(const Duration(milliseconds: 300));

      final data = await Clipboard.getData(Clipboard.kTextPlain);
      expect(data?.text, equals('alice'));
    });

    testWidgets('tapping Copy with Headers copies header and cell text', (tester) async {
      await tester.pumpWidget(
        _testShell(
          child: const material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: ['id', 'username', 'role'],
              rows: [
                ['1', 'alice', 'admin'],
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      await _secondaryClick(tester, find.text('alice'));

      await tester.tap(find.text('Copy with Headers'));
      await tester.pump(const Duration(milliseconds: 300));

      final data = await Clipboard.getData(Clipboard.kTextPlain);
      expect(data?.text, equals('username\nalice'));
    });

    testWidgets('tapping Copy as JSON copies formatted JSON', (tester) async {
      await tester.pumpWidget(
        _testShell(
          child: const material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: ['id', 'username', 'role'],
              rows: [
                ['1', 'alice', 'admin'],
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      await _secondaryClick(tester, find.text('alice'));

      await tester.tap(find.text('Copy as JSON'));
      await tester.pump(const Duration(milliseconds: 300));

      final data = await Clipboard.getData(Clipboard.kTextPlain);
      expect(data?.text, isNotNull);
      final decoded = jsonDecode(data!.text!) as Map<String, dynamic>;
      expect(decoded['username'], equals('alice'));
    });

    testWidgets('Filter by Value emits SQL-like filter predicate', (tester) async {
      String? filterRequested;

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'status'],
              rows: const [
                ['1', 'ACTIVE'],
              ],
              onFilterRequested: (expr) => filterRequested = expr,
            ),
          ),
        ),
      );
      await tester.pump();

      await _secondaryClick(tester, find.text('ACTIVE'));

      expect(find.text('Filter by Value (status = ACTIVE)'), findsOneWidget);
      await tester.tap(find.text('Filter by Value (status = ACTIVE)'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(filterRequested, equals("status = 'ACTIVE'"));
    });

    testWidgets('Filter Out emits inverted SQL-like filter predicate', (tester) async {
      String? filterRequested;

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'status'],
              rows: const [
                ['1', 'ACTIVE'],
              ],
              onFilterRequested: (expr) => filterRequested = expr,
            ),
          ),
        ),
      );
      await tester.pump();

      await _secondaryClick(tester, find.text('ACTIVE'));

      expect(find.text('Filter Out (status != ACTIVE)'), findsOneWidget);
      await tester.tap(find.text('Filter Out (status != ACTIVE)'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(filterRequested, equals("status != 'ACTIVE'"));
    });

    testWidgets('Set NULL and Duplicate Row update StagingBuffer from context menu', (tester) async {
      final buffer = DataGridStagingBuffer(
        columns: const ['id', 'username'],
        rows: const [
          ['1', 'alice'],
        ],
      );

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'username'],
              rows: const [
                ['1', 'alice'],
              ],
              stagingBuffer: buffer,
            ),
          ),
        ),
      );
      await tester.pump();

      // Right-click on alice and select Set NULL
      await _secondaryClick(tester, find.text('alice'));

      expect(find.text('Set NULL'), findsOneWidget);
      await tester.tap(find.text('Set NULL'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(buffer.isCellNull(0, 1), isTrue);

      // Right-click on cell and Duplicate Row
      await _secondaryClick(tester, find.text('1'));

      expect(find.text('Duplicate Row'), findsOneWidget);
      await tester.tap(find.text('Duplicate Row'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(buffer.insertedRowCount, equals(1));
      expect(buffer.getCellValue(1, 0), equals('1'));
    });
  });
}
