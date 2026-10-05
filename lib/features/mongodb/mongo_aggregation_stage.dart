import 'dart:convert';

import 'package:mongo_dart/mongo_dart.dart' show EJsonCodec;

/// Standard MongoDB aggregation stage operators with descriptions.
class MongoStageOperatorInfo {
  const MongoStageOperatorInfo(this.op, this.summary, this.template);

  final String op;
  final String summary;
  final String template;
}

const List<MongoStageOperatorInfo> kMongoStageOperators = [
  MongoStageOperatorInfo(
    r'$match',
    'Filters documents to pass only those matching criteria',
    '{\n  "status": "active"\n}',
  ),
  MongoStageOperatorInfo(
    r'$group',
    'Groups documents by a specified identifier expression',
    '{\n  "_id": r"\$category",\n  "count": {\n    r"\$sum": 1\n  }\n}',
  ),
  MongoStageOperatorInfo(
    r'$project',
    'Passes along documents with specified requested fields',
    '{\n  "_id": 1,\n  "name": 1\n}',
  ),
  MongoStageOperatorInfo(
    r'$sort',
    'Reorders the document stream by specified sort keys',
    '{\n  "createdAt": -1\n}',
  ),
  MongoStageOperatorInfo(
    r'$limit',
    'Passes the first n documents unmodified',
    '20',
  ),
  MongoStageOperatorInfo(
    r'$skip',
    'Passes along documents after skipping n documents',
    '10',
  ),
  MongoStageOperatorInfo(
    r'$lookup',
    'Performs a left outer join to an unsharded collection',
    '{\n  "from": "users",\n  "localField": "userId",\n  "foreignField": "_id",\n  "as": "user"\n}',
  ),
  MongoStageOperatorInfo(
    r'$unwind',
    'Deconstructs an array field from input documents',
    '{\n  "path": r"\$items",\n  "preserveNullAndEmptyArrays": true\n}',
  ),
  MongoStageOperatorInfo(
    r'$addFields',
    'Adds new computed fields to documents',
    '{\n  "totalWithTax": {\n    r"\$multiply": [r"\$price", 1.2]\n  }\n}',
  ),
  MongoStageOperatorInfo(
    r'$count',
    'Returns a count of documents arriving at this stage',
    '"total_records"',
  ),
  MongoStageOperatorInfo(
    r'$facet',
    'Processes multiple aggregation pipelines within a single stage',
    '{\n  "categorizedByTags": [\n    {\n      r"\$unwind": r"\$tags"\n    },\n    {\n      r"\$count": "count"\n    }\n  ]\n}',
  ),
  MongoStageOperatorInfo(
    r'$replaceRoot',
    'Replaces the input document with the specified document',
    '{\n  "newRoot": r"\$nested"\n}',
  ),
  MongoStageOperatorInfo(
    r'$set',
    r'Alias for $addFields: adds or updates fields',
    '{\n  "updated": true\n}',
  ),
  MongoStageOperatorInfo(
    r'$unset',
    'Excludes fields from documents',
    '["temporaryField", "extraData"]',
  ),
];

/// Returns the default template JSON for a given stage operator.
String templateForOperator(String op) {
  switch (op) {
    case r'$match':
      return '{\n  "status": "active"\n}';
    case r'$group':
      return '{\n  "_id": "\$category",\n  "count": {\n    "\$sum": 1\n  }\n}';
    case r'$project':
      return '{\n  "_id": 1,\n  "name": 1\n}';
    case r'$sort':
      return '{\n  "createdAt": -1\n}';
    case r'$limit':
      return '20';
    case r'$skip':
      return '10';
    case r'$lookup':
      return '{\n  "from": "users",\n  "localField": "userId",\n  "foreignField": "_id",\n  "as": "user"\n}';
    case r'$unwind':
      return '{\n  "path": "\$items",\n  "preserveNullAndEmptyArrays": true\n}';
    case r'$addFields':
      return '{\n  "totalWithTax": {\n    "\$multiply": ["\$price", 1.2]\n  }\n}';
    case r'$count':
      return '"total_records"';
    case r'$facet':
      return '{\n  "categorizedByTags": [\n    {\n      "\$unwind": "\$tags"\n    },\n    {\n      "\$count": "count"\n    }\n  ]\n}';
    case r'$replaceRoot':
      return '{\n  "newRoot": "\$nested"\n}';
    case r'$set':
      return '{\n  "updated": true\n}';
    case r'$unset':
      return '["temporaryField", "extraData"]';
    default:
      return '{\n}';
  }
}

/// Model representing a single stage in an aggregation pipeline.
class MongoAggregationStage {
  const MongoAggregationStage({
    required this.id,
    required this.operator,
    required this.queryText,
    this.isEnabled = true,
    this.executionDurationMs,
    this.outputCount,
    this.error,
  });

  final String id;
  final String operator;
  final String queryText;
  final bool isEnabled;
  final int? executionDurationMs;
  final int? outputCount;
  final String? error;

