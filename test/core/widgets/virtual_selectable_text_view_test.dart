import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/widgets/virtual_selectable_text_view.dart';

void main() {
  group('VirtualSelectableTextView', () {
    testWidgets('renders SingleChildScrollView + SelectableText below threshold', (tester) async {
      const text = 'line 1\nline 2\nline 3';
      await tester.pumpWidget(
        const material.MaterialApp(
          home: material.Scaffold(
            body: VirtualSelectableTextView(
              text: text,
              threshold: 10,
            ),
          ),
        ),
      );

      expect(find.byType(material.SingleChildScrollView), findsOneWidget);
      expect(find.byType(material.ListView), findsNothing);
      expect(find.text(text), findsOneWidget);
    });

    testWidgets('renders ListView.builder above threshold', (tester) async {
      final text = List.generate(50, (i) => 'Virtual Line $i').join('\n');
      await tester.pumpWidget(
        material.MaterialApp(
          home: material.Scaffold(
            body: VirtualSelectableTextView(
              text: text,
              threshold: 10,
            ),
          ),
        ),
      );

      expect(find.byType(material.SingleChildScrollView), findsNothing);
      expect(find.byType(material.ListView), findsOneWidget);
      expect(find.text('Virtual Line 0'), findsOneWidget);
      expect(find.text('Virtual Line 1'), findsOneWidget);
    });

    testWidgets('a new text re-splits the lines (#1532)', (tester) async {
      final large = List.generate(50, (i) => 'Virtual Line $i').join('\n');
      var text = 'a\nb';
      late void Function(void Function()) rebuild;

      await tester.pumpWidget(
        material.MaterialApp(
          home: material.Scaffold(
            body: material.StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return VirtualSelectableTextView(text: text, threshold: 10);
              },
            ),
          ),
        ),
      );
      expect(find.byType(material.ListView), findsNothing);

      rebuild(() => text = large);
      await tester.pump();
      expect(find.byType(material.ListView), findsOneWidget);
      expect(find.text('Virtual Line 0'), findsOneWidget);

      rebuild(() => text = 'only\none');
      await tester.pump();
      expect(find.byType(material.ListView), findsNothing);
      expect(find.text('only\none'), findsOneWidget);
    });

    testWidgets('a rebuild with the same text keeps the same lines (#1532)',
        (tester) async {
      final text = List.generate(50, (i) => 'Virtual Line $i').join('\n');
      var style = const material.TextStyle(fontSize: 12);
      late void Function(void Function()) rebuild;

      await tester.pumpWidget(
        material.MaterialApp(
          home: material.Scaffold(
            body: material.StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return VirtualSelectableTextView(
                  text: text,
                  style: style,
                  threshold: 10,
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('Virtual Line 0'), findsOneWidget);

      rebuild(() => style = const material.TextStyle(fontSize: 14));
      await tester.pump();
      expect(find.byType(material.ListView), findsOneWidget);
      expect(find.text('Virtual Line 0'), findsOneWidget);
    });
  });
}
