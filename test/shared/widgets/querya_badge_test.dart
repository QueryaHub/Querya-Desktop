import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('QueryaBadge', () {
    testWidgets('renders primary key badge with key icon', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaBadge.primaryKey(),
        ),
      );

      expect(find.text('PK'), findsOneWidget);
      expect(find.byIcon(material.Icons.vpn_key_rounded), findsOneWidget);
    });

    testWidgets('renders foreign key badge with link icon', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaBadge.foreignKey(),
        ),
      );

      expect(find.text('FK'), findsOneWidget);
      expect(find.byIcon(material.Icons.link_rounded), findsOneWidget);
    });

    testWidgets('renders data type badge in uppercase', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaBadge.dataType('uuid'),
        ),
      );

      expect(find.text('UUID'), findsOneWidget);
    });

    testWidgets('renders status badge with status icon', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaBadge.status(
            'Connected',
            status: QueryaBadgeStatus.success,
          ),
        ),
      );

      expect(find.text('Connected'), findsOneWidget);
      expect(find.byIcon(material.Icons.check_circle_outline_rounded), findsOneWidget);
    });

    testWidgets('renders read-only badge with lock icon', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaBadge.readOnly(),
        ),
      );

      expect(find.text('READ ONLY'), findsOneWidget);
      expect(find.byIcon(material.Icons.lock_outline_rounded), findsOneWidget);
    });
  });
}
