import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/token_style_resolver.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';

void main() {
  test('resolves longest matching scope prefix', () {
    const rules = [
      TokenColorRule(
        scopes: ['comment'],
        foreground: '#111111',
      ),
      TokenColorRule(
        scopes: ['keyword'],
        foreground: '#222222',
      ),
    ];
    final resolver = TokenStyleResolver(
      rules: rules,
      defaultStyle: const TextStyle(color: Color(0xFFFFFFFF)),
    );

    expect(resolver.resolve('comment.line.sql').color, const Color(0xFF111111));
    expect(resolver.resolve('keyword.control').color, const Color(0xFF222222));
    expect(resolver.resolve('unknown.scope').color, const Color(0xFFFFFFFF));
  });

  test('caches repeated scope lookups', () {
    const rules = [
      TokenColorRule(scopes: ['string'], foreground: '#ABCDEF'),
    ];
    final resolver = TokenStyleResolver(
      rules: rules,
      defaultStyle: const TextStyle(color: Color(0xFF000000)),
    );
    final a = resolver.resolve('string.quoted.double');
    final b = resolver.resolve('string.quoted.double');
    expect(identical(a, b), isTrue);
  });
}
