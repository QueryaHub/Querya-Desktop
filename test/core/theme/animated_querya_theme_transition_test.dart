import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/animated_querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';

void main() {
  group('QueryaThemeScope.transitioning (#1358)', () {
    testWidgets('is true only while the theme animation runs', (tester) async {
      var theme = QueryaTheme.darkDefault;
      var transitioning = false;
      late StateSetter setOuterState;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setOuterState = setState;
            return Directionality(
              textDirection: TextDirection.ltr,
              child: AnimatedQueryaTheme(
                data: theme,
                duration: const Duration(milliseconds: 200),
                child: Builder(
                  builder: (context) {
                    transitioning = QueryaThemeScope.isTransitioning(context);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            );
          },
        ),
      );
      expect(transitioning, isFalse, reason: 'initial theme is settled');

      setOuterState(() => theme = QueryaTheme.lightDefault);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(transitioning, isTrue, reason: 'mid-animation');

      await tester.pumpAndSettle();
      expect(transitioning, isFalse, reason: 'animation finished');
    });

    testWidgets('a consumer is rebuilt when the transition ends',
        (tester) async {
      var theme = QueryaTheme.darkDefault;
      final seen = <bool>[];
      late StateSetter setOuterState;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setOuterState = setState;
            return Directionality(
              textDirection: TextDirection.ltr,
              child: AnimatedQueryaTheme(
                data: theme,
                duration: const Duration(milliseconds: 200),
                child: Builder(
                  builder: (context) {
                    seen.add(QueryaThemeScope.isTransitioning(context));
                    return const SizedBox.shrink();
                  },
                ),
              ),
            );
          },
        ),
      );

      setOuterState(() => theme = QueryaTheme.lightDefault);
      await tester.pumpAndSettle();

      expect(seen.last, isFalse);
      expect(seen, contains(true));
    });

    testWidgets('defaults to settled for a plain scope', (tester) async {
      var transitioning = true;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: QueryaThemeScope(
            data: QueryaTheme.darkDefault,
            child: Builder(
              builder: (context) {
                transitioning = QueryaThemeScope.isTransitioning(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(transitioning, isFalse);
    });
  });
}
