/// Monospace font stack for SQL editors, cell inspectors, and code preview dialogs.
abstract class QueryaTypography {
  QueryaTypography._();

  /// Primary monospace font family identifier.
  static const String mono = 'Cascadia Code';

  /// Cross-platform prioritized monospace font fallback list.
  ///
  /// Prioritizes modern programming fonts across operating systems:
  /// - Windows 11 / Terminal: Cascadia Code
  /// - Windows 10 / legacy: Consolas, Courier New
  /// - macOS: Menlo, SF Mono, Monaco
  /// - Linux / BSD: Fira Code, Ubuntu Mono, DejaVu Sans Mono
  /// - Generic system fallback: monospace
  ///
  /// Ends with [cjkFontFamilyFallback], so CJK text in the editor, inspectors
  /// and badges does not go through the engine's per-paragraph search.
  static const List<String> monoFontFamilyFallback = <String>[
    'Cascadia Code',
    'Consolas',
    'Menlo',
    'SF Mono',
    'Monaco',
    'Fira Code',
    'Ubuntu Mono',
    'DejaVu Sans Mono',
    'Courier New',
    'monospace',
    ...cjkFontFamilyFallback,
  ];

  /// Families that have CJK glyphs, to put after the primary family (#1553).
  ///
  /// When the primary family has none, the engine asks fontconfig (or the OS)
  /// for a fallback for every paragraph and does not reuse the answer: about
  /// 400 us per 18-character string instead of 10-30 us measured with an
  /// explicit family. A family that is not installed costs 2-5 us, so the
  /// list can be long. Use it alone where the primary family must stay the
  /// generic `monospace` (result grid cells).
  static const List<String> cjkFontFamilyFallback = <String>[
    // Linux
    'Noto Sans Mono CJK SC',
    'Noto Sans Mono CJK JP',
    'Noto Sans Mono CJK KR',
    'Noto Sans CJK SC',
    'Noto Sans CJK JP',
    'Noto Sans CJK KR',
    'WenQuanYi Micro Hei',
    // macOS
    'PingFang SC',
    'Hiragino Sans',
    'Apple SD Gothic Neo',
    // Windows
    'Microsoft YaHei',
    'Yu Gothic',
    'Malgun Gothic',
  ];
}
