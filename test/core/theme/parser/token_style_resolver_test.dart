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

  test('walks prefixes by dot, including empty segments (#1530)', () {
    const rules = [
      TokenColorRule(scopes: ['a'], foreground: '#010101'),
      TokenColorRule(scopes: ['a.b'], foreground: '#020202'),
      TokenColorRule(scopes: ['a.'], foreground: '#030303'),
      TokenColorRule(scopes: [''], foreground: '#040404'),
      TokenColorRule(scopes: ['x.y.z'], foreground: '#050505'),
    ];
    final resolver = TokenStyleResolver(
      rules: rules,
      defaultStyle: const TextStyle(color: Color(0xFFFFFFFF)),
    );

    // The longest prefix wins.
    expect(resolver.resolve('a.b.c.d').color, const Color(0xFF020202));
    expect(resolver.resolve('a.c.d').color, const Color(0xFF010101));
    expect(resolver.resolve('x.y.z.w').color, const Color(0xFF050505));
    // `a..b` -> `a.` -> `a`: the empty segment is a prefix of its own.
    expect(resolver.resolve('a..b').color, const Color(0xFF030303));
    // The leading dot gives the empty prefix; a bare empty scope is it too.
    expect(resolver.resolve('.q').color, const Color(0xFF040404));
    expect(resolver.resolve('').color, const Color(0xFF040404));
    // Nothing matches: the default style.
    expect(resolver.resolve('zzz.top').color, const Color(0xFFFFFFFF));
  });
}
