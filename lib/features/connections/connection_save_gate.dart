import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/report_error.dart';

/// Stores a connection from inside its form (#1758): the form calls it with the
/// row when the user presses Save and closes only when it returns `null`. A
/// message keeps the form open with everything the user typed and shows the
/// message, so a refused save (typically the system keyring) can be retried.
typedef ConnectionSaveGate = Future<String?> Function(ConnectionRow row);

/// The gate of the creation flows: adds the connection to the local database.
/// Returns `null` when it is stored, or the reason it is not (also logged).
Future<String?> storeNewConnection(ConnectionRow row) async {
  try {
    await LocalDb.instance.addConnection(row);
    return null;
  } catch (e, st) {
    return failureMessage(
      'The connection was not saved',
      e,
      where: 'storeNewConnection',
      stack: st,
    );
  }
}
