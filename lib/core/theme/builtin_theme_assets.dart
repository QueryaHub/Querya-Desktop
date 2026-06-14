/// Bundled theme JSON files shipped in the Flutter asset bundle.
abstract final class BuiltinThemeAssets {
  static const directory = 'assets/themes';

  /// File names under [directory] that are registered as built-in themes.
  static const bundledFiles = <String>[
    'cyberpunk-neon.json',
  ];

  static String assetPath(String fileName) => '$directory/$fileName';
}
