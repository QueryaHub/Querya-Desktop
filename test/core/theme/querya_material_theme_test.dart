import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_material_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';

void main() {
  test('dark material theme uses light onSurface for dropdowns', () {
    final td = materialThemeFromQuerya(QueryaTheme.darkDefault.colorScheme);
    expect(td.colorScheme.brightness, material.Brightness.dark);
    expect(td.colorScheme.onSurface, const material.Color(0xFFF8FAFC));
    expect(td.textTheme.bodyLarge?.color, const material.Color(0xFFF8FAFC));
  });

  test('light material theme uses dark onSurface', () {
    final td = materialThemeFromQuerya(QueryaTheme.lightDefault.colorScheme);
    expect(td.colorScheme.onSurface, const material.Color(0xFF0F172A));
  });
}
