import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_note_ops.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';

ErdNote _note(String id, {double x = 50, double y = 60}) =>
    ErdNote(id: id, text: 't', x: x, y: y);

void main() {
  group('ErdNoteOps.nextId', () {
    test('starts at n1 and skips taken ids', () {
      expect(ErdNoteOps.nextId(const []), 'n1');
      expect(ErdNoteOps.nextId([_note('n1'), _note('n3')]), 'n2');
    });
  });

  group('ErdNoteOps.create', () {
    test('centres the note on the point', () {
      final n = ErdNoteOps.create(const [],
          text: 'hello', centre: const Offset(500, 400));
      expect(n.text, 'hello');
      expect(n.x, 500 - ErdNote.defaultWidth / 2);
      expect(n.y, 400 - ErdNote.defaultHeight / 2);
    });

    test('keeps 8 px from the origin', () {
      final n = ErdNoteOps.create(const [],
          text: 'x', centre: const Offset(0, 0));
      expect(n.x, 8);
      expect(n.y, 8);
    });
  });

  group('ErdNoteOps.moved', () {
    test('divides the screen delta by the zoom', () {
      final n = ErdNoteOps.moved(_note('n1'), const Offset(20, 10), 2);
      expect(n.x, 60);
      expect(n.y, 65);
    });

    test('never leaves the canvas', () {
      final n = ErdNoteOps.moved(_note('n1', x: 5, y: 5),
          const Offset(-100, -100), 1);
      expect(n.x, 0);
      expect(n.y, 0);
    });

    test('treats a zero scale as 1', () {
      final n = ErdNoteOps.moved(_note('n1'), const Offset(10, 0), 0);
      expect(n.x, 60);
    });
  });

  group('ErdNoteOps.resized', () {
    test('grows by the zoomed delta', () {
      final n = ErdNoteOps.resized(_note('n1'), const Offset(40, 20), 2);
      expect(n.width, ErdNote.defaultWidth + 20);
      expect(n.height, ErdNote.defaultHeight + 10);
    });

    test('stops at the minimum size', () {
      final n = ErdNoteOps.resized(_note('n1'), const Offset(-999, -999), 1);
      expect(n.width, ErdNote.minWidth);
      expect(n.height, ErdNote.minHeight);
    });
  });

  group('ErdNoteOps.nearestTable', () {
    test('picks the table whose card is closest to the note', () {
      final schema = ErdSchema(
        tables: [
          const ErdTable(name: 'a', columns: []),
          const ErdTable(name: 'b', columns: []),
        ],
        relations: const [],
      );
      final layout = ErdLayout.compute(schema);
      final near = layout.rectOf(schema.tables[1]).center;
      final note = ErdNote(
        id: 'n1',
        text: 't',
        x: near.dx - ErdNote.defaultWidth / 2,
        y: near.dy - ErdNote.defaultHeight / 2,
      );
      expect(ErdNoteOps.nearestTable(note, layout, schema), 'b');
    });

    test('is null for a diagram without tables', () {
      const schema = ErdSchema(tables: [], relations: []);
      final layout = ErdLayout.compute(schema);
      expect(ErdNoteOps.nearestTable(_note('n1'), layout, schema), isNull);
    });
  });
}
