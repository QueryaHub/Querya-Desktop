import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Epic #1365: the Querya UI kit (`lib/shared/`) is moving off
/// `package:shadcn_flutter`. This guard is a ratchet: the files below still
/// import it and are allowed to, nothing else may start to, and an entry has
/// to be removed from the list in the same change that removes its import.
///
/// `widgets.dart` is the barrel that re-exports shadcn for the rest of the app
/// until the migration is done; it goes last.
void main() {
  const allowed = <String>{
    'lib/shared/widgets/app_toast.dart',
    'lib/shared/widgets/connection_tree_loading_row.dart',
    'lib/shared/widgets/export_menu_button.dart',
    'lib/shared/widgets/querya_action_button.dart',
    'lib/shared/widgets/querya_action_menu.dart',
    'lib/shared/widgets/querya_badge.dart',
    'lib/shared/widgets/querya_dialog_card.dart',
    'lib/shared/widgets/querya_dropdown.dart',
    'lib/shared/widgets/querya_empty_state.dart',
    'lib/shared/widgets/querya_icon_button.dart',
    'lib/shared/widgets/querya_modal_dialog.dart',
    'lib/shared/widgets/querya_search_field.dart',
    'lib/shared/widgets/querya_spinner.dart',
    'lib/shared/widgets/querya_tab_strip.dart',
    'lib/shared/widgets/widgets.dart',
  };

  final importsShadcn = RegExp('package:shadcn_flutter/');

  Set<String> filesImportingShadcn() {
    final found = <String>{};
    for (final entity in Directory('lib/shared').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (importsShadcn.hasMatch(entity.readAsStringSync())) {
        found.add(path);
      }
    }
    return found;
  }

  test('lib/shared does not start importing shadcn_flutter', () {
    final offenders = filesImportingShadcn().difference(allowed).toList()
      ..sort();

    expect(
      offenders,
      isEmpty,
      reason: 'These files in lib/shared import shadcn_flutter: $offenders. '
          'The UI kit is moving off it (#1365): use Flutter primitives and the '
          'kit tokens instead.',
    );
  });

  test('the allow-list only names files that still import shadcn_flutter', () {
    final stale = allowed.difference(filesImportingShadcn()).toList()..sort();

    expect(
      stale,
      isEmpty,
      reason: 'These files no longer import shadcn_flutter (or are gone): '
          '$stale. Remove them from the allow-list in this test.',
    );
  });
}
