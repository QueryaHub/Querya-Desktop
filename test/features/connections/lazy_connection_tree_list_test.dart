import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';

void main() {
  testWidgets(
      'lazyConnectionTreeList virtualizes fixed-extent leaves without shrinkWrap',
      (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      material.MaterialApp(
        home: material.Scaffold(
          body: material.Builder(
            builder: (context) => lazyConnectionTreeList(
              context: context,
              itemCount: 50,
              itemExtent: kConnectionTreeRowExtent,
              itemBuilder: (context, index) {
                builds++;
                return material.SizedBox(
                  height: kConnectionTreeRowExtent,
                  child: material.Text('item $index'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<material.ListView>(
      find.byType(material.ListView),
    );
    expect(list.shrinkWrap, isFalse);
    expect(builds, lessThan(50));
    expect(builds, lessThanOrEqualTo(kConnectionTreeMaxVisibleRows + 8));
  });

  testWidgets(
      'lazyConnectionTreeList uses Column for expandable children (no itemExtent)',
      (tester) async {
    await tester.pumpWidget(
      material.MaterialApp(
        home: material.Scaffold(
          body: material.SingleChildScrollView(
            child: material.Builder(
              builder: (context) => lazyConnectionTreeList(
                context: context,
                itemCount: 50,
                itemBuilder: (context, index) => material.Text('item $index'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(material.ListView), findsNothing);
    expect(find.text('item 0'), findsOneWidget);
    expect(find.text('item 49'), findsOneWidget);
  });

  testWidgets('lazyConnectionTreeList uses Column for small leaf lists',
      (tester) async {
    await tester.pumpWidget(
      material.MaterialApp(
        home: material.Scaffold(
          body: material.Builder(
            builder: (context) => lazyConnectionTreeList(
              context: context,
              itemCount: 5,
              itemExtent: kConnectionTreeRowExtent,
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
