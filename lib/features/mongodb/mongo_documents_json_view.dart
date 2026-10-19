import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/core/editor/syntax_highlight_service.dart';
import 'package:querya_desktop/features/mongodb/mongo_ejson.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';
import 'package:gap/gap.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/shared/widgets/querya_button.dart';
import 'package:querya_desktop/shared/widgets/querya_text.dart';

/// Full-page formatted Extended JSON viewer using [QueryaCodeEditor].
class MongoDocumentsJsonView extends StatefulWidget {
  const MongoDocumentsJsonView({
    super.key,
    required this.documents,
  });

  final List<Map<String, dynamic>> documents;

  @override
  State<MongoDocumentsJsonView> createState() => _MongoDocumentsJsonViewState();
}

class _MongoDocumentsJsonViewState extends State<MongoDocumentsJsonView> {
  late material.TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SyntaxHighlightService.createHighlightController(
      language: QueryaCodeLanguage.json,
      text: mongoDocumentsToEjson(widget.documents),
    );
  }

  @override
  void didUpdateWidget(covariant MongoDocumentsJsonView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.documents, widget.documents)) {
      _controller.text = mongoDocumentsToEjson(widget.documents);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copyJson() async {
    await Clipboard.setData(ClipboardData(text: _controller.text));
    if (mounted) {
      showAppToast(
        context: context,
        message: 'JSON copied to clipboard',
        variant: AppToastVariant.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    if (widget.documents.isEmpty) {
      return material.Center(
        child: const Text('No documents found').muted(),
      );
    }

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        // Action toolbar
        material.Container(
          height: 36,
          padding: const material.EdgeInsets.symmetric(horizontal: 16),
          decoration: material.BoxDecoration(
            color: cs.muted.withValues(alpha: 0.1),
            border: material.Border(
              bottom: material.BorderSide(
                color: cs.border.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              material.Icon(
                material.Icons.code_rounded,
                size: 15,
                color: cs.mutedForeground,
              ),
              const Gap(8),
              Text('${widget.documents.length} documents (Extended JSON)')
                  .muted()
                  .small(),
              const Spacer(),
              QueryaButton.secondary(
                label: 'Copy JSON',
                icon: material.Icons.copy_rounded,
                onPressed: _copyJson,
                size: QueryaControlSize.sm,
              ),
            ],
          ),
        ),
        // Code Editor
        material.Expanded(
          child: QueryaCodeEditor(
            controller: _controller,
            language: QueryaCodeLanguage.json,
            readOnly: true,
            expands: true,
          ),
        ),
      ],
    );
  }
}
