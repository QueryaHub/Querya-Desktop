import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/database/database_error_mapper.dart';
import 'package:querya_desktop/core/mcp/mcp_redaction.dart';
import 'package:querya_desktop/core/util/querya_log.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';

/// The text a user reads for [error]: the mapped message with its hint for a
/// driver error, the error's own text otherwise, without credentials.
String describeError(Object error, {DatabaseDriver? driver}) =>
    McpRedaction.redact(describeDatabaseError(error, driver: driver));

/// The one way to tell the user that an action failed: writes the failure to
/// the log (with its stack) and shows an error toast, `<action>. <reason>`.
///
/// Use it for a failed user action. A lazy load that fails inside a tree uses
/// `TreeLoadError`, and a query uses `QueryErrorView`; they should still log
/// through [QueryaLog].
///
/// [action] is a short sentence without the final full stop (`'The connection
/// was not saved'`). [where] names the place for the log (`'saveNewConnection'`).
/// Safe to call when [context] has been unmounted: the log is still written and
/// the toast is skipped.
void reportError(
  BuildContext context,
  Object error, {
  required String where,
  required String action,
  StackTrace? stack,
  DatabaseDriver? driver,
}) {
  QueryaLog.instance.error(where, action, error: error, stack: stack);
  if (!context.mounted) return;
  showAppToast(
    context: context,
    variant: AppToastVariant.error,
    message: '$action. ${describeError(error, driver: driver)}',
  );
}

/// Logs [error] and returns `<action>: <reason>` for an inline error line (a
/// view's own error text), where a toast is not the surface. [action] is a
/// short phrase (`'Delete failed'`); [where] names the place for the log.
String failureMessage(
  String action,
  Object error, {
  required String where,
  StackTrace? stack,
  DatabaseDriver? driver,
}) {
  QueryaLog.instance.error(where, action, error: error, stack: stack);
  return '$action: ${describeError(error, driver: driver)}';
}

/// Starts [action] without waiting for it and reports its failure like
/// [reportError]. For a user action that is fired from a callback
/// (`onChanged: (v) => unawaited(_save(v))`), where a bare `unawaited` would
/// leave a failed write to the zone handler: the log only, with the control on
/// screen showing a value that was not saved.
void runReported(
  BuildContext context,
  Future<void> Function() action, {
  required String where,
  required String failedAction,
  DatabaseDriver? driver,
}) {
  unawaited(() async {
    try {
      await action();
    } catch (error, stack) {
      if (context.mounted) {
        reportError(context, error,
            where: where, action: failedAction, stack: stack, driver: driver);
      } else {
        QueryaLog.instance.error(where, failedAction, error: error, stack: stack);
      }
    }
  }());
}
