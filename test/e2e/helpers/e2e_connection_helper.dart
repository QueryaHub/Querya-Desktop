import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';

/// Programmatic connection setup for E2E scenarios. Only stores configuration;
/// nothing connects until the scenario taps the connection in the sidebar.
class E2eConnections {
  E2eConnections._();

  static ConnectionRow _row(
    String type,
    String name, {
    String? host,
    int? port,
    String? username,
    String? database,
    String? extensionId,
  }) =>
      ConnectionRow(
        type: type,
        name: name,
        host: host,
        port: port,
        username: username,
        databaseName: database,
        extensionId: extensionId,
        createdAt: DateTime.utc(2026).toIso8601String(),
      );

  static ConnectionRow postgres(String name) => _row('postgresql', name,
      host: 'localhost', port: 5432, username: 'querya', database: 'querya');
  static ConnectionRow mysql(String name) => _row('mysql', name,
      host: 'localhost', port: 3306, username: 'querya', database: 'querya');
  static ConnectionRow mongo(String name) => _row('mongodb', name,
      host: 'localhost', port: 27017, username: 'querya', database: 'querya');
  static ConnectionRow redis(String name) =>
      _row('redis', name, host: 'localhost', port: 6379);
  static ConnectionRow sqlite(String name, String path) =>
      _row('sqlite', name, database: path);
  static ConnectionRow extension(String name, String extensionId) =>
      _row('extension', name, host: 'localhost', extensionId: extensionId);

  /// Saves [row] and refreshes the sidebar; returns the new connection id.
  static Future<int> add(WidgetTester tester, ConnectionRow row) async {
    final id = await tester.runAsync(() => LocalDb.instance.addConnection(row));
    await reloadSidebar(tester);
    return id!;
  }

  static Future<void> remove(WidgetTester tester, int id) async {
    await tester.runAsync(() => LocalDb.instance.removeConnection(id));
    await reloadSidebar(tester);
    // Let the tile's exit animation finish.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Re-reads connections from the database into the mounted sidebar.
  static Future<void> reloadSidebar(WidgetTester tester) async {
    final panel = tester.state<ConnectionsPanelState>(
      find.byType(ConnectionsPanel),
    );
    await tester.runAsync(panel.reloadConnectionsFromDb);
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Selects the connection tile named [name] (opens its workspace).
  static Future<void> open(WidgetTester tester, String name) async {
    await tester.tap(find.text(name).first);
    await tester.pump(const Duration(milliseconds: 300));
  }
}
