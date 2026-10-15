import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/security/pii_masking_controller.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';

import '../../support/querya_theme_test_shell.dart';

material.Widget _shell({required material.Widget child}) {
  return queryaThemeTestShell(child: material.Scaffold(body: child));
}

void main() {
  group('VirtualResultGrid listeners (#1555)', () {
    testWidgets('disposing a grid removes its listener from PiiMaskingController',
        (tester) async {
      // ignore: invalid_use_of_protected_member
      final before = PiiMaskingController.instance.hasListeners;

      await tester.pumpWidget(
        _shell(
          child: const material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: ['id', 'name'],
              rows: [
                ['1', 'Alice'],
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // ignore: invalid_use_of_protected_member
      expect(PiiMaskingController.instance.hasListeners, isTrue);

      await tester.pumpWidget(_shell(child: const material.SizedBox()));
      await tester.pumpAndSettle();

      // ignore: invalid_use_of_protected_member
      expect(PiiMaskingController.instance.hasListeners, before);
    });
  });
}
