import re

with open('lib/core/theme/theme_registry_service.dart', 'r') as f:
    content = f.read()

# Fix curly_braces_in_flow_control_structures
content = content.replace("if (!await directory.exists()) continue;", "if (!await directory.exists()) { continue; }")

# Fix unnecessary_brace_in_string_interps
content = content.replace("'${slug}-$counter'", "'$slug-$counter'")
content = content.replace("'${preferredBaseName}-$counter'", "'$preferredBaseName-$counter'")

# Fix unused hash
content = content.replace("final hash = _contentHash(raw);\n      final json = _decodeRoot(raw);", "final json = _decodeRoot(raw);")
content = content.replace("final hash = _contentHash(raw);\n      final json = _decodeRoot(raw);", "final json = _decodeRoot(raw);")  # Handle multiple occurrences if any

# Remove unused methods
methods_to_remove = [
    r'Future<void> _scanDirectory.*?^\s*\}\s*',
    r'Future<_ResolvedImportDestination> _resolveImportDestination.*?^\s*\}\s*',
    r'Future<String> _nextRenamedThemeId.*?^\s*\}\s*',
    r'Future<bool> _themeIdExists.*?^\s*\}\s*',
    r'Future<File> _nextAvailableThemeFile.*?^\s*\}\s*',
    r'String _rewriteCustomThemeId.*?^\s*\}\s*',
    r'class _ResolvedImportDestination.*?^\}\s*'
]

for pattern in methods_to_remove:
    content = re.sub(pattern, '', content, flags=re.DOTALL | re.MULTILINE)

with open('lib/core/theme/theme_registry_service.dart', 'w') as f:
    f.write(content)
