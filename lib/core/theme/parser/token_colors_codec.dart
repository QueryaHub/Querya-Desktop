import 'dart:convert';

import 'vscode_theme_manifest.dart';

/// JSON persistence for [TokenColorRule] lists (theme import storage).
List<TokenColorRule> tokenColorRulesFromJson(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! List) return const [];
  final rules = <TokenColorRule>[];
  for (final item in decoded) {
    if (item is Map<String, dynamic>) {
      final rule = TokenColorRule.tryParse(item);
      if (rule != null) rules.add(rule);
    }
  }
  return rules;
}

String tokenColorRulesToJson(List<TokenColorRule> rules) {
  final list = [
    for (final r in rules)
      {
        'scope': r.scopes.length == 1 ? r.scopes.single : r.scopes,
        'settings': {
          if (r.foreground != null) 'foreground': r.foreground,
          if (r.background != null) 'background': r.background,
          if (r.fontStyle != null) 'fontStyle': r.fontStyle,
        },
      },
  ];
  return jsonEncode(list);
}
