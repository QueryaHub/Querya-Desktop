import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';

void main() {
  test('macOS secrets go to the login keychain, not the data protection one '
      '(#1586)', () {
    // What the native plugin reads: "true" (its default) needs the
    // keychain-access-groups entitlement, which the app does not have.
    expect(
      ConnectionSecretsStore.macOsOptions.toMap()['usesDataProtectionKeychain'],
      'false',
    );
  });
}
