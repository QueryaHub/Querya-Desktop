import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1555: an extension method torn off twice gives two different closures, so
/// `removeListener(_onX)` never removes what `addListener(_onX)` stored and the
/// listener keeps its owner alive. Handlers passed to `addListener` /
/// `removeListener` must be class members or a stored closure.
void main() {
  test('addListener / removeListener never take an extension method', () {
    final extensionBody = RegExp(
      r'^extension\s+\w+(?:<[^>]*>)?\s+on\s+[^{]+\{',
      multiLine: true,
    );
    final methodDecl = RegExp(
      r'^  (?:[\w<>?,\s]+\s)?(_?\w+)\s*\([^)]*\)\s*(?:async\s*)?(?:\{|=>)',
      multiLine: true,
    );
    final listenerArg = RegExp(r'\b(?:add|remove)Listener\(\s*(_?\w+)\s*[,)]');

    final extensionMethods = <String>{};
    final files = <File>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      files.add(f);
      final src = f.readAsStringSync();
      for (final m in extensionBody.allMatches(src)) {
        // Extensions are declared at the top level; their members are indented
        // by two spaces up to the first closing brace in column zero.
        final end = src.indexOf('\n}', m.end);
        final body = src.substring(m.end, end < 0 ? src.length : end);
        for (final d in methodDecl.allMatches(body)) {
          extensionMethods.add(d.group(1)!);
        }
      }
    }

    // Comments may quote the pattern they warn about.
    final commentLine = RegExp(r'^\s*//.*$', multiLine: true);

    final offenders = <String>[];
    for (final f in files) {
      final code = f.readAsStringSync().replaceAll(commentLine, '');
      for (final m in listenerArg.allMatches(code)) {
        final name = m.group(1)!;
        if (extensionMethods.contains(name)) offenders.add('${f.path}: $name');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Extension methods passed to addListener / removeListener: '
          '$offenders. Declare them in the class or keep one closure in a '
          'field.',
    );
  });
}
