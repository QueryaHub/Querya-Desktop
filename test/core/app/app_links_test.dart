import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/app/app_links.dart';

void main() {
  group('AppLinks', () {
    test('repository points to Querya-Desktop GitHub', () {
      expect(AppLinks.repository, 'https://github.com/QueryaHub/Querya-Desktop');
    });

    test('documentation points to docs README on main', () {
      expect(
        AppLinks.documentation,
        'https://github.com/QueryaHub/Querya-Desktop/blob/main/docs/README.md',
      );
    });

    test('license points to LICENSE file on main', () {
      expect(
        AppLinks.license,
        'https://github.com/QueryaHub/Querya-Desktop/blob/main/LICENSE',
      );
    });
  });
}
