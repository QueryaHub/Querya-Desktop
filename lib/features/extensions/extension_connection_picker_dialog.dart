import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';
import 'package:querya_desktop/features/connections/driver_icon.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Prompts the user to pick which of several equally-live connections an
/// ambiguous extension command should target (#892), instead of silently
/// running against whichever one happens to be first.
Future<int?> showExtensionConnectionPickerDialog({
  required BuildContext context,
  required String extensionName,
  required String commandTitle,
  required List<ConnectionRow> connections,
}) {
  return showAppDialog<int?>(
    context: context,
    builder: (dialogContext) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(dialogContext),
      child: _ExtensionConnectionPickerDialog(
        extensionName: extensionName,
        commandTitle: commandTitle,
        connections: connections,
      ),
    ),
  );
}

class _ExtensionConnectionPickerDialog extends material.StatelessWidget {
  const _ExtensionConnectionPickerDialog({
    required this.extensionName,
    required this.commandTitle,
    required this.connections,
  });

  final String extensionName;
  final String commandTitle;
  final List<ConnectionRow> connections;

  @override
  material.Widget build(material.BuildContext context) {
    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: 420,
        minWidth: 320,
        maxHeight: 420,
      ),
      child: material.Padding(
        padding: const material.EdgeInsets.all(16),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            Text('Select a $extensionName connection').semiBold().large(),
            const Gap(6),
            Text(
              'Multiple $extensionName connections are open. Choose which one '
              'should run "$commandTitle".',
            ).muted().small(),
            const Gap(12),
            material.Flexible(
              child: material.ListView.separated(
                shrinkWrap: true,
                itemCount: connections.length,
                separatorBuilder: (_, __) => const Gap(4),
                itemBuilder: (context, index) {
                  final connection = connections[index];
                  return material.InkWell(
                    key: material.ValueKey('extension_picker_${connection.id}'),
                    borderRadius: material.BorderRadius.circular(8),
                    onTap: () =>
                        material.Navigator.of(context).pop(connection.id),
                    child: material.Padding(
                      padding: const material.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      child: material.Row(
                        children: [
                          DriverIcon(
                            size: 18,
                            fallbackIcon:
                                QueryaIcons.connectionIcon(connection.type),
                            assetPath:
                                QueryaIcons.connectionAsset(connection.type),
                          ),
                          const Gap(10),
                          material.Expanded(
                            child: Text(connection.name).small(),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Gap(12),
            material.Align(
              alignment: material.Alignment.centerRight,
              child: OutlineButton(
                onPressed: () => material.Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
