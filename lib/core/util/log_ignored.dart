import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/util/querya_log.dart';

/// Records an error that the caller deliberately goes on from: a best-effort
/// close or delete, a cache that can be rebuilt. [where] names the place
/// (`'LocalExtensionInstaller.backup'`), so a failure that matters later has a
/// trace in the debug log instead of none.
void logIgnored(String where, Object error, [StackTrace? stack]) {
  debugPrint('[$where] ignored: $error');
  QueryaLog.instance.warn(where, 'ignored', error: error);
  if (stack != null && kDebugMode) debugPrint('$stack');
}
