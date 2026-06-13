import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';

void main() {
  testWidgets('lazyConnectionTreeList uses ListView for large lists', (tester) async {
    await tester.pumpWidget(
      material.MaterialApp(
        home: material.Scaffold(
          body: material.Builder(
            builder: (context) => lazyConnectionTreeList(
              context: context,
              itemCount: 50,
              itemExtent: kConnectionTreeRowExtent,
              itemBuilder: (context, index) => material.SizedBox(
                height: kConnectionTreeRowExtent,
                child: material.Text('item $index'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(material.ListView), findsOneWidget);
  });

  testWidgets('lazyConnectionTreeList uses Column for small lists', (tester) async {
    await tester.pumpWidget(
      material.MaterialApp(
        home: material.Scaffold(
          body: material.Builder(
            builder: (context) => lazyConnectionTreeList(
              context: context,
              itemCount: 5,
              itemBuilder: (context, index) => material.Text('item $index'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(material.ListView), findsNothing);
    expect(find.text('item 0'), findsOneWidget);
    expect(find.text('item 4'), findsOneWidget);
  });
}
