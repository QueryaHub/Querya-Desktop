import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_note_text.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/core/erd/erd_layout.dart';

/// #1283: sticky notes.
void main() {
  group('note text', () {
    test('bold runs and bullets', () {
      final lines = parseErdNote('**Legacy** table\n- filled nightly\n* by cron');
      expect(lines, hasLength(3));
      expect([for (final r in lines[0].runs) (r.text, r.bold)],
          [('Legacy', true), (' table', false)]);
      expect(lines[1].bullet, isTrue);
      expect(lines[1].plain, 'filled nightly');
      expect(lines[2].bullet, isTrue);
    });

    test('an unclosed marker is kept as typed', () {
      final line = parseErdNote('a **b').single;
      expect(line.plain, 'a **b');
      expect(line.runs.every((r) => !r.bold), isTrue);
    });
  });

  group('saved notes', () {
    const note = ErdNote(
      id: 'n1',
      text: '**Careful**',
      x: 40.04,
      y: 80,
      width: 220,
      height: 90,
      color: 'type2',
      attachedTo: 'orders',
    );

    test('come back from JSON', () {
      final back =
          ErdSavedLayout.decode(const ErdSavedLayout(notes: [note]).encode())!;
      final n = back.notes.single;
      expect((n.id, n.text, n.x, n.y, n.width, n.height),
          ('n1', '**Careful**', 40.0, 80.0, 220.0, 90.0));
      expect((n.color, n.attachedTo), ('type2', 'orders'));
      expect(const ErdSavedLayout(notes: [note]).isEmpty, isFalse);
    });

    test('broken entries go, sizes and colours are bounded', () {
      final back = ErdSavedLayout.decode('{"notes": ['
          '{"id": "a", "text": "x", "x": 1, "y": 2, "w": 5, "h": 99999, '
          '"color": "#fff"},'
          '{"id": "a", "text": "dup", "x": 1, "y": 2},'
          '{"id": "", "text": "x", "x": 1, "y": 2},'
          '{"id": "b", "text": "x", "y": 2}'
          ']}')!;
      final n = back.notes.single;
      expect(n.width, ErdNote.minWidth);
      expect(n.height, 2000);
      expect(n.color, isNull);
    });

    test('a note of a gone table is kept, unattached', () {
      final kept = const ErdSavedLayout(notes: [note]).keepOnly({'users'});
      expect(kept.notes.single.attachedTo, isNull);
      expect(kept.notes.single.x, 40.04);
      expect(const ErdSavedLayout(notes: [note]).keepOnly({'orders'})
          .notes.single.attachedTo, 'orders');
    });
  });

  test('the SVG draws a note with bold, bullets and wrapping', () {
    final s = ErdSchema.fromCatalog(
        columnRows: const [['users', 'id', 'int', '1']], fkRows: const []);
    final l = ErdLayout.compute(s);
    final svg = ErdExport.toSvg(s, l, notes: [
      const ErdSvgNote(
        text: '**Legacy** & old\n- a very long line that has to wrap around '
            'because the note is narrow',
        rect: Rect.fromLTWH(300, 500, 140, 100),
        fill: '#ffffe0',
        stroke: '#cbd5e1',
      ),
    ]);
    expect('class="erd-note"'.allMatches(svg).length, 1);
    expect(svg, contains('<tspan font-weight="bold">Legacy</tspan>'));
    expect(svg, contains('&amp; old'));
    expect('class="erd-note-line"'.allMatches(svg).length, greaterThan(2));
    // The canvas grows to hold a note below the cards.
    final h = double.parse(
        RegExp(r'<svg[^>]* height="([0-9.]+)"').firstMatch(svg)!.group(1)!);
    expect(h, greaterThanOrEqualTo(600));
  });
}
