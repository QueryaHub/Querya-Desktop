import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/app/app_shutdown.dart';

void main() {
  group('disconnectAllExternalServices', () {
    test('completes without open connections', () async {
      await disconnectAllExternalServices();
    });
  });
}