  MongoAggregationStage copyWith({
    String? id,
    String? operator,
    String? queryText,
    bool? isEnabled,
    int? executionDurationMs,
    int? outputCount,
    String? error,
    bool clearError = false,
    bool clearMetrics = false,
  }) {
    return MongoAggregationStage(
      id: id ?? this.id,
      operator: operator ?? this.operator,
      queryText: queryText ?? this.queryText,
      isEnabled: isEnabled ?? this.isEnabled,
      executionDurationMs: clearMetrics
          ? null
          : (executionDurationMs ?? this.executionDurationMs),
      outputCount:
          clearMetrics ? null : (outputCount ?? this.outputCount),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MongoAggregationStage &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          operator == other.operator &&
          queryText == other.queryText &&
          isEnabled == other.isEnabled &&
          executionDurationMs == other.executionDurationMs &&
          outputCount == other.outputCount &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
        id,
        operator,
        queryText,
        isEnabled,
        executionDurationMs,
        outputCount,
        error,
      );
}

/// Validates whether the stage query body contains valid JSON / EJSON.
/// Returns null if valid, or a descriptive error message.
String? validateStage(MongoAggregationStage stage) {
  final trimmed = stage.queryText.trim();
  if (trimmed.isEmpty) {
    return 'Stage body cannot be empty';
  }
  try {
    json.decode(trimmed);
    return null;
  } on FormatException catch (e) {
    return 'Invalid JSON: ${e.message}';
  } catch (e) {
    return 'Syntax error: $e';
  }
}

/// Parses a stage into a MongoDB aggregation stage dictionary `{ "$operator": value }`.
Map<String, dynamic> parseStage(MongoAggregationStage stage) {
  final trimmed = stage.queryText.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Stage body cannot be empty');
  }

  final decoded = json.decode(trimmed);

  // If the user pasted the full stage wrapper e.g. `{ "$match": { ... } }`
  if (decoded is Map) {
    final rawMap = Map<String, dynamic>.from(decoded);
    if (rawMap.length == 1 && rawMap.containsKey(stage.operator)) {
      return _convertEjsonMap(rawMap);
    }
    return {
      stage.operator: _convertEjsonValue(rawMap),
    };
  }

  // Scalar, string, or array value (e.g. `$limit: 20`, `$unwind: "$field"`, `$unset: ["a", "b"]`)
  return {
    stage.operator: _convertEjsonValue(decoded),
  };
}

dynamic _convertEjsonValue(dynamic value) {
  if (value is Map) {
    return _convertEjsonMap(Map<String, dynamic>.from(value));
  } else if (value is List) {
    return value.map(_convertEjsonValue).toList();
  }
  return value;
}

Map<String, dynamic> _convertEjsonMap(Map<String, dynamic> map) {
  try {
    return EJsonCodec.eJson2Doc(map);
  } catch (_) {
    return map;
  }
}

/// Builds an executable pipeline list up to [upToStageIndex] (inclusive).
/// Disabled stages are filtered out.
List<Map<String, dynamic>> buildPipeline(
  List<MongoAggregationStage> stages, {
  int? upToStageIndex,
}) {
  final effectiveStages = upToStageIndex == null
      ? stages
      : stages.sublist(0, (upToStageIndex + 1).clamp(0, stages.length));

  final pipeline = <Map<String, dynamic>>[];
  for (int i = 0; i < effectiveStages.length; i++) {
    final stage = effectiveStages[i];
    if (!stage.isEnabled) continue;
    final stageMap = parseStage(stage);
    pipeline.add(stageMap);
  }
  return pipeline;
}

/// Code generation helpers for MongoDB aggregation pipelines.
class MongoAggregationExporter {
  const MongoAggregationExporter._();

  /// Formats the pipeline into JSON array string.
  static String formatPipelineJson(List<MongoAggregationStage> stages) {
    final enabled = stages.where((s) => s.isEnabled).toList();
    final list = <Map<String, dynamic>>[];
    for (final stage in enabled) {
      try {
        final decoded = json.decode(stage.queryText.trim());
        if (decoded is Map &&
            decoded.length == 1 &&
            decoded.containsKey(stage.operator)) {
          list.add(Map<String, dynamic>.from(decoded));
        } else {
          list.add({stage.operator: decoded});
        }
      } catch (_) {
        list.add({stage.operator: stage.queryText.trim()});
      }
    }
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  /// Exports to `mongosh` / MongoDB Shell script.
  static String toMongosh({
    required String database,
    required String collection,
    required List<MongoAggregationStage> stages,
  }) {
    final pipelineJson = formatPipelineJson(stages);
    return '''// mongosh script
use('$database');

db.getCollection('$collection').aggregate($pipelineJson);
''';
  }

  /// Exports to Node.js (Official MongoDB Node Driver) code.
  static String toNodeJs({
    required String database,
    required String collection,
    required List<MongoAggregationStage> stages,
  }) {
    final pipelineJson = formatPipelineJson(stages);
    return '''// Node.js (mongodb driver)
const { MongoClient } = require('mongodb');

async function runPipeline() {
  const uri = process.env.MONGODB_URI || 'mongodb://localhost:27017';
  const client = new MongoClient(uri);

  try {
    await client.connect();
    const db = client.db('$database');
    const collection = db.collection('$collection');

    const pipeline = $pipelineJson;

    const results = await collection.aggregate(pipeline).toArray();
    console.log('Results count:', results.length);
    console.dir(results, { depth: null });
  } finally {
    await client.close();
  }
}

runPipeline().catch(console.error);
''';
  }

  /// Exports to Python (PyMongo) script.
  static String toPython({
    required String database,
    required String collection,
    required List<MongoAggregationStage> stages,
  }) {
    final pipelineJson = formatPipelineJson(stages);
    return '''# Python (pymongo)
import os
from pymongo import MongoClient

uri = os.environ.get('MONGODB_URI', 'mongodb://localhost:27017')
client = MongoClient(uri)

try:
    db = client['$database']
    collection = db['$collection']

    pipeline = $pipelineJson

    results = list(collection.aggregate(pipeline))
    print(f"Results count: {len(results)}")
    for doc in results:
        print(doc)
finally:
    client.close()
''';
  }
}
