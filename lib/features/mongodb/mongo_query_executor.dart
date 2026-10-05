import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/features/mongodb/mql_parser.dart';

/// Result of executing an MQL statement.
class MongoQueryResult {
  const MongoQueryResult({
    required this.documents,
    required this.elapsed,
    required this.summary,
    this.isMutation = false,
  });

  final List<Map<String, dynamic>> documents;
  final Duration elapsed;
  final String summary;
  final bool isMutation;

  int get count => documents.length;
}

/// Abstract contract for executing parsed [MqlCommand]s against MongoDB.
abstract class MongoQueryExecutor {
  Future<MongoQueryResult> execute({
    required MongoConnection connection,
    required String database,
    required MqlCommand command,
    String? defaultCollection,
  });
}

/// Production implementation of [MongoQueryExecutor] delegating to [MongoService].
class DefaultMongoQueryExecutor implements MongoQueryExecutor {
  const DefaultMongoQueryExecutor({MongoService? service})
      : _service = service;

  final MongoService? _service;

  MongoService get _effectiveService => _service ?? MongoService.instance;

  @override
  Future<MongoQueryResult> execute({
    required MongoConnection connection,
    required String database,
    required MqlCommand command,
    String? defaultCollection,
  }) async {
    final coll = command.collection ?? defaultCollection;
    final stopwatch = Stopwatch()..start();

    switch (command.method) {
      case MqlMethod.find:
        if (coll == null || coll.isEmpty) {
          throw const FormatException('find() requires a target collection');
        }
        final docs = await _effectiveService.find(
          connection,
          database,
          coll,
          filter: command.filter,
          sort: command.sort,
          limit: command.limit ?? 100,
          skip: command.skip,
        );
        stopwatch.stop();
        return MongoQueryResult(
          documents: docs,
          elapsed: stopwatch.elapsed,
          summary: 'Fetched ${docs.length} documents',
        );

      case MqlMethod.findOne:
        if (coll == null || coll.isEmpty) {
          throw const FormatException('findOne() requires a target collection');
        }
        final docs = await _effectiveService.find(
          connection,
          database,
          coll,
          filter: command.filter,
          limit: 1,
        );
        stopwatch.stop();
        return MongoQueryResult(
          documents: docs,
          elapsed: stopwatch.elapsed,
          summary: docs.isEmpty ? 'No document found' : 'Fetched 1 document',
        );

      case MqlMethod.count:
      case MqlMethod.countDocuments:
        if (coll == null || coll.isEmpty) {
          throw const FormatException('count() requires a target collection');
        }
        final count = await _effectiveService.countDocuments(
          connection,
          database,
          coll,
          filter: command.filter,
        );
        stopwatch.stop();
        return MongoQueryResult(
          documents: [{'count': count}],
          elapsed: stopwatch.elapsed,
          summary: 'Count: $count',
        );

      case MqlMethod.aggregate:
        if (coll == null || coll.isEmpty) {
          throw const FormatException('aggregate() requires a target collection');
        }
        final docs = await _effectiveService.aggregate(
          connection,
          database,
          coll,
          command.pipeline ?? [],
        );
        stopwatch.stop();
        return MongoQueryResult(
          documents: docs,
          elapsed: stopwatch.elapsed,
          summary: 'Pipeline returned ${docs.length} documents',
        );

      case MqlMethod.insertOne:
        if (coll == null || coll.isEmpty) {
          throw const FormatException('insertOne() requires a target collection');
        }
        final inserted = await _effectiveService.insertDocument(
          connection,
          database,
          coll,
          command.document ?? {},
        );
        stopwatch.stop();
        return MongoQueryResult(
          documents: [inserted],
          elapsed: stopwatch.elapsed,
          summary: 'Inserted 1 document',
          isMutation: true,
        );

      case MqlMethod.insertMany:
        if (coll == null || coll.isEmpty) {
          throw const FormatException('insertMany() requires a target collection');
        }
        final list = command.documents ?? [];
        final results = <Map<String, dynamic>>[];
        for (final doc in list) {
          final res = await _effectiveService.insertDocument(
            connection,
            database,
            coll,
            doc,
          );
          results.add(res);
        }
        stopwatch.stop();
        return MongoQueryResult(
          documents: results,
          elapsed: stopwatch.elapsed,
          summary: 'Inserted ${results.length} documents',
          isMutation: true,
        );

      case MqlMethod.updateOne:
        if (coll == null || coll.isEmpty) {
          throw const FormatException('updateOne() requires a target collection');
        }
        await _effectiveService.updateDocument(
          connection,
          database,
          coll,
          command.filter ?? {},
          command.update ?? {},
        );
        stopwatch.stop();
        return MongoQueryResult(
          documents: [{'acknowledged': true, 'ok': 1}],
          elapsed: stopwatch.elapsed,
          summary: 'Updated successfully',
          isMutation: true,
        );

      case MqlMethod.updateMany:
        if (coll == null || coll.isEmpty) {
          throw const FormatException('updateMany() requires a target collection');
        }
        final res = await _effectiveService.executeCommand(
          connection,
          database,
          <String, Object>{
            'update': coll,
            'updates': [
              {
                'q': command.filter ?? {},
                'u': command.update ?? {},
                'multi': true,
                'upsert': command.upsert,
              },
            ],
          },
        );
        stopwatch.stop();
        final n = res['nModified'] ?? res['n'] ?? 0;
        return MongoQueryResult(
          documents: [res],
          elapsed: stopwatch.elapsed,
          summary: 'Updated $n documents',
          isMutation: true,
        );

      case MqlMethod.deleteOne:
        if (coll == null || coll.isEmpty) {
          throw const FormatException('deleteOne() requires a target collection');
        }
        await _effectiveService.deleteDocument(
          connection,
          database,
          coll,
          command.filter ?? {},
        );
        stopwatch.stop();
        return MongoQueryResult(
          documents: [{'acknowledged': true, 'deletedCount': 1}],
          elapsed: stopwatch.elapsed,
          summary: 'Deleted 1 document',
          isMutation: true,
        );

      case MqlMethod.deleteMany:
        if (coll == null || coll.isEmpty) {
          throw const FormatException('deleteMany() requires a target collection');
        }
        final res = await _effectiveService.executeCommand(
          connection,
          database,
          <String, Object>{
            'delete': coll,
            'deletes': [
              {'q': command.filter ?? {}, 'limit': 0},
            ],
          },
        );
        stopwatch.stop();
        final n = res['n'] ?? 0;
        return MongoQueryResult(
          documents: [res],
          elapsed: stopwatch.elapsed,
          summary: 'Deleted $n documents',
          isMutation: true,
        );

      case MqlMethod.drop:
        if (coll == null || coll.isEmpty) {
          throw const FormatException('drop() requires a target collection');
        }
        await _effectiveService.dropCollection(
          connection,
          database,
          coll,
        );
        stopwatch.stop();
        return MongoQueryResult(
          documents: [{'dropped': coll, 'ok': 1}],
          elapsed: stopwatch.elapsed,
          summary: 'Collection "$coll" dropped',
          isMutation: true,
        );

      case MqlMethod.runCommand:
        final res = await _effectiveService.executeCommand(
          connection,
          database,
          command.commandMap ?? {},
        );
        stopwatch.stop();
        return MongoQueryResult(
          documents: [res],
          elapsed: stopwatch.elapsed,
          summary: 'Command executed in ${stopwatch.elapsedMilliseconds}ms',
        );

      case MqlMethod.getCollectionNames:
        final names = await connection.listCollections(database);
        stopwatch.stop();
        final docs = names.map((n) => {'name': n}).toList();
        return MongoQueryResult(
          documents: docs,
          elapsed: stopwatch.elapsed,
          summary: 'Found ${docs.length} collections',
        );

      case MqlMethod.stats:
        if (coll == null || coll.isEmpty) {
          throw const FormatException('stats() requires a target collection');
        }
        final stats = await _effectiveService.getCollectionStats(
          connection,
          database,
          coll,
        );
        stopwatch.stop();
        return MongoQueryResult(
          documents: [stats],
          elapsed: stopwatch.elapsed,
          summary: 'Collection stats retrieved',
        );

      case MqlMethod.unknown:
        throw const FormatException('Unknown or unsupported MQL method');
    }
  }
}
