import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_animated_expand.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';

void main() {
  testWidgets('QueryaAnimatedExpand hides child when collapsed',
      (tester) async {
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

  testWidgets('uses treeExpand duration/curve tokens on Full motion',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: QueryaMotionScope(
          level: QueryaMotionLevel.full,
          child: _ExpandHost(expanded: true),
        ),
      ),
    );

    final size = tester.widget<AnimatedSize>(find.byType(AnimatedSize));
    expect(size.duration, QueryaMotion.treeExpand);
    expect(size.curve, QueryaMotion.treeExpandCurve);
  });

  testWidgets('Motion Off skips AnimatedSize entirely', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: QueryaMotionScope(
          level: QueryaMotionLevel.off,
          child: _ExpandHost(expanded: true),
        ),
      ),
    );

    expect(find.byType(AnimatedSize), findsNothing);
    expect(find.text('child'), findsOneWidget);
  });

  testWidgets('large estimatedChildCount skips AnimatedSize on Full motion',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: QueryaMotionScope(
          level: QueryaMotionLevel.full,
          child: _ExpandHost(
            expanded: true,
            estimatedChildCount:
                QueryaAnimatedExpand.defaultSkipSizeAnimationAbove + 1,
          ),
        ),
      ),
    );

    expect(find.byType(AnimatedSize), findsNothing);
    expect(find.text('child'), findsOneWidget);
  });

  testWidgets('small estimatedChildCount still uses AnimatedSize',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: QueryaMotionScope(
          level: QueryaMotionLevel.full,
          child: _ExpandHost(expanded: true, estimatedChildCount: 8),
        ),
      ),
    );

    expect(find.byType(AnimatedSize), findsOneWidget);
  });
}

class _ExpandHost extends StatelessWidget {
  const _ExpandHost({
    required this.expanded,
    this.estimatedChildCount,
  });

  final bool expanded;
  final int? estimatedChildCount;

  @override
  Widget build(BuildContext context) {
    return QueryaAnimatedExpand(
      expanded: expanded,
      estimatedChildCount: estimatedChildCount,
      child: const Text('child'),
    );
  }
}
