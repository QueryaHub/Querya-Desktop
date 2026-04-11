import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/database/redis_service.dart';

/// Disconnects all pooled / cached client connections (PostgreSQL pool, MySQL,
/// Mongo, Redis). Safe to call when no connections exist.
Future<void> disconnectAllExternalServices() async {
  await PostgresService.instance.disconnectAll();
  await MysqlService.instance.disconnectAll();
  await MongoService.instance.disconnectAll();
  await RedisService.instance.disconnectAll();
}
