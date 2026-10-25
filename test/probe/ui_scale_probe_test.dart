import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/app/app.dart';
import 'package:querya_desktop/core/layout/ui_scale_controller.dart';
import 'package:querya_desktop/features/main_screen/main_screen.dart';
import 'package:querya_desktop/features/postgresql/postgresql_connection_form.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';

import '../e2e/helpers/e2e_app_harness.dart';
import '../e2e/helpers/e2e_command_palette_helper.dart';
import '../support/layout_overflow.dart';

/// PROBE, not a regression test: counts layout overflows of a few screens at
/// several interface scales and window sizes, and fails at the end with the
/// table so the numbers are in the CI log.
void main() {
  final app = E2eAppHarness();
  setUpAll(app.setUpAll);
  tearDownAll(app.tearDownAll);

  final rows = <String>[];

  String firstLine(FlutterErrorDetails d) {
    final s = d.exceptionAsString().split('\n').first;
    return s.length > 110 ? s.substring(0, 110) : s;
  }

  Future<void> measure(
    WidgetTester tester,
    String label,
    Future<void> Function() action,
  ) async {
    final errors = await collectOverflowErrorsDuring(() async {
      await action();
      await pumpFrames(tester, count: 10);
    });
    final distinct = <String>{for (final e in errors) firstLine(e)};
    rows.add('$label: ${errors.length} overflows'
        '${distinct.isEmpty ? '' : '  e.g. ${distinct.take(2).join(' | ')}'}');
    // The probe reads the errors; they must not fail the test run.
    tester.takeException();
  }

  for (final size in const [Size(1280, 720), Size(900, 600)]) {
    for (final scale in const [0.75, 1.0, 1.25, 1.5, 2.0]) {
      testWidgets('scale $scale at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await tester.runAsync(() => UiScaleController.instance.commitScale(scale));
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final tag = 'scale=$scale ${size.width.toInt()}x${size.height.toInt()}';

        await measure(tester, '$tag shell', () async {
          await tester.pumpWidget(const QueryaApp());
          await pumpFrames(tester, count: 20);
        });
        final ctx = tester.element(find.byType(MainScreen));

        await measure(tester, '$tag preferences', () async {
          showPreferencesDialog(ctx);
          await pumpFrames(tester, count: 20);
        });
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await pumpFrames(tester, count: 10);

        await measure(tester, '$tag postgres form', () async {
          unawaited(showPostgresConnectionForm(ctx));
          await pumpFrames(tester, count: 20);
        });
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await pumpFrames(tester, count: 10);

        await measure(tester, '$tag command palette', () async {
          await E2ePalette.open(tester);
        });
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await app.close(tester);
      });
    }
  }

  test('report', () {
    fail('UI SCALE PROBE\n${rows.join('\n')}');
  });
}
