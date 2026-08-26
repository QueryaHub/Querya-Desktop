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
  ];
}
