import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Service that creates, seeds, and manages a lightweight Demo Playground
/// SQLite database for instant exploration without configuring external servers.
abstract final class DemoPlaygroundService {
  static const String demoConnectionName = 'Sample Demo Playground';

  static const String demoDefaultQuery = '''
-- ✨ Welcome to Querya Demo Playground!
-- Press Cmd+Enter (macOS) or Ctrl+Enter (Linux/Windows) to run queries.
-- Try:
--   • Clicking column headers to sort ascending/descending
--   • Dragging column dividers to resize
--   • Shift+Clicking to select cell ranges and Cmd+C/Ctrl+C to copy TSV
--   • Pressing Cmd+B / Ctrl+B to toggle the left sidebar with fluid spring motion

SELECT 
  o.id AS order_id,
  u.full_name AS customer,
  u.email,
  p.category,
  o.product_name,
  o.amount,
  o.status,
  o.created_at
FROM orders o
JOIN users u ON o.user_id = u.id
JOIN products p ON o.product_id = p.id
ORDER BY o.created_at DESC;
''';

  /// Resolves the filesystem path for the demo playground database file.
  static Future<String> resolveDemoDatabasePath() async {
    final supportDir = await AppDataRoot.applicationSupportDirectory();
    final demoDir = Directory(p.join(supportDir.path, 'demo'));
    if (!await demoDir.exists()) {
      await demoDir.create(recursive: true);
    }
    return p.join(demoDir.path, 'demo_playground.sqlite');
  }

  /// Seeds the demo SQLite database with sample tables and rows if not populated.
  static Future<void> seedDemoDatabase(String dbPath) async {
    await LocalDb.initFfi();
    final db = await databaseFactoryFfi.openDatabase(dbPath);
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          full_name TEXT NOT NULL,
          email TEXT NOT NULL UNIQUE,
          role TEXT NOT NULL,
          avatar_color TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          category TEXT NOT NULL,
          price REAL NOT NULL,
          stock INTEGER NOT NULL,
          rating REAL NOT NULL
        );
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL REFERENCES users(id),
          product_id INTEGER NOT NULL REFERENCES products(id),
          product_name TEXT NOT NULL,
          amount REAL NOT NULL,
          currency TEXT NOT NULL DEFAULT 'USD',
          status TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
      ''');

      final userCountResult = await db.rawQuery('SELECT COUNT(*) as count FROM users;');
      final userCount = (userCountResult.first['count'] as num?)?.toInt() ?? 0;

      if (userCount == 0) {
        final batch = db.batch();
        batch.rawInsert('''
          INSERT INTO users (full_name, email, role, avatar_color, created_at) VALUES
            ('Alex River', 'alex.river@example.com', 'Admin', '#06B6D4', '2026-01-10T08:30:00Z'),
            ('Elena Vance', 'elena.vance@example.com', 'Engineer', '#8B5CF6', '2026-01-14T11:20:00Z'),
            ('Marcus Chen', 'marcus.c@example.com', 'Product Manager', '#10B981', '2026-01-18T14:45:00Z'),
            ('Sophia Taylor', 'sophia.t@example.com', 'Designer', '#F59E0B', '2026-02-01T09:15:00Z'),
            ('David Kim', 'david.kim@example.com', 'Data Scientist', '#EC4899', '2026-02-05T16:00:00Z'),
            ('Olivia Brown', 'olivia.b@example.com', 'QA Lead', '#3B82F6', '2026-02-10T12:10:00Z'),
            ('Lucas Garcia', 'lucas.g@example.com', 'Security Engineer', '#EF4444', '2026-02-12T15:30:00Z'),
            ('Emma Watson', 'emma.w@example.com', 'Analyst', '#6366F1', '2026-02-15T10:00:00Z');
        ''');

        batch.rawInsert('''
          INSERT INTO products (title, category, price, stock, rating) VALUES
            ('UltraWide 34" Curved Monitor', 'Hardware', 749.99, 45, 4.8),
            ('Ergonomic Mechanical Keyboard', 'Peripherals', 189.50, 120, 4.9),
            ('Precision Wireless Mouse', 'Peripherals', 89.00, 200, 4.7),
            ('Noise Cancelling Studio Headphones', 'Audio', 299.99, 60, 4.8),
            ('USB-C 100W Multiport Dock', 'Accessories', 129.99, 85, 4.6),
            ('4K Ultra HD Streaming Webcam', 'Video', 159.00, 95, 4.5),
            ('Adjustable Standing Desk Mat', 'Office', 69.95, 150, 4.7),
            ('Thunderbolt 4 Pro Cable 2m', 'Accessories', 49.00, 300, 4.9);
        ''');

        batch.rawInsert('''
          INSERT INTO orders (user_id, product_id, product_name, amount, currency, status, created_at) VALUES
            (1, 1, 'UltraWide 34" Curved Monitor', 749.99, 'USD', 'delivered', '2026-02-16T10:30:00Z'),
            (2, 2, 'Ergonomic Mechanical Keyboard', 189.50, 'USD', 'delivered', '2026-02-16T14:15:00Z'),
            (3, 4, 'Noise Cancelling Studio Headphones', 299.99, 'USD', 'shipped', '2026-02-17T09:00:00Z'),
            (4, 3, 'Precision Wireless Mouse', 89.00, 'USD', 'delivered', '2026-02-17T11:45:00Z'),
            (5, 5, 'USB-C 100W Multiport Dock', 129.99, 'USD', 'processing', '2026-02-18T08:20:00Z'),
            (6, 6, '4K Ultra HD Streaming Webcam', 159.00, 'USD', 'shipped', '2026-02-18T13:10:00Z'),
            (7, 2, 'Ergonomic Mechanical Keyboard', 189.50, 'USD', 'delivered', '2026-02-19T16:00:00Z'),
            (8, 7, 'Adjustable Standing Desk Mat', 69.95, 'USD', 'processing', '2026-02-20T10:15:00Z'),
            (1, 8, 'Thunderbolt 4 Pro Cable 2m', 49.00, 'USD', 'delivered', '2026-02-20T12:40:00Z'),
            (3, 1, 'UltraWide 34" Curved Monitor', 749.99, 'USD', 'processing', '2026-02-21T09:30:00Z'),
            (5, 4, 'Noise Cancelling Studio Headphones', 299.99, 'USD', 'pending', '2026-02-22T15:00:00Z'),
            (2, 5, 'USB-C 100W Multiport Dock', 129.99, 'USD', 'pending', '2026-02-23T11:20:00Z');
        ''');

        await batch.commit(noResult: true);
      }
    } finally {
      await db.close();
    }
  }

  /// Gets or registers the demo playground connection row in [LocalDb].
  static Future<ConnectionRow> getOrCreateDemoConnection() async {
    final dbPath = await resolveDemoDatabasePath();
    await seedDemoDatabase(dbPath);

    final existingConnections = await LocalDb.instance.getConnections();
    for (final conn in existingConnections) {
      if (conn.type == 'sqlite' && (conn.host == dbPath || conn.name == demoConnectionName)) {
        return conn;
      }
    }

    final newRow = ConnectionRow(
      type: 'sqlite',
      name: demoConnectionName,
      host: dbPath,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

    final createdId = await LocalDb.instance.addConnection(newRow);
    return newRow.copyWith(id: createdId);
  }
}
