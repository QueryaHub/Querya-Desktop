import 'package:querya_desktop/core/security/connection_environment.dart';

/// How long a Production connection stays writable after the user unlocks it.
const Duration kSafeModeUnlockDuration = Duration(minutes: 5);

/// Whether turning the read-only lock off for [environment] needs an explicit,
/// typed confirmation (Safe Mode).
bool safeModeRequiresConfirmation(ConnectionEnvironment? environment) =>
    environment == ConnectionEnvironment.production;

/// Text the user has to type to unlock a Production connection: the
/// connection's name, or `PRODUCTION` when it has none.
String safeModeConfirmationPhrase(String connectionName) {
  final name = connectionName.trim();
  return name.isEmpty ? 'PRODUCTION' : name;
}

/// Whether [input] unlocks a connection called [connectionName]. Surrounding
/// whitespace is ignored; the text is otherwise compared exactly.
bool isSafeModeConfirmationValid(String input, String connectionName) =>
    input.trim() == safeModeConfirmationPhrase(connectionName);
