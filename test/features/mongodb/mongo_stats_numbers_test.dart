import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/mongodb/mongo_stats_view.dart';

/// Stands in for bson's `Int64`: not a Dart [num], prints its value.
class _Int64Like {
  const _Int64Like(this.value);
  final int value;

  @override
  String toString() => '$value';
}

void main() {
  test('serverStatus numbers read as ints, Int64 included', () {
    expect(mongoStatInt(42), 42);
    expect(mongoStatInt(42.9), 42);
    // opcounters and network.bytesIn arrive as Int64; they used to read as 0.
    expect(mongoStatInt(const _Int64Like(577674)), 577674);
    expect(mongoStatInt(null), isNull);
    expect(mongoStatInt('not a number'), isNull);
  });
}
