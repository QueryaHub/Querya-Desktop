import os

with open('lib/core/theme/theme_registry_service.dart', 'r') as f:
    content = f.read()

# 1. Imports
target_imports = """import 'theme_metadata.dart';
import 'theme_paths.dart';"""
new_imports = """import 'theme_metadata.dart';
import 'theme_paths.dart';
import '../extensions/local_extension_registry.dart';
import '../extensions/extension_paths.dart';
import '../extensions/models/extension_manifest.dart';
import '../extensions/models/extension_type.dart';"""
content = content.replace(target_imports, new_imports)

# 2. Add flag
target_flag = """  final List<String> _bundledThemeAssetFiles;
  final _ThemeLruCache _themeCache;
  int _themeParseCount = 0;"""
new_flag = """  final List<String> _bundledThemeAssetFiles;
  final _ThemeLruCache _themeCache;
  int _themeParseCount = 0;
  bool _hasMigratedThemes = false;"""
content = content.replace(target_flag, new_flag)

# 3. loadThemeDefinitions
target_load = """  Future<List<ThemeDefinition>> loadThemeDefinitions() async {
    final definitions = <ThemeDefinition>[];

    await _loadBuiltinAssetDefinitions(definitions);

    await _scanDirectory(
      await _userThemesDirectory(),
      ThemeSource.filesystem,
      definitions,
    );
    await _scanDirectory(
      await _importedThemesDirectory(),
      ThemeSource.imported,
      definitions,
    );

    final legacy = await _legacyImportedDefinition();
    if (legacy != null) {
      definitions.removeWhere(
        (definition) =>
            definition.path == legacy.path &&
            definition.source != ThemeSource.legacyImported,
      );
      definitions.add(legacy);
    }

    definitions.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return List.unmodifiable(definitions);
  }"""
new_load = """  Future<List<ThemeDefinition>> loadThemeDefinitions() async {
    final definitions = <ThemeDefinition>[];

    await _loadBuiltinAssetDefinitions(definitions);

    if (!_hasMigratedThemes) {
      await _migrateLegacyThemesToExtensions();
      _hasMigratedThemes = true;
    }

    await LocalExtensionRegistry.instance.load();
    for (final manifest in LocalExtensionRegistry.instance.manifests) {
      if (manifest.type != ExtensionType.theme) continue;
      final installPath = manifest.installPath;
      final mainFile = manifest.main;
      if (installPath == null || mainFile == null) continue;

      final file = File(p.join(installPath, mainFile));
      if (!await file.exists()) continue;

      final definition = await _definitionFromFile(file, ThemeSource.filesystem);
      if (definition != null) {
        definitions.add(definition);
      }
    }

    final legacy = await _legacyImportedDefinition();
    if (legacy != null) {
      definitions.removeWhere(
        (definition) =>
            definition.path == legacy.path &&
            definition.source != ThemeSource.legacyImported,
      );
      definitions.add(legacy);
    }

    definitions.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return List.unmodifiable(definitions);
  }

  Future<void> _migrateLegacyThemesToExtensions() async {
    final dirs = [
      await _userThemesDirectory(),
      await _importedThemesDirectory(),
    ];
    
    final extensionsDir = await ExtensionPaths.ensureExtensionsDirectory();

    for (final directory in dirs) {
      if (!await directory.exists()) continue;
      
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        if (p.basename(entity.path) == ThemeImportService.storedFileName) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (ext != '.json' && ext != '.jsonc') continue;

        try {
          final definition = await _definitionFromFile(entity, ThemeSource.filesystem);
          if (definition == null) continue;

          final slug = ThemeImportService.slugifyThemeName(definition.name);
          var finalExtDir = Directory(p.join(extensionsDir.path, slug));
          var counter = 2;
          while (await finalExtDir.exists()) {
            finalExtDir = Directory(p.join(extensionsDir.path, '$slug-$counter'));
            counter++;
          }
          await finalExtDir.create(recursive: true);

          final themeFile = File(p.join(finalExtDir.path, 'theme.json'));
          await entity.copy(themeFile.path);

          final manifest = ExtensionManifest(
            id: definition.id,
            name: definition.name,
            version: '1.0.0',
            publisher: 'Unknown',
            type: ExtensionType.theme,
            engines: const {'querya_desktop': '*'},
            main: 'theme.json',
            description: 'Migrated custom theme',
          );
          
          final manifestFile = File(p.join(finalExtDir.path, 'manifest.json'));
          await manifestFile.writeAsString(jsonEncode(manifest.toJson()));

          await entity.delete(); // Delete old file to complete migration
        } catch (_) {}
      }
    }
    // Reload extensions since we might have added new ones
    await LocalExtensionRegistry.instance.reload();
  }"""
