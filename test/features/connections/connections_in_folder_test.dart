import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';

ConnectionRow _row(int id, {int? folderId}) => ConnectionRow(
      id: id,
      type: 'postgresql',
      name: 'conn $id',
      folderId: folderId,
      createdAt: DateTime.utc(2026).toIso8601String(),
    );

void main() {
  final all = [
    _row(1),
    _row(2, folderId: 10),
    _row(3, folderId: 10),
    _row(4, folderId: 11),
  ];

  test('a folder holds the connections that carry its id', () {
    expect(connectionsInFolder(all, 10).map((c) => c.id), [2, 3]);
    expect(connectionsInFolder(all, 11).map((c) => c.id), [4]);
    expect(connectionsInFolder(all, 12), isEmpty);
  });

  test('a folder whose id is not known yet is empty, not the top level', () {
    // A freshly created folder is listed before its id is read; matching
    // folderId == null there put every top-level connection inside it.
    expect(connectionsInFolder(all, null), isEmpty);
  });
}
