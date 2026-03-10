import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows dialog to create a new MongoDB database.
Future<String?> showCreateMongoDBDialog(material.BuildContext context) async {
  return showDialog<String>(
    context: context,
    barrierColor: material.Colors.black54,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: const material.EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: const _CreateMongoDBDialogContent(),
    ),
  );
}

class _CreateMongoDBDialogContent extends material.StatefulWidget {
  const _CreateMongoDBDialogContent();

  @override
  material.State<_CreateMongoDBDialogContent> createState() => _CreateMongoDBDialogContentState();
}

class _CreateMongoDBDialogContentState extends material.State<_CreateMongoDBDialogContent> {
  final _nameController = material.TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() => setState(() {});

  bool get _formValid => _nameController.text.trim().isNotEmpty;

  void _save() {
    if (!_formValid) return;
    material.Navigator.of(context).pop(_nameController.text.trim());
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFieldChanged);
    _nameController.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;

    return material.Container(
      constraints: const material.BoxConstraints(maxWidth: 500),
      decoration: material.BoxDecoration(
        color: theme.popover,
        borderRadius: material.BorderRadius.circular(radius),
        border: material.Border.all(color: theme.muted),
      ),
      child: material.ClipRRect(
        borderRadius: material.BorderRadius.circular(radius),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            material.Padding(
              padding: const material.EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  material.Row(
                    children: [
                      material.Icon(material.Icons.storage_rounded, size: 24, color: theme.primary),
                      const Gap(12),
                      const Text('Create Database').large().semiBold(),
                    ],
                  ),
                  const Gap(8),
                  const Text('Enter the name for the new MongoDB database.').muted().small(),
                ],
              ),
            ),
            const material.Divider(height: 1),
            material.Padding(
              padding: const material.EdgeInsets.all(24),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  const Text('Database Name').small().semiBold(),
                  const Gap(8),
                  TextField(
                    controller: _nameController,
                    placeholder: const Text('mydb'),
                  ),
                ],
              ),
            ),
            const material.Divider(height: 1),
            material.Container(
              padding: const material.EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: material.Row(
                mainAxisAlignment: material.MainAxisAlignment.end,
                children: [
                  GhostButton(
                    onPressed: () => material.Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Gap(12),
                  PrimaryButton(
                    onPressed: _formValid ? _save : null,
                    child: const Text('Create'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
