import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/token_colors_codec.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';

void main() {
  test('tokenColorRulesToJson round-trips rules', () {
    const rules = [
      TokenColorRule(
        scopes: ['comment', 'comment.line'],
        foreground: '#6272a4',
        fontStyle: 'italic',
      ),
      TokenColorRule(
        scopes: ['keyword'],
        foreground: '#ff79c6',
      ),
    ];

    final json = tokenColorRulesToJson(rules);
    final restored = tokenColorRulesFromJson(json);

    expect(restored.length, 2);
    expect(restored.first.scopes, ['comment', 'comment.line']);
    expect(restored.first.foreground, '#6272a4');
    expect(restored.first.fontStyle, 'italic');
    expect(restored[1].scopes, ['keyword']);
  });
}
