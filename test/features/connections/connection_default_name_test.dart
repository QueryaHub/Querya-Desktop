import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/connections/connection_default_name.dart';

String _name(String label, int port, String uri) => defaultConnectionName(
      label: label,
      defaultPort: port,
      uri: uri,
      fields: '$label localhost:$port',
    );

void main() {
  test('a URI names the connection after its host and port', () {
    expect(_name('Redis', 6379, 'redis://:p@cache.example.com:6380'),
        'Redis: cache.example.com:6380');
    expect(_name('MySQL', 3306, 'mysql://u:p@my.example.com:3307/app'),
        'MySQL: my.example.com:3307');
    expect(_name('MongoDB', 27017, 'mongodb://u:p@mongo.example.com:27018/app'),
        'MongoDB: mongo.example.com:27018');
  });

  test('a URI without a port uses the type default', () {
    expect(_name('Redis', 6379, 'redis://cache.example.com'),
        'Redis: cache.example.com:6379');
  });

  test('a +srv URI has no port', () {
    expect(_name('MongoDB', 27017, 'mongodb+srv://u:p@c0.example.net/db'),
        'MongoDB: c0.example.net');
  });

  test('a URI without a host falls back to (URI)', () {
    expect(_name('Redis', 6379, 'not a uri'), 'Redis (URI)');
  });

  test('without a URI the name comes from the fields', () {
    expect(_name('Redis', 6379, '  '), 'Redis localhost:6379');
  });
}
