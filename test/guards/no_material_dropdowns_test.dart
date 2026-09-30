import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1021: Material dropdown / popup menus must not reappear in `lib/`.
void main() {
  test('no Material DropdownButton / PopupMenuButton / showMenu in lib/', () {
    final banned = RegExp(
      r'\b(DropdownButtonFormField|DropdownButton|PopupMenuButton|showMenu)\b\s*[<(]',
    );
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('lib/shared/widgets/')) continue;
      if (banned.hasMatch(f.readAsStringSync())) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });
}
