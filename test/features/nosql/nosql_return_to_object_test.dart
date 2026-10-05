import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/main_screen/main_screen_workspace_state.dart';
import 'package:querya_desktop/features/mongodb/mongo_stats_view.dart';
import 'package:querya_desktop/features/redis/redis_view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

void main() {
  final createdAt = DateTime.utc(2025).toIso8601String();
  final mongoConn = ConnectionRow(
    type: 'mongodb',
    name: 'prod_mongo',
    host: '127.0.0.1',
    port: 27017,
    createdAt: createdAt,
    id: 101,
  );
  final redisConn = ConnectionRow(
    type: 'redis',
    name: 'prod_redis',
    host: '127.0.0.1',
    port: 6379,
    createdAt: createdAt,
    id: 102,
  );

  group('MainScreenWorkspaceState NoSQL 1-click restore', () {
    test('restores MongoDB database and collection', () {
      final state = MainScreenWorkspaceState.empty
          .selectMongoCollection(mongoConn, 'ecommerce', 'orders')
          .unselectActiveObject();

      expect(state.activeMongoDB, isNull);
      expect(state.selectedMongoCollection, isNull);
      expect(state.lastSelectedMongoDb, 'ecommerce');
      expect(state.lastSelectedMongoCollection, 'orders');

      final restored = state.restoreLastSelectedObject();
      expect(restored.activeMongoDB, 'ecommerce');
      expect(restored.selectedMongoCollection, 'orders');
    });

    test('restores Redis database and key', () {
      final state = MainScreenWorkspaceState.empty
          .selectRedisDb(redisConn, 3, key: 'user:session:99')
          .unselectActiveObject();

      expect(state.activeRedisDb, isNull);
      expect(state.selectedRedisKey, isNull);
      expect(state.lastSelectedRedisDb, 3);
      expect(state.lastSelectedRedisKey, 'user:session:99');

      final restored = state.restoreLastSelectedObject();
      expect(restored.activeRedisDb, 3);
      expect(restored.selectedRedisKey, 'user:session:99');
    });
  });

  group('MongoStatsView Return to Collection / Database button', () {
    testWidgets('shows Return to collection when collection is set',
        (tester) async {
      var restored = false;
      await tester.pumpWidget(
        shadcn.ShadcnApp(
          home: material.Scaffold(
            body: MongoStatsView(
              connectionRow: mongoConn,
              lastSelectedMongoDb: 'ecommerce',
              lastSelectedMongoCollection: 'orders',
              onRestoreLastSelectedObject: () => restored = true,
            ),
          ),
        ),
      );

      final buttonFinder = find.widgetWithText(
        shadcn.OutlineButton,
        'Return to orders',
      );
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pump();
      expect(restored, isTrue);
    });

    testWidgets('shows Return to database when only database is set',
        (tester) async {
      var restored = false;
      await tester.pumpWidget(
        shadcn.ShadcnApp(
          home: material.Scaffold(
            body: MongoStatsView(
              connectionRow: mongoConn,
              lastSelectedMongoDb: 'ecommerce',
              lastSelectedMongoCollection: null,
              onRestoreLastSelectedObject: () => restored = true,
            ),
          ),
        ),
      );

      final buttonFinder = find.widgetWithText(
        shadcn.OutlineButton,
        'Return to ecommerce',
      );
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pump();
      expect(restored, isTrue);
    });
  });

  group('RedisView Return to Key / Database button', () {
    testWidgets('shows Return to key when key is set', (tester) async {
      var restored = false;
      await tester.pumpWidget(
        shadcn.ShadcnApp(
          home: material.Scaffold(
            body: RedisView(
              connectionRow: redisConn,
              lastSelectedRedisDb: 0,
              lastSelectedRedisKey: 'cache:config:app',
              onRestoreLastSelectedObject: () => restored = true,
            ),
          ),
        ),
      );

      final buttonFinder = find.widgetWithText(
        shadcn.OutlineButton,
        'Return to cache:config:app',
      );
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pump();
      expect(restored, isTrue);
    });

    testWidgets('shows Return to db when only db is set', (tester) async {
      var restored = false;
      await tester.pumpWidget(
        shadcn.ShadcnApp(
          home: material.Scaffold(
            body: RedisView(
              connectionRow: redisConn,
              lastSelectedRedisDb: 5,
              lastSelectedRedisKey: null,
              onRestoreLastSelectedObject: () => restored = true,
            ),
          ),
        ),
      );

      final buttonFinder = find.widgetWithText(
        shadcn.OutlineButton,
        'Return to db5',
      );
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pump();
      expect(restored, isTrue);
    });
  });
}