content = content.replace(target_load, new_load)

# 4. importThemeFile
target_import = """  /// Validates [sourcePath], copies into the user themes directory, and returns
  /// the scanned [ThemeDefinition].
  Future<ThemeDefinitionImportResult> importThemeFile(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        return const ThemeDefinitionImportFailure('Theme file not found.');
      }

      final raw = await source.readAsString();
      final hash = _contentHash(raw);
      final json = _decodeRoot(raw);
      if (json == null) {
        return const ThemeDefinitionImportFailure('Invalid JSON.');
      }

      final themesDir = await _userThemesDirectory();
      if (!await themesDir.exists()) {
        await themesDir.create(recursive: true);
      }

      final schema = json['schema']?.toString();
      late final String logicalId;
      late final String preferredBaseName;
      late String contentToWrite;

      if (schema == queryaThemeSchemaV1) {
        final manifest = QueryaThemeManifest.fromJsonString(raw);
        logicalId = manifest.id;
        preferredBaseName = ThemeImportService.safeThemeFileBase(manifest.id);
        contentToWrite = raw;
      } else {
        final manifest = VsCodeThemeManifest.fromJsonString(raw);
        if (manifest.colors.isEmpty) {
          return const ThemeDefinitionImportFailure(
            'Theme file has no "colors" section to import.',
          );
        }
        final displayName = manifest.name?.trim().isNotEmpty == true
            ? manifest.name!.trim()
            : p.basenameWithoutExtension(sourcePath);
        preferredBaseName = ThemeImportService.slugifyThemeName(displayName);
        logicalId = preferredBaseName;
        contentToWrite = raw;
      }

      var resolved = await _resolveImportDestination(
        themesDir: themesDir,
        hash: hash,
        logicalId: logicalId,
        preferredBaseName: preferredBaseName,
      );

      if (!resolved.reused &&
          schema == queryaThemeSchemaV1 &&
          resolved.renamedId != null) {
        contentToWrite = _rewriteCustomThemeId(raw, resolved.renamedId!);
      }

      if (!resolved.reused) {
        await resolved.file.writeAsString(contentToWrite);
      }

      final definition =
          await _definitionFromFile(resolved.file, ThemeSource.filesystem);
      if (definition == null) {
        return const ThemeDefinitionImportFailure(
          'Failed to index imported theme.',
        );
      }

      return ThemeDefinitionImportSuccess(
        definition: definition,
        reusedExisting: resolved.reused,
      );
    } on QueryaThemeManifestParseException catch (e) {
      return ThemeDefinitionImportFailure(e.message);
    } on VsCodeThemeParseException catch (e) {
      return ThemeDefinitionImportFailure(e.message);
    } on IOException catch (e) {
      return ThemeDefinitionImportFailure(e.toString());
    } on Object catch (e) {
      return ThemeDefinitionImportFailure(e.toString());
    }
  }"""

