import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/erd/erd_viewport.dart';

void main() {
  group('zoom and pan', () {
    late ErdViewport v;
    setUp(() => v = ErdViewport());
    tearDown(() => v.dispose());

    test('set and read back the scale and the translation', () {
      v.set(scale: 1.5, translation: const Offset(30, 40));
      expect(v.scale, closeTo(1.5, 1e-9));
      expect(v.translation, const Offset(30, 40));
    });

    test('zooming about a point keeps that point still', () {
      v.set(scale: 1, translation: const Offset(10, 10));
      const focal = Offset(200, 100);
      final before = v.toCanvas(focal);
      v.zoomTo(2, focal);
      expect(v.scale, closeTo(2, 1e-9));
      final after = v.toCanvas(focal);
      expect(after.dx, closeTo(before.dx, 1e-9));
      expect(after.dy, closeTo(before.dy, 1e-9));
    });

    test('the zoom stays between the floor and the maximum', () {
      v.zoomTo(100, Offset.zero);
      expect(v.scale, ErdViewport.maxScale);
      v.zoomTo(0.0001, Offset.zero);
      expect(v.scale, ErdViewport.minScale);
      v.zoomFloor = 0.05;
      v.zoomTo(0.0001, Offset.zero);
      expect(v.scale, closeTo(0.05, 1e-9));
    });

    test('screen and canvas positions convert both ways', () {
      v.set(scale: 2, translation: const Offset(10, 20));
      expect(v.toScreen(const Offset(5, 5)), const Offset(20, 30));
      expect(v.toCanvas(const Offset(20, 30)), const Offset(5, 5));
    });

    test('before it is laid out there is no size, no fit, no centre', () {
      expect(v.size, isNull);
      expect(v.fit(const Size(100, 100)), isNull);
      expect(v.centre(), const Offset(60, 60));
      v.zoomBy(2); // nothing to zoom about: no change
      expect(v.scale, 1);
    });
  });

  group('in a laid out viewport', () {
    testWidgets('fit centres a small diagram without enlarging it', (t) async {
      final v = ErdViewport();
      addTearDown(v.dispose);
      await t.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 800, height: 600, child: SizedBox(key: v.key)),
      ));
      expect(v.size, const Size(800, 600));

      expect(v.fit(const Size(400, 300)), isFalse);
      expect(v.scale, closeTo(1, 1e-9));
      expect(v.translation, const Offset(200, 150));
      expect(v.centre(), const Offset(200, 150));
    });

    testWidgets('fit shrinks a big diagram and lowers the zoom floor',
        (t) async {
      final v = ErdViewport();
      addTearDown(v.dispose);
      await t.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 800, height: 600, child: SizedBox(key: v.key)),
      ));
      final moved = v.fit(const Size(16000, 12000));
      expect(moved, isTrue);
      expect(v.scale, lessThan(ErdViewport.minScale));
      expect(v.zoomFloor, closeTo(v.scale, 1e-9));
    });

    testWidgets('centreOn puts a canvas point in the middle, keeping the zoom',
        (t) async {
      final v = ErdViewport();
      addTearDown(v.dispose);
      await t.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 800, height: 600, child: SizedBox(key: v.key)),
      ));
      v.set(scale: 2, translation: Offset.zero);
      v.centreOn(const Offset(1000, 500));
      expect(v.scale, closeTo(2, 1e-9));
      final c = v.toCanvas(const Offset(400, 300));
      expect(c.dx, closeTo(1000, 1e-9));
      expect(c.dy, closeTo(500, 1e-9));
    });
  });
}
