import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_animated_expand.dart';

void main() {
  testWidgets('QueryaAnimatedExpand hides child when collapsed', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: _ExpandHost(expanded: false),
      ),
    );

    expect(find.text('child'), findsNothing);
  });

  testWidgets('QueryaAnimatedExpand shows child when expanded', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: _ExpandHost(expanded: true),
      ),
    );

    expect(find.text('child'), findsOneWidget);
  });
}

class _ExpandHost extends StatelessWidget {
  const _ExpandHost({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return QueryaAnimatedExpand(
      expanded: expanded,
      child: const Text('child'),
    );
  }
}
