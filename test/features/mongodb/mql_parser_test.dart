import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/mongodb/mql_parser.dart';

void main() {
  group('MqlParser', () {
    test('parses simple find with unquoted keys and string values', () {
      final cmd = MqlParser.parse('db.users.find({ status: "active" })');
      expect(cmd.method, equals(MqlMethod.find));
      expect(cmd.collection, equals('users'));
      expect(cmd.filter, equals({'status': 'active'}));
    });

    test('parses find without db prefix', () {
      final cmd = MqlParser.parse('users.find({ age: { \$gt: 21 } })');
      expect(cmd.method, equals(MqlMethod.find));
      expect(cmd.collection, equals('users'));
      expect(cmd.filter, equals({'age': {'\$gt': 21}}));
    });

    test('parses chained sort, limit, and skip', () {
      final cmd = MqlParser.parse(
        'db.orders.find({ status: "completed" }).sort({ createdAt: -1 }).skip(20).limit(50);',
      );
      expect(cmd.method, equals(MqlMethod.find));
      expect(cmd.collection, equals('orders'));
      expect(cmd.filter, equals({'status': 'completed'}));
      expect(cmd.sort, equals({'createdAt': -1}));
      expect(cmd.skip, equals(20));
      expect(cmd.limit, equals(50));
    });

    test('parses findOne with projection', () {
      final cmd = MqlParser.parse('db.users.findOne({ _id: "123" }, { name: 1, email: 1 })');
      expect(cmd.method, equals(MqlMethod.findOne));
      expect(cmd.collection, equals('users'));
      expect(cmd.filter, equals({'_id': '123'}));
      expect(cmd.projection, equals({'name': 1, 'email': 1}));
      expect(cmd.limit, equals(1));
    });

    test('parses countDocuments and count', () {
      final cmd1 = MqlParser.parse('db.logs.countDocuments({ level: "error" })');
      expect(cmd1.method, equals(MqlMethod.countDocuments));
      expect(cmd1.collection, equals('logs'));
      expect(cmd1.filter, equals({'level': 'error'}));

      final cmd2 = MqlParser.parse('db.logs.find().count()');
      expect(cmd2.method, equals(MqlMethod.count));
      expect(cmd2.collection, equals('logs'));
    });

    test('parses aggregate pipeline', () {
      final cmd = MqlParser.parse(
        'db.orders.aggregate([ { \$match: { status: "A" } }, { \$group: { _id: "\$cust_id", total: { \$sum: "\$amount" } } } ])',
      );
      expect(cmd.method, equals(MqlMethod.aggregate));
      expect(cmd.collection, equals('orders'));
      expect(cmd.pipeline?.length, equals(2));
      expect(cmd.pipeline?[0]['\$match'], equals({'status': 'A'}));
    });

    test('parses insertOne and insertMany', () {
      final cmd1 = MqlParser.parse('db.products.insertOne({ title: "Laptop", price: 999.99 })');
      expect(cmd1.method, equals(MqlMethod.insertOne));
      expect(cmd1.collection, equals('products'));
      expect(cmd1.document?['title'], equals('Laptop'));

      final cmd2 = MqlParser.parse('db.products.insertMany([ { title: "Item 1" }, { title: "Item 2" } ])');
      expect(cmd2.method, equals(MqlMethod.insertMany));
      expect(cmd2.collection, equals('products'));
      expect(cmd2.documents?.length, equals(2));
    });

    test('parses updateOne and updateMany', () {
      final cmd1 = MqlParser.parse('db.users.updateOne({ name: "Bob" }, { \$set: { age: 30 } })');
      expect(cmd1.method, equals(MqlMethod.updateOne));
      expect(cmd1.collection, equals('users'));
      expect(cmd1.filter, equals({'name': 'Bob'}));
      expect(cmd1.update, equals({'\$set': {'age': 30}}));
    });

    test('parses deleteOne and deleteMany', () {
      final cmd1 = MqlParser.parse('db.sessions.deleteOne({ expired: true })');
      expect(cmd1.method, equals(MqlMethod.deleteOne));
      expect(cmd1.collection, equals('sessions'));
      expect(cmd1.filter, equals({'expired': true}));
    });

    test('parses runCommand and getCollectionNames', () {
      final cmd1 = MqlParser.parse('db.runCommand({ ping: 1 })');
      expect(cmd1.method, equals(MqlMethod.runCommand));
      expect(cmd1.commandMap, equals({'ping': 1}));

      final cmd2 = MqlParser.parse('db.getCollectionNames()');
      expect(cmd2.method, equals(MqlMethod.getCollectionNames));
    });

    test('parses direct JSON object as command or find', () {
      final cmd1 = MqlParser.parse('{ "collStats": "users" }');
      expect(cmd1.method, equals(MqlMethod.runCommand));
      expect(cmd1.commandMap, equals({'collStats': 'users'}));

      final cmd2 = MqlParser.parse('{ "find": "users", "filter": { "active": true }, "limit": 10 }');
      expect(cmd2.method, equals(MqlMethod.find));
      expect(cmd2.collection, equals('users'));
      expect(cmd2.filter, equals({'active': true}));
      expect(cmd2.limit, equals(10));
    });

    test('handles single-quoted strings and nested objects', () {
      final cmd = MqlParser.parse("db.users.find({'profile.city': 'New York', 'tags': ['vip', 'admin']})");
      expect(cmd.method, equals(MqlMethod.find));
      expect(cmd.collection, equals('users'));
      expect(cmd.filter?['profile.city'], equals('New York'));
      expect(cmd.filter?['tags'], equals(['vip', 'admin']));
    });

    test('handles empty or whitespace query with FormatException', () {
      expect(() => MqlParser.parse(''), throwsA(isA<FormatException>()));
      expect(() => MqlParser.parse('   ;  '), throwsA(isA<FormatException>()));
    });
  });
}
