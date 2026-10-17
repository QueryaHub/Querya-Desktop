import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_router.dart';
import 'package:querya_desktop/features/erd/widgets/erd_relation_painter.dart';

ErdRoute _route(String from, String to, {bool oneToOne = false}) => ErdRoute(
      ErdRelation(
        fromTable: from,
        fromColumn: 'id',
        toTable: to,
        toColumn: 'id',
        oneToOne: oneToOne,
      ),
      const [Offset(0, 0), Offset(40, 0), Offset(40, 60), Offset(120, 60)],
    );

void _paint(ErdRelationPainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(200, 100));
  recorder.endRecording().dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final routes = [_route('a', 'b'), _route('b', 'c', oneToOne: true)];

  // The painter reuses one Paint, the rounded paths and the laid-out labels
  // (#1518); these pin that every state still draws.
  group('ErdRelationPainter', () {
    test('paints with nothing focused, a focused table and a picked relation',
        () {
      const blue = Color(0xFF2196F3);
      const orange = Color(0xFFFF9800);
      _paint(ErdRelationPainter(
          routes: routes, color: blue, highlight: orange, focus: null));
      _paint(ErdRelationPainter(
          routes: routes, color: blue, highlight: orange, focus: 'b'));
      _paint(ErdRelationPainter(
          routes: routes,
          color: blue,
          highlight: orange,
          focus: null,
          picked: routes.first.relation));
    });

    test('repeated paints of the same routes keep working', () {
      final painter = ErdRelationPainter(
        routes: routes,
        color: Colors.grey,
        highlight: Colors.red,
        focus: 'a',
      );
      for (var i = 0; i < 5; i++) {
        _paint(painter);
      }
    });

    test('more distinct colours than the label cache holds still paint', () {
      for (var i = 0; i < 40; i++) {
        _paint(ErdRelationPainter(
          routes: routes,
          color: Color(0xFF000000 + i * 0x010203),
          highlight: Color(0xFF800000 + i),
          focus: i.isEven ? 'a' : null,
        ));
      }
    });

    test('a route with fewer than two points is skipped', () {
      _paint(ErdRelationPainter(
        routes: [
          ErdRoute(routes.first.relation, const [Offset(1, 1)]),
          ...routes,
        ],
        color: Colors.grey,
        highlight: Colors.red,
        focus: null,
      ));
    });

    test('repaints only when something it draws changed', () {
      ErdRelationPainter make({String? focus, List<ErdRoute>? r}) =>
          ErdRelationPainter(
            routes: r ?? routes,
            color: Colors.grey,
            highlight: Colors.red,
            focus: focus,
          );
      expect(make().shouldRepaint(make()), isFalse);
      expect(make(focus: 'a').shouldRepaint(make()), isTrue);
      expect(make(r: [...routes]).shouldRepaint(make()), isTrue);
    });
  });
}
