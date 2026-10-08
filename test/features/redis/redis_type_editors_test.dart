import 'dart:typed_data';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/features/redis/editors/redis_hash_editor.dart';
import 'package:querya_desktop/features/redis/editors/redis_list_editor.dart';
import 'package:querya_desktop/features/redis/editors/redis_set_editor.dart';
import 'package:querya_desktop/features/redis/editors/redis_string_editor.dart';
import 'package:querya_desktop/features/redis/editors/redis_zset_editor.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../../support/querya_theme_test_shell.dart';

RedisBulkValue _v(String s) => RedisBulkValue.utf8(s);

final _binary = RedisBulkValue.fromReply(Uint8List.fromList([0xff, 0xfe, 0x01]));

Future<void> _pump(
  WidgetTester tester,
  material.Widget Function(shadcn.ColorScheme cs) editor,
) async {
  await tester.pumpWidget(
    queryaThemeTestShell(
      child: material.Scaffold(
        body: material.SizedBox(
          width: 800,
          height: 600,
          child: material.Builder(
            builder: (context) =>
                editor(shadcn.Theme.of(context).colorScheme),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String placeholder) => find.byWidgetPredicate(
      (w) => w is shadcn.TextField && w.placeholder is shadcn.Text &&
          (w.placeholder! as shadcn.Text).data == placeholder,
    );

void main() {
  group('RedisStringEditor', () {
    testWidgets('shows the value and saves on demand', (tester) async {
      final controller = material.TextEditingController(text: 'hello');
      addTearDown(controller.dispose);
      var saved = 0;

      await _pump(
        tester,
        (cs) => RedisStringEditor(
          value: _v('hello'),
          controller: controller,
          isReadOnly: false,
          onSave: () => saved++,
          colorScheme: cs,
        ),
      );

      expect(find.text('Value'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      await tester.tap(find.text('Save'));
      expect(saved, 1);
    });

    testWidgets('typing updates the controller owned by the parent',
        (tester) async {
      final controller = material.TextEditingController(text: 'a');
      addTearDown(controller.dispose);

      await _pump(
        tester,
        (cs) => RedisStringEditor(
          value: _v('a'),
          controller: controller,
          isReadOnly: false,
          onSave: () {},
          colorScheme: cs,
        ),
      );
      await tester.enterText(find.byType(material.TextField), 'changed');

      expect(controller.text, 'changed');
    });

    testWidgets('read-only hides Save and locks the field', (tester) async {
      final controller = material.TextEditingController(text: 'hello');
      addTearDown(controller.dispose);

      await _pump(
        tester,
        (cs) => RedisStringEditor(
          value: _v('hello'),
          controller: controller,
          isReadOnly: true,
          onSave: () {},
          colorScheme: cs,
        ),
      );

      expect(find.text('Save'), findsNothing);
      expect(
        tester.widget<material.TextField>(find.byType(material.TextField)).readOnly,
        isTrue,
      );
    });

    testWidgets('a binary value is shown as hex and base64 without Save',
        (tester) async {
      final controller = material.TextEditingController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        (cs) => RedisStringEditor(
          value: _binary,
          controller: controller,
          isReadOnly: false,
          onSave: () {},
          colorScheme: cs,
        ),
      );

      expect(find.text('Binary value (3 bytes)'), findsOneWidget);
      expect(find.text(_binary.toHex()), findsOneWidget);
      expect(find.text(_binary.toBase64()), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      expect(find.byType(material.TextField), findsNothing);
    });
  });

  group('RedisHashEditor', () {
    final entries = [
      MapEntry(_v('name'), _v('Ada')),
      MapEntry(_v('role'), _v('admin')),
    ];

    Future<void> pumpHash(
      WidgetTester tester, {
      bool readOnly = false,
      List<MapEntry<RedisBulkValue, RedisBulkValue>>? rows,
      void Function(String, String)? onSet,
      void Function(RedisBulkValue)? onDelete,
      material.Widget? footer,
    }) =>
        _pump(
          tester,
          (cs) => RedisHashEditor(
            heading: 'Hash fields (2 / 2)',
            entries: rows ?? entries,
            isReadOnly: readOnly,
            onSet: onSet ?? (_, __) {},
            onDelete: onDelete ?? (_) {},
            colorScheme: cs,
            shadcnCs: cs,
            footer: footer,
          ),
        );

    testWidgets('lists fields with their values and the heading',
        (tester) async {
      await pumpHash(tester);

      expect(find.text('Hash fields (2 / 2)'), findsOneWidget);
      expect(find.text('name'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('role'), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);
    });

    testWidgets('HSET trims the field, keeps the value, and clears the inputs',
        (tester) async {
      String? field;
      String? value;
      await pumpHash(tester, onSet: (f, v) {
        field = f;
        value = v;
      });

      await tester.enterText(_field('Field'), '  city ');
      await tester.enterText(_field('Value'), ' Paris ');
      await tester.tap(find.text('HSET'));
      await tester.pump();

      expect(field, 'city');
      expect(value, ' Paris ');
      expect(find.text('city'), findsNothing, reason: 'input cleared');
    });

    testWidgets('HSET ignores an empty field name', (tester) async {
      var calls = 0;
      await pumpHash(tester, onSet: (_, __) => calls++);

      await tester.enterText(_field('Value'), 'orphan');
      await tester.tap(find.text('HSET'));
      await tester.pump();

      expect(calls, 0);
    });

    testWidgets('the delete icon reports the field to remove', (tester) async {
      RedisBulkValue? deleted;
      await pumpHash(tester, onDelete: (f) => deleted = f);

      await tester.tap(find.byIcon(material.Icons.close_rounded).last);

      expect(deleted, _v('role'));
    });

    testWidgets('read-only hides the add bar and the delete icons',
        (tester) async {
      await pumpHash(tester, readOnly: true);

      expect(find.text('HSET'), findsNothing);
      expect(find.byIcon(material.Icons.close_rounded), findsNothing);
      expect(find.text('Ada'), findsOneWidget);
    });

    testWidgets('an empty hash says so, and a footer is shown', (tester) async {
      await pumpHash(
        tester,
        rows: const [],
        footer: const material.Text('Load more'),
      );

      expect(find.text('No fields'), findsOneWidget);
      expect(find.text('Load more'), findsOneWidget);
    });
  });

  group('RedisListEditor', () {
    final items = [_v('first'), _v('second')];

    Future<void> pumpList(
      WidgetTester tester, {
      bool readOnly = false,
      List<RedisBulkValue>? rows,
      void Function(String)? onPush,
      Future<void> Function(int, String, {RedisBulkValue? expectedCurrent})?
          onSet,
      void Function(int, RedisBulkValue)? onRemove,
    }) =>
        _pump(
          tester,
          (cs) => RedisListEditor(
            heading: 'List items (2 / 2)',
            items: rows ?? items,
            isReadOnly: readOnly,
            onPush: onPush ?? (_) {},
            onSet: onSet ?? (_, __, {expectedCurrent}) async {},
            onRemove: onRemove ?? (_, __) {},
            colorScheme: cs,
            shadcnCs: cs,
          ),
        );

    testWidgets('lists the items with their indexes', (tester) async {
      await pumpList(tester);

      expect(find.text('List items (2 / 2)'), findsOneWidget);
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('RPUSH sends the text as typed and clears the input',
        (tester) async {
      String? pushed;
      await pumpList(tester, onPush: (v) => pushed = v);

      await tester.enterText(_field('New item'), ' third ');
      await tester.tap(find.text('RPUSH'));
      await tester.pump();

      expect(pushed, ' third ');
      expect(find.text(' third '), findsNothing);
    });

    testWidgets('RPUSH ignores empty input', (tester) async {
      var calls = 0;
      await pumpList(tester, onPush: (_) => calls++);

      await tester.tap(find.text('RPUSH'));
      await tester.pump();

      expect(calls, 0);
    });

    testWidgets('editing an item sends LSET with the value it expects',
        (tester) async {
      int? index;
      String? value;
      RedisBulkValue? expected;
      await pumpList(tester, onSet: (i, v, {expectedCurrent}) async {
        index = i;
        value = v;
        expected = expectedCurrent;
      });

      await tester.tap(find.byIcon(material.Icons.edit_outlined).last);
      await tester.pumpAndSettle();
      expect(find.text('Edit Item [1]'), findsOneWidget);

      await tester.enterText(find.byType(shadcn.TextField).last, 'changed');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(index, 1);
      expect(value, 'changed');
      expect(expected, _v('second'));
    });

    testWidgets('cancelling or not changing the text sends nothing',
        (tester) async {
      var calls = 0;
      await pumpList(tester, onSet: (_, __, {expectedCurrent}) async => calls++);

      await tester.tap(find.byIcon(material.Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(material.Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(calls, 0);
    });

    testWidgets('the delete icon reports index and item', (tester) async {
      int? index;
      RedisBulkValue? item;
      await pumpList(tester, onRemove: (i, v) {
        index = i;
        item = v;
      });

      await tester.tap(find.byIcon(material.Icons.close_rounded).first);

      expect(index, 0);
      expect(item, _v('first'));
    });

    testWidgets('a binary item has a badge and cannot be edited',
        (tester) async {
      await pumpList(tester, rows: [_v('text'), _binary]);

      expect(find.text('binary'), findsOneWidget);
      expect(find.byIcon(material.Icons.edit_outlined), findsOneWidget,
          reason: 'only the text item is editable');
      expect(find.byIcon(material.Icons.close_rounded), findsNWidgets(2));
    });

    testWidgets('read-only hides the add bar, edit and delete', (tester) async {
      await pumpList(tester, readOnly: true);

      expect(find.text('RPUSH'), findsNothing);
      expect(find.byIcon(material.Icons.edit_outlined), findsNothing);
      expect(find.byIcon(material.Icons.close_rounded), findsNothing);
    });

    testWidgets('an empty list says so', (tester) async {
      await pumpList(tester, rows: const []);

      expect(find.text('No items'), findsOneWidget);
    });
  });

  group('RedisSetEditor', () {
    Future<void> pumpSet(
      WidgetTester tester, {
      bool readOnly = false,
      List<RedisBulkValue>? rows,
      void Function(String)? onAdd,
      void Function(RedisBulkValue)? onRemove,
    }) =>
        _pump(
          tester,
          (cs) => RedisSetEditor(
            heading: 'Set members (2 / 2)',
            members: rows ?? [_v('a'), _v('b')],
            isReadOnly: readOnly,
            onAdd: onAdd ?? (_) {},
            onRemove: onRemove ?? (_) {},
            colorScheme: cs,
            shadcnCs: cs,
          ),
        );

    testWidgets('lists members', (tester) async {
      await pumpSet(tester);

      expect(find.text('Set members (2 / 2)'), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('SADD trims the member and clears the input', (tester) async {
      String? added;
      await pumpSet(tester, onAdd: (m) => added = m);

      await tester.enterText(_field('New member'), '  c  ');
      await tester.tap(find.text('SADD'));
      await tester.pump();

      expect(added, 'c');
    });

    testWidgets('SADD ignores blank input', (tester) async {
      var calls = 0;
      await pumpSet(tester, onAdd: (_) => calls++);

      await tester.enterText(_field('New member'), '   ');
      await tester.tap(find.text('SADD'));
      await tester.pump();

      expect(calls, 0);
    });

    testWidgets('the delete icon reports the member', (tester) async {
      RedisBulkValue? removed;
      await pumpSet(tester, onRemove: (m) => removed = m);

      await tester.tap(find.byIcon(material.Icons.close_rounded).first);

      expect(removed, _v('a'));
    });

    testWidgets('read-only and empty states', (tester) async {
      await pumpSet(tester, readOnly: true, rows: const []);

      expect(find.text('SADD'), findsNothing);
      expect(find.text('No members'), findsOneWidget);
    });
  });

  group('RedisZsetEditor', () {
    Future<void> pumpZset(
      WidgetTester tester, {
      bool readOnly = false,
      List<(RedisBulkValue, double)>? rows,
      void Function(String, double)? onAdd,
      void Function(RedisBulkValue)? onRemove,
    }) =>
        _pump(
          tester,
          (cs) => RedisZsetEditor(
            heading: 'Sorted set (2 / 2)',
            members: rows ?? [(_v('low'), 1), (_v('high'), 2.5)],
            isReadOnly: readOnly,
            onAdd: onAdd ?? (_, __) {},
            onRemove: onRemove ?? (_) {},
            colorScheme: cs,
            shadcnCs: cs,
          ),
        );

    testWidgets('lists members with scores, whole scores without decimals',
        (tester) async {
      await pumpZset(tester);

      expect(find.text('low'), findsOneWidget);
      expect(find.text('high'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2.50'), findsOneWidget);
    });

    testWidgets('ZADD parses the score and trims the member', (tester) async {
      String? member;
      double? score;
      await pumpZset(tester, onAdd: (m, s) {
        member = m;
        score = s;
      });

      await tester.enterText(_field('Member'), ' mid ');
      await tester.enterText(_field('Score'), ' 1.5 ');
      await tester.tap(find.text('ZADD'));
      await tester.pump();

      expect(member, 'mid');
      expect(score, 1.5);
    });

    testWidgets('ZADD ignores an empty member or a score that is not a number',
        (tester) async {
      var calls = 0;
      await pumpZset(tester, onAdd: (_, __) => calls++);

      await tester.enterText(_field('Member'), 'x');
      await tester.enterText(_field('Score'), 'abc');
      await tester.tap(find.text('ZADD'));
      await tester.pump();

      await tester.enterText(_field('Member'), '');
      await tester.enterText(_field('Score'), '3');
      await tester.tap(find.text('ZADD'));
      await tester.pump();

      expect(calls, 0);
    });

    testWidgets('the delete icon reports the member', (tester) async {
      RedisBulkValue? removed;
      await pumpZset(tester, onRemove: (m) => removed = m);

      await tester.tap(find.byIcon(material.Icons.close_rounded).last);

      expect(removed, _v('high'));
    });

    testWidgets('read-only hides the add bar and delete icons', (tester) async {
      await pumpZset(tester, readOnly: true);

      expect(find.text('ZADD'), findsNothing);
      expect(find.byIcon(material.Icons.close_rounded), findsNothing);
    });
  });
}
