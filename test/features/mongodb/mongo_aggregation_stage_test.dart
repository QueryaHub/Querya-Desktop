import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/mongodb/mongo_aggregation_stage.dart';

void main() {
  group('MongoAggregationStage and pipeline helpers', () {
    test('validateStage returns null on valid JSON and error string on invalid JSON', () {
      const validStage = MongoAggregationStage(
        id: 's1',
        operator: r'$match',
        queryText: '{"status": "active"}',
      );
      expect(validateStage(validStage), isNull);

      const emptyStage = MongoAggregationStage(
        id: 's2',
        operator: r'$match',
        queryText: '   ',
      );
      expect(validateStage(emptyStage), contains('cannot be empty'));

      const invalidJsonStage = MongoAggregationStage(
        id: 's3',
        operator: r'$match',
        queryText: '{"status": active}',
      );
      expect(validateStage(invalidJsonStage), contains('Invalid JSON'));
    });

    test('parseStage correctly parses map stage bodies', () {
      const stage = MongoAggregationStage(
        id: 's1',
        operator: r'$match',
        queryText: '{"status": "active", "count": {"\$gt": 5}}',
      );
      final parsed = parseStage(stage);
      expect(parsed, contains(r'$match'));
      final body = parsed[r'$match'] as Map<String, dynamic>;
      expect(body['status'], equals('active'));
      expect(body['count'], equals({r'$gt': 5}));
    });

    test('parseStage unwraps redundant outer operator if user provided it', () {
      const stage = MongoAggregationStage(
        id: 's1',
        operator: r'$match',
        queryText: '{"\$match": {"status": "active"}}',
      );
      final parsed = parseStage(stage);
      expect(parsed, equals({
        r'$match': {'status': 'active'},
      }));
    });

    test('parseStage handles scalar values for limit/skip/count', () {
      const limitStage = MongoAggregationStage(
        id: 's1',
        operator: r'$limit',
        queryText: '25',
      );
      expect(parseStage(limitStage), equals({r'$limit': 25}));

      const countStage = MongoAggregationStage(
        id: 's2',
        operator: r'$count',
        queryText: '"total_records"',
      );
      expect(parseStage(countStage), equals({r'$count': 'total_records'}));

      const unsetStage = MongoAggregationStage(
        id: 's3',
        operator: r'$unset',
        queryText: '["fieldA", "fieldB"]',
      );
      expect(parseStage(unsetStage), equals({
        r'$unset': ['fieldA', 'fieldB'],
      }));
    });

    test('buildPipeline filters disabled stages and supports upToStageIndex', () {
      final stages = [
        const MongoAggregationStage(
          id: 's1',
          operator: r'$match',
          queryText: '{"active": true}',
          isEnabled: true,
        ),
        const MongoAggregationStage(
          id: 's2',
          operator: r'$group',
          queryText: '{"_id": "\$role", "total": {"\$sum": 1}}',
          isEnabled: false,
        ),
        const MongoAggregationStage(
          id: 's3',
          operator: r'$sort',
          queryText: '{"total": -1}',
          isEnabled: true,
        ),
        const MongoAggregationStage(
          id: 's4',
          operator: r'$limit',
          queryText: '5',
          isEnabled: true,
        ),
      ];

      // Full pipeline skips s2 (disabled)
      final fullPipeline = buildPipeline(stages);
      expect(fullPipeline.length, equals(3));
      expect(fullPipeline[0], contains(r'$match'));
      expect(fullPipeline[1], contains(r'$sort'));
      expect(fullPipeline[2], contains(r'$limit'));

      // Up to stage index 1 (s1, s2): only s1 is enabled
      final partialPipeline = buildPipeline(stages, upToStageIndex: 1);
      expect(partialPipeline.length, equals(1));
      expect(partialPipeline.first, contains(r'$match'));
    });

    test('MongoAggregationExporter formats valid snippets for mongosh, node and python', () {
      final stages = [
        const MongoAggregationStage(
          id: 's1',
          operator: r'$match',
          queryText: '{"status": "published"}',
          isEnabled: true,
        ),
        const MongoAggregationStage(
          id: 's2',
          operator: r'$limit',
          queryText: '10',
          isEnabled: true,
        ),
      ];

      final mongoshCode = MongoAggregationExporter.toMongosh(
        database: 'my_db',
        collection: 'articles',
        stages: stages,
      );
      expect(mongoshCode, contains("use('my_db');"));
      expect(mongoshCode, contains("db.getCollection('articles').aggregate("));
      expect(mongoshCode, contains(r'$match'));

      final nodeCode = MongoAggregationExporter.toNodeJs(
        database: 'my_db',
        collection: 'articles',
        stages: stages,
      );
      expect(nodeCode, contains("client.db('my_db')"));
      expect(nodeCode, contains("db.collection('articles')"));
      expect(nodeCode, contains("collection.aggregate(pipeline).toArray()"));

      final pythonCode = MongoAggregationExporter.toPython(
        database: 'my_db',
        collection: 'articles',
        stages: stages,
      );
      expect(pythonCode, contains("client['my_db']"));
      expect(pythonCode, contains("db['articles']"));
      expect(pythonCode, contains("list(collection.aggregate(pipeline))"));
    });
  });
}
