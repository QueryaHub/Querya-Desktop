import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/layout/ui_scale_controller.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/features/settings/preferences_controls.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('InterfaceScaleSlider', () {
    testWidgets('shows percentage and slider', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(
            body: InterfaceScaleSlider(scale: 1.0),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('100%'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    test('UiScaleController.normalize snaps to presets unless fine mode', () {
      expect(UiScaleController.normalize(1.15), 1.1);
      expect(UiScaleController.normalize(1.15, fine: true), closeTo(1.15, 0.001));
      expect(UiScaleController.normalize(0.88), 0.9);
    });
  });

  group('ui scale range', () {
    test('matches Telegram-style 75–200 percent bounds', () {
      expect(kMinUiScale, 0.75);
      expect(kMaxUiScale, 2.0);
      expect(kUiScaleStep, 0.01);
    });

    test('presets snap to fixed ticks', () {
      expect(kUiScalePresets, [
        0.75,
        0.85,
        0.9,
        1.0,
        1.1,
        1.25,
        1.5,
        1.75,
        2.0,
      ]);
      expect(snapUiScaleToPreset(1.12), 1.1);
      expect(snapUiScaleToPreset(0.88), 0.9);
      expect(nearestUiScalePresetIndex(1.0), 3);
    });
  });
}
