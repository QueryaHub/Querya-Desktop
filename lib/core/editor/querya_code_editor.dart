import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'querya_code_language.dart';

/// Shadcn vs Material [TextField] backend for different parent widgets.
enum QueryaCodeEditorVariant {
  shadcn,
  material,
}

/// Unified code editor (MVP: plain [TextField]; highlighting in #49+).
class QueryaCodeEditor extends StatefulWidget {
  const QueryaCodeEditor({
    super.key,
    this.controller,
    this.language = QueryaCodeLanguage.plain,
    this.fontSize,
    this.readOnly = false,
    this.onChanged,
    this.placeholder,
    this.variant = QueryaCodeEditorVariant.shadcn,
    this.expands = true,
    this.maxLines,
    this.hintText,
    this.contentPadding,
    this.textAlignVertical,
  });

  final material.TextEditingController? controller;
  final QueryaCodeLanguage language;
  final double? fontSize;

  /// When null, uses [QueryaEditorTheme.fontSize] from scope.
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final Widget? placeholder;
  final QueryaCodeEditorVariant variant;
  final bool expands;
  final int? maxLines;
  final String? hintText;
  final material.EdgeInsetsGeometry? contentPadding;
  final material.TextAlignVertical? textAlignVertical;

  @override
  State<QueryaCodeEditor> createState() => _QueryaCodeEditorState();
}

class _QueryaCodeEditorState extends State<QueryaCodeEditor> {
  late material.TextEditingController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _initController(widget.controller);
    _controller.addListener(_onTextChanged);
  }

  void _initController(material.TextEditingController? external) {
    if (external == null) {
      _controller = material.TextEditingController();
      _ownsController = true;
    } else {
      _controller = external;
      _ownsController = false;
    }
  }

  void _onTextChanged() {
    widget.onChanged?.call(_controller.text);
  }

  @override
  void didUpdateWidget(QueryaCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onTextChanged);
      if (_ownsController) {
        _controller.dispose();
      }
      _initController(widget.controller);
      _controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  material.TextStyle _textStyle(QueryaEditorTheme editor) {
    final size = widget.fontSize ?? editor.fontSize;
    return material.TextStyle(
      fontFamily: editor.fontFamily,
      fontSize: size,
      color: editor.foreground,
      height: widget.language == QueryaCodeLanguage.json ? 1.5 : null,
    );
  }

  Widget? _resolvedPlaceholder() {
    if (widget.placeholder != null) return widget.placeholder;
    return switch (widget.language) {
      QueryaCodeLanguage.sql => const Text(
          '-- Enter SQL here…\nSELECT 1;',
        ),
      QueryaCodeLanguage.json => const Text('{ }'),
      QueryaCodeLanguage.plain => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.editorTheme;
    final style = _textStyle(editor);
    final placeholder = _resolvedPlaceholder();

    if (widget.variant == QueryaCodeEditorVariant.material) {
      return material.TextField(
        controller: _controller,
        readOnly: widget.readOnly,
        maxLines: widget.expands ? null : widget.maxLines,
        expands: widget.expands,
        style: style,
        textAlignVertical: widget.textAlignVertical,
        decoration: material.InputDecoration(
          border: material.InputBorder.none,
          hintText: widget.hintText,
          contentPadding: widget.contentPadding ??
              const material.EdgeInsets.all(12),
        ),
        onChanged: widget.onChanged,
      );
    }

    return TextField(
      controller: _controller,
      readOnly: widget.readOnly,
      maxLines: widget.expands ? null : widget.maxLines,
      expands: widget.expands,
      style: style,
      placeholder: placeholder,
      onChanged: widget.onChanged,
    );
  }
}
