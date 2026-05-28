import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_color_scheme.dart';
import 'package:querya_desktop/core/theme/querya_colors.dart';
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('QueryaWorkbenchTheme', () {
    test('darkDefault matches QueryaColors', () {
      const w = QueryaWorkbenchTheme.darkDefault;
      expect(w.canvas, QueryaColors.canvas);
      expect(w.surface, QueryaColors.surface);
      expect(w.accent, QueryaColors.accentCyan);
      expect(w.borderSubtle, QueryaColors.borderSubtle);
    });

    test('copyWith overrides one field', () {
      const w = QueryaWorkbenchTheme.darkDefault;
      final next = w.copyWith(accent: const Color(0xFFFF0000));
      expect(next.accent, const Color(0xFFFF0000));
      expect(next.canvas, w.canvas);
    });

    test('lerp at 0 returns a', () {
      const a = QueryaWorkbenchTheme.darkDefault;
      const b = QueryaWorkbenchTheme.lightDefault;
      final m = QueryaWorkbenchTheme.lerp(a, b, 0);
      expect(m.canvas, a.canvas);
    });
  });

  group('QueryaEditorTheme', () {
    test('copyWith and equality', () {
      const a = QueryaEditorTheme.darkDefault;
      final b = a.copyWith(fontSize: 14);
      expect(b.fontSize, 14);
      expect(b, isNot(equals(a)));
      expect(b.copyWith(fontSize: 13), equals(a));
    });
  });

  group('QueryaTheme', () {
    test('darkDefault colorScheme matches legacy QueryaColorScheme.dark', () {
      final legacy = QueryaColorScheme.dark;
      final next = QueryaTheme.darkDefault.colorScheme;
      expect(next.background, legacy.background);
      expect(next.primary, legacy.primary);
      expect(next.card, legacy.card);
      expect(next.border, legacy.border);
    });

    test('colorSchemeFromWorkbench uses workbench tokens', () {
      const w = QueryaWorkbenchTheme(
        canvas: Color(0xFF111111),
        surface: Color(0xFF222222),
        sidebarBackground: Color(0xFF111111),
        editorBackground: Color(0xFF222222),
        borderSubtle: Color(0xFF333333),
        accent: Color(0xFF00FFFF),
        onAccent: Color(0xFF000000),
        mutedForeground: Color(0xFFAAAAAA),
        destructive: Color(0xFFFF0000),
        success: Color(0xFF00FF00),
        warning: Color(0xFFFFFF00),
        gitModified: Color(0xFFFF00FF),
        gitUntracked: Color(0xFF00FF00),
      );
      final cs = QueryaTheme.colorSchemeFromWorkbench(
        w,
        brightness: Brightness.dark,
      );
      expect(cs.background, w.canvas);
      expect(cs.primary, w.accent);
    });

    test('lerp interpolates editor and workbench', () {
      const a = QueryaTheme.darkDefault;
      const b = QueryaTheme.lightDefault;
      final mid = QueryaTheme.lerp(a, b, 0.5);
      expect(mid.workbench, isNot(equals(a.workbench)));
      expect(mid.editor.foreground, isNot(equals(a.editor.foreground)));
    });

    test('toShadcnThemeData preserves brightness', () {
      final td = QueryaTheme.darkDefault.toShadcnThemeData();
      expect(td.brightness, Brightness.dark);
      expect(td.colorScheme.primary, QueryaColors.accentCyan);
    });
  });
}
