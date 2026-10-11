import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The button standard (`docs/ui-kit.md`, epic #1331): every button is a
/// `QueryaButton` / `QueryaIconButton` / menu or split button of the kit.
/// These guards keep the migration done. An allow-list entry names the
/// follow-up that removes it.
void main() {
  List<File> libFiles() => [
        for (final e in Directory('lib').listSync(recursive: true))
          if (e is File && e.path.endsWith('.dart')) e,
      ];

  /// The source without `//` comments, so a word in a comment is not a use.
  String code(File f) => f
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  String norm(File f) => f.path.replaceAll(r'\', '/');

  test('no shadcn button types in lib/', () {
    final banned = RegExp(
      r'\b(PrimaryButton|OutlineButton|GhostButton|DestructiveButton|'
      r'SecondaryButton|LinkButton|TextButton|ButtonSize|ButtonDensity)\b',
    );
    final offenders = <String>[];
    for (final f in libFiles()) {
      // Material's own TextButton is covered by the next guard.
      final source = code(f).replaceAll(RegExp(r'material\.TextButton'), '');
      if (banned.hasMatch(source)) offenders.add(norm(f));
    }

    expect(offenders, isEmpty,
        reason: 'shadcn buttons in $offenders: use QueryaButton.');
  });

  test('no raw Material buttons in lib/', () {
    final banned = RegExp(
      r'(?<![\w.])(material\.)?(IconButton|TextButton|ElevatedButton|'
      r'OutlinedButton|FilledButton)\(',
    );
    final offenders = <String>[];
    for (final f in libFiles()) {
      if (banned.hasMatch(code(f))) offenders.add(norm(f));
    }

    expect(offenders, isEmpty,
        reason: 'Material buttons in $offenders: use QueryaButton / '
            'QueryaIconButton.');
  });

  test('no button class outside the kit', () {
    // Each entry is a labelled trigger that is still hand-built; the
    // follow-up is #1445.
    const allowed = {
      'lib/features/settings/theme_picker_button.dart',
      'lib/features/workspace/table_view_staging.dart',
    };
    final decl = RegExp(r'^class _?\w*Button\b', multiLine: true);
    final offenders = <String>[];
    for (final f in libFiles()) {
      final path = norm(f);
      if (path.startsWith('lib/shared/widgets/')) continue;
      if (allowed.contains(path)) continue;
      if (decl.hasMatch(code(f))) offenders.add(path);
    }

    expect(offenders, isEmpty,
        reason: 'Button classes in $offenders: compose QueryaButton instead.');
  });

  test('tooltips take kQueryaTooltipWait, not a literal delay', () {
    final banned = RegExp(r'waitDuration:\s*(const\s+)?Duration\(');
    final offenders = <String>[];
    for (final f in libFiles()) {
      if (norm(f) == 'lib/core/ui/querya_tooltip.dart') continue;
      if (banned.hasMatch(code(f))) offenders.add(norm(f));
    }

    expect(offenders, isEmpty,
        reason: 'Literal tooltip delays in $offenders: use kQueryaTooltipWait.');
  });
}
