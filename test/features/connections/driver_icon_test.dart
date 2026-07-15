import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/connections/driver_icon.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  testWidgets('uses fallback when bundled asset is missing', (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const DriverIcon(
          assetPath: 'assets/images/missing_database_icon.png',
          size: 32,
          fallbackIcon: material.Icons.storage_rounded,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(material.Icons.storage_rounded), findsOneWidget);
  });

  testWidgets('uses fallback when extension icon file is missing',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const DriverIcon(
          filePath: '/definitely/missing/database-icon.svg',
          size: 32,
          fallbackIcon: material.Icons.extension_rounded,
        ),
      ),
    );

    expect(find.byIcon(material.Icons.extension_rounded), findsOneWidget);
  });
}
