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

    test('preview updates controller without persisting', () {
      final controller = UiScaleController.instance;
      final before = controller.scale;
      controller.setScalePreview(1.15);
      expect(controller.scale, closeTo(1.15, 0.001));
      controller.setScalePreview(before);
    });
  });

  group('ui scale range', () {
    test('matches Telegram-style 75–200 percent bounds', () {
      expect(kMinUiScale, 0.75);
      expect(kMaxUiScale, 2.0);
      expect(kUiScaleStep, 0.01);
    });
  });
}
