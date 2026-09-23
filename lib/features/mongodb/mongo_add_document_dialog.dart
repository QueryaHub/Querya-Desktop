import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/features/mongodb/mongo_ejson.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const kDefaultDraftMongoDocument = '{\n  \n}';

/// Shows a dialog to create and insert a new MongoDB document.
Future<Map<String, dynamic>?> showMongoAddDocumentDialog(
  material.BuildContext context, {
  required String database,
  required String collection,
  String initialTemplate = kDefaultDraftMongoDocument,
}) async {
  return showAppDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: MongoAddDocumentDialog(
        database: database,
        collection: collection,
        initialTemplate: initialTemplate,
      ),
    ),
  );
}

class MongoAddDocumentDialog extends material.StatefulWidget {
  const MongoAddDocumentDialog({
    super.key,
    required this.database,
    required this.collection,
    this.initialTemplate = kDefaultDraftMongoDocument,
  });

  final String database;
  final String collection;
  final String initialTemplate;

  @override
  material.State<MongoAddDocumentDialog> createState() =>
      _MongoAddDocumentDialogState();
}

class _MongoAddDocumentDialogState extends material.State<MongoAddDocumentDialog> {
  late final material.TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = material.TextEditingController(text: widget.initialTemplate);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_error != null) {
      setState(() => _error = null);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Document cannot be empty');
      return;
    }

    try {
      final doc = mongoDocumentFromEjson(text);
      material.Navigator.of(context).pop(doc);
    } catch (e) {
      setState(() {
        _error = 'Invalid EJSON syntax: $e';
      });
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = context.colors;
    final editorTheme = context.editorTheme;

    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(context, maxWidth: 640),
      borderColor: theme.muted,
      child: material.SingleChildScrollView(
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
                    material.Icon(material.Icons.post_add_rounded,
                        size: 24, color: theme.primary),
                    const Gap(12),
                    const Text('Add Document').large().semiBold(),
                  ],
                ),
                const Gap(8),
                Text('Insert a new document into ${widget.database}.${widget.collection}.')
                    .muted()
                    .small(),
              ],
            ),
          ),
          const material.Divider(height: 1),
          if (_error != null) ...[
            material.Container(
              padding: const material.EdgeInsets.symmetric(
                  horizontal: 24, vertical: 10),
              color: theme.destructive.withValues(alpha: 0.1),
              child: Row(
                children: [
                  material.Icon(material.Icons.error_outline_rounded,
                      size: 16, color: theme.destructive),
                  const Gap(8),
                  material.Expanded(
                    child: Text(
                      _error!,
                      style: material.TextStyle(
                          color: theme.destructive, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const material.Divider(height: 1),
          ],
          material.Padding(
            padding: const material.EdgeInsets.all(24),
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                const Text('Document (Extended JSON)').small().semiBold(),
                const Gap(8),
                material.Container(
                  height: 180,
                  decoration: material.BoxDecoration(
                    color: editorTheme.background,
                    borderRadius: material.BorderRadius.circular(6),
                    border: material.Border.all(
                      color: _error != null
                          ? theme.destructive
                          : theme.border.withValues(alpha: 0.4),
                    ),
                  ),
                  child: QueryaCodeEditor(
                    controller: _controller,
                    language: QueryaCodeLanguage.json,
                    fontSize: 13,
                    variant: QueryaCodeEditorVariant.material,
                    contentPadding: const material.EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          const material.Divider(height: 1),
          material.Container(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 24, vertical: 16),
            child: material.Row(
              mainAxisAlignment: material.MainAxisAlignment.end,
              children: [
                GhostButton(
                  onPressed: () => material.Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Gap(12),
                PrimaryButton(
                  onPressed: _submit,
                  leading:
                      const material.Icon(material.Icons.add_rounded, size: 16),
                  child: const Text('Insert Document'),
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
