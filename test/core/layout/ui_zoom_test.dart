import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/layout/ui_zoom.dart';

void main() {
  group('effectiveUiScale', () {
    test('is the requested scale while the window has room for it', () {
      expect(
        effectiveUiScale(requested: 2.0, window: const Size(1800, 1200)),
        2.0,
      );
      expect(
        effectiveUiScale(requested: 0.75, window: const Size(1280, 720)),
        0.75,
      );
    });

    test('is capped so a 900x600 layout always fits', () {
      // 1280x720 holds a 900x600 layout up to 1.2x (720 / 600).
      expect(
        effectiveUiScale(requested: 2.0, window: const Size(1280, 720)),
        closeTo(1.2, 1e-9),
      );
      expect(
        effectiveUiScale(requested: 1.5, window: const Size(900, 600)),
        1.0,
      );
    });

    test('shrinks a window that is below the minimum, down to a floor', () {
      expect(
        effectiveUiScale(requested: 1.0, window: const Size(800, 500)),
        closeTo(0.8333, 1e-3),
      );
      expect(
        effectiveUiScale(requested: 1.0, window: const Size(300, 200)),
        kLowestUiZoom,
      );
    });
  });

  group('QueryaUiZoom', () {
    Widget app({
      required double scale,
      Duration duration = Duration.zero,
      required Widget child,
    }) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: QueryaUiZoom(scale: scale, duration: duration, child: child),
          ),
        );

    testWidgets('lays the child out in a smaller window and paints it larger',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Size? seen;
      const key = Key('box');

      await tester.pumpWidget(app(
        scale: 2.0,
        child: Builder(builder: (context) {
          seen = MediaQuery.sizeOf(context);
          return const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(key: key, width: 100, height: 50),
          );
        }),
      ));

      expect(seen, const Size(900, 600));
      expect(tester.getRect(find.byKey(key)), const Rect.fromLTWH(0, 0, 200, 100));
    });

    testWidgets('a tap lands on the widget under the pointer', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var taps = 0;

      await tester.pumpWidget(app(
        scale: 2.0,
        child: Align(
          alignment: Alignment.topLeft,
          child: GestureDetector(
            onTap: () => taps++,
            child: const SizedBox(key: Key('target'), width: 100, height: 50),
          ),
        ),
      ));
      // 100x50 at 2x covers (0,0)-(200,100) in the window.
      await tester.tapAt(const Offset(150, 80));
      expect(taps, 1);
      await tester.tapAt(const Offset(250, 80));
      expect(taps, 1);
    });

    testWidgets('windowToApp divides a window position by the zoom',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Offset? app0;

      await tester.pumpWidget(app(
        scale: 2.0,
        child: Builder(builder: (context) {
          app0 = context.windowToApp(const Offset(200, 100));
          return const SizedBox.shrink();
        }),
      ));

      expect(app0, const Offset(100, 50));
    });

    testWidgets('a small window caps the zoom and says so', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Size? seen;
      QueryaUiZoomScope? scope;

      await tester.pumpWidget(app(
        scale: 2.0,
        child: Builder(builder: (context) {
          seen = MediaQuery.sizeOf(context);
          scope = QueryaUiZoomScope.maybeOf(context);
          return const SizedBox.shrink();
        }),
      ));

      expect(seen!.width, closeTo(1280 / 1.2, 1e-6));
      expect(seen!.height, closeTo(600, 1e-6));
      expect(scope!.requested, 2.0);
      expect(scope!.effective, closeTo(1.2, 1e-9));
      expect(scope!.isCapped, isTrue);
    });

    testWidgets('a change of scale is animated, not a jump', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final seen = <double>[];
      Widget build(double scale) => app(
            scale: scale,
            duration: const Duration(milliseconds: 200),
            child: Builder(builder: (context) {
              seen.add(QueryaUiZoomScope.maybeOf(context)!.effective);
              return const SizedBox.shrink();
            }),
          );

      await tester.pumpWidget(build(1.0));
      await tester.pumpWidget(build(1.5));
      await tester.pump(const Duration(milliseconds: 100));
      final midway = seen.last;
      await tester.pump(const Duration(milliseconds: 150));

      expect(midway, greaterThan(1.0));
      expect(midway, lessThan(1.5));
      expect(seen.last, closeTo(1.5, 1e-9));
    });
  });
}