new_import = """  /// Validates [sourcePath], creates an extension directory, and returns
  /// the scanned [ThemeDefinition].
  Future<ThemeDefinitionImportResult> importThemeFile(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        return const ThemeDefinitionImportFailure('Theme file not found.');
      }

      final raw = await source.readAsString();
      final json = _decodeRoot(raw);
      if (json == null) {
        return const ThemeDefinitionImportFailure('Invalid JSON.');
      }

      final extensionsDir = await ExtensionPaths.ensureExtensionsDirectory();

      final schema = json['schema']?.toString();
      late final String logicalId;
      late final String preferredBaseName;
      late String contentToWrite;

      if (schema == queryaThemeSchemaV1) {
        final manifest = QueryaThemeManifest.fromJsonString(raw);
        logicalId = manifest.id;
        preferredBaseName = ThemeImportService.safeThemeFileBase(manifest.id);
        contentToWrite = raw;
      } else {
        final manifest = VsCodeThemeManifest.fromJsonString(raw);
        if (manifest.colors.isEmpty) {
          return const ThemeDefinitionImportFailure(
            'Theme file has no "colors" section to import.',
          );
        }
        final displayName = manifest.name?.trim().isNotEmpty == true
            ? manifest.name!.trim()
            : p.basenameWithoutExtension(sourcePath);
        preferredBaseName = ThemeImportService.slugifyThemeName(displayName);
        logicalId = preferredBaseName;
        contentToWrite = raw;
      }

      await LocalExtensionRegistry.instance.load();
      bool reused = false;
      String? existingInstallPath;
      
      for (final extManifest in LocalExtensionRegistry.instance.manifests) {
        if (extManifest.type == ExtensionType.theme && extManifest.id == logicalId) {
           reused = true;
           existingInstallPath = extManifest.installPath;
           break;
        }
      }

      File resolvedFile;
      if (reused && existingInstallPath != null) {
         resolvedFile = File(p.join(existingInstallPath, 'theme.json'));
      } else {
         var finalExtDir = Directory(p.join(extensionsDir.path, preferredBaseName));
         var counter = 2;
         while (await finalExtDir.exists()) {
           finalExtDir = Directory(p.join(extensionsDir.path, '$preferredBaseName-$counter'));
           counter++;
         }
         await finalExtDir.create(recursive: true);
         
         resolvedFile = File(p.join(finalExtDir.path, 'theme.json'));
         await resolvedFile.writeAsString(contentToWrite);

         final newManifest = ExtensionManifest(
            id: logicalId,
            name: preferredBaseName,
            version: '1.0.0',
            publisher: 'Unknown',
            type: ExtensionType.theme,
            engines: const {'querya_desktop': '*'},
            main: 'theme.json',
            description: 'Imported custom theme',
         );
         final manifestFile = File(p.join(finalExtDir.path, 'manifest.json'));
         await manifestFile.writeAsString(jsonEncode(newManifest.toJson()));
         
         await LocalExtensionRegistry.instance.reload();
      }

      final definition = await _definitionFromFile(resolvedFile, ThemeSource.filesystem);
      if (definition == null) {
        return const ThemeDefinitionImportFailure('Failed to index imported theme.');
      }

      return ThemeDefinitionImportSuccess(
        definition: definition,
        reusedExisting: reused,
      );
    } on QueryaThemeManifestParseException catch (e) {
      return ThemeDefinitionImportFailure(e.message);
    } on VsCodeThemeParseException catch (e) {
      return ThemeDefinitionImportFailure(e.message);
    } on IOException catch (e) {
      return ThemeDefinitionImportFailure(e.toString());
    } on Object catch (e) {
      return ThemeDefinitionImportFailure(e.toString());
    }
  }"""
content = content.replace(target_import, new_import)

# 5. Remove unused methods using python block extracting instead of regex
# Or just simple replace
import re
to_remove = [
    (r'  Future<void> _scanDirectory\(', r'^\s*\}\s*$', 3),
    (r'  Future<_ResolvedImportDestination> _resolveImportDestination\(', r'^\s*\}\s*$', 3),
    (r'  Future<String> _nextRenamedThemeId\(', r'^\s*\}\s*$', 3),
    (r'  Future<bool> _themeIdExists\(', r'^\s*\}\s*$', 3),
    (r'  Future<File> _nextAvailableThemeFile\(', r'^\s*\}\s*$', 3),
    (r'  String _rewriteCustomThemeId\(', r'^\s*\}\s*$', 3),
    (r'class _ResolvedImportDestination \{', r'^\}\s*$', 0),
]

lines = content.split('\n')
for start_regex, end_regex, indent in to_remove:
    start_idx = -1
    end_idx = -1
    for i, line in enumerate(lines):
        if re.search(start_regex, line):
            start_idx = i
            break
    if start_idx != -1:
        # find matching closing brace
        brace_count = 0
        started = False
        for i in range(start_idx, len(lines)):
            brace_count += lines[i].count('{')
            brace_count -= lines[i].count('}')
            if '{' in lines[i]:
                started = True
            if started and brace_count == 0:
                end_idx = i
                break
        if end_idx != -1:
            lines[start_idx:end_idx+1] = []

content = '\n'.join(lines)

with open('lib/core/theme/theme_registry_service.dart', 'w') as f:
    f.write(content)

print("Patch applied successfully.")
