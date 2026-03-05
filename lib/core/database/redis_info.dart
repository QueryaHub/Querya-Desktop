/// Parsed Redis INFO response: section name -> key -> value.
typedef RedisInfoSections = Map<String, Map<String, String>>;

/// Parse Redis INFO string into sections and key-value pairs.
RedisInfoSections parseRedisInfo(String raw) {
  final sections = <String, Map<String, String>>{};
  String? currentSection;
  final lines = raw.split('\n');
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('#')) {
      currentSection = trimmed.substring(1).trim();
      if (currentSection.isNotEmpty && !sections.containsKey(currentSection)) {
        sections[currentSection] = {};
      }
      continue;
    }
    final colon = trimmed.indexOf(':');
    if (colon <= 0) {
      final eq = trimmed.indexOf('=');
      if (eq > 0) {
        final k = trimmed.substring(0, eq).trim();
        final v = trimmed.substring(eq + 1).trim();
        if (currentSection != null && sections[currentSection] != null) {
          sections[currentSection]![k] = v;
        }
      }
      continue;
    }
    final k = trimmed.substring(0, colon).trim();
    final v = trimmed.substring(colon + 1).trim();
    if (currentSection != null && sections[currentSection] != null) {
      sections[currentSection]![k] = v;
    }
  }
  return sections;
}

String? sectionValue(RedisInfoSections info, String section, String key) {
  return info[section]?[key];
}

int? sectionInt(RedisInfoSections info, String section, String key) {
  final v = sectionValue(info, section, key);
  if (v == null) return null;
  return int.tryParse(v);
}

double? sectionDouble(RedisInfoSections info, String section, String key) {
  final v = sectionValue(info, section, key);
  if (v == null) return null;
  return double.tryParse(v);
}
