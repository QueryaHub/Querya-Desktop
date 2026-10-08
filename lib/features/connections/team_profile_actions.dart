import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/actions/querya_command_host.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/team/team_profile.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';

const _typeGroup = XTypeGroup(label: 'Querya team profile', extensions: ['querya']);

/// Saves all connections (without passwords) to a `team-profile.querya` file.
Future<void> exportTeamProfile(BuildContext context) async {
  final connections = await LocalDb.instance.getConnections();
  if (!context.mounted) return;
  if (connections.isEmpty) {
    showAppToast(context: context, message: 'No connections to export');
    return;
  }
  final location = await getSaveLocation(
    acceptedTypeGroups: const [_typeGroup],
    suggestedName: 'team-profile.querya',
  );
  if (location == null || !context.mounted) return;
  await File(location.path).writeAsString(TeamProfileCodec.encode(connections));
  if (!context.mounted) return;
  showAppToast(
    context: context,
    message:
        'Exported ${connections.length} connection(s). Passwords are not included.',
    variant: AppToastVariant.success,
  );
}

/// Adds connections from a `team-profile.querya` file (passwords stay empty).
Future<void> importTeamProfile(BuildContext context) async {
  final file = await openFile(acceptedTypeGroups: const [_typeGroup]);
  if (file == null || !context.mounted) return;
  try {
    final rows = TeamProfileCodec.decode(utf8.decode(await file.readAsBytes()));
    final added = await TeamProfileCodec.importInto(LocalDb.instance, rows);
    if (!context.mounted) return;
    QueryaCommandHost.maybeOf(context)?.onReloadConnections?.call();
    showAppToast(
      context: context,
      message: added == 0
          ? 'Nothing new to import'
          : 'Imported $added connection(s). Enter passwords when connecting.',
      variant: AppToastVariant.success,
    );
  } on TeamProfileFormatException catch (e) {
    if (!context.mounted) return;
    showAppToast(context: context, message: e.message, variant: AppToastVariant.error);
  }
}
