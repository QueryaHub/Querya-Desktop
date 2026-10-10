import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'querya_code_language.dart';
import 'querya_highlight_controller.dart';
import 'syntax_highlight_service.dart';

/// Shadcn vs Material [TextField] backend for different parent widgets.
enum QueryaCodeEditorVariant {
  shadcn,
  material,
}

/// Unified code editor with optional syntax highlighting (SQL/JSON).
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
    this.enableHighlighting = true,
    this.autofocus = false,
    this.focusNode,
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

  /// When true and [language] is SQL/JSON, uses [syntax_highlight] if initialized.
  final bool enableHighlighting;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<QueryaCodeEditor> createState() => _QueryaCodeEditorState();
}

class _QueryaCodeEditorState extends State<QueryaCodeEditor> {
  material.TextEditingController? _internalController;
  QueryaEditorTheme? _lastEditorTheme;
  int _lastTokenColorsHash = 0;

  material.TextEditingController get _effectiveController =>
      widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    _initControllerIfNeeded();
    _attachListener();
  }

  void _initControllerIfNeeded() {
    if (widget.controller == null) {
      _internalController = material.TextEditingController();
    }
  }

  void _attachListener() {
    _effectiveController.addListener(_onTextChanged);
  }

  void _detachListener([material.TextEditingController? target]) {
    (target ?? _effectiveController).removeListener(_onTextChanged);
  }

  void _onTextChanged() {
    widget.onChanged?.call(_effectiveController.text);
  }

  void _syncThemeIfNeeded(
    QueryaTheme queryaTheme, {
    bool transitioning = false,
  }) {
    final controller = _effectiveController;
    if (controller is! QueryaHighlightController) return;

    // Mid-animation themes differ on every frame: building highlighters for
    // them each time is wasted work and pushes real entries out of the pair
    // cache. The final frame arrives with `transitioning` false (#1358).
    if (transitioning && _lastEditorTheme != null) return;

    final editor = queryaTheme.editor;
    final tokenHash = queryaTheme.tokenColorsHash;
    if (_lastEditorTheme == editor && _lastTokenColorsHash == tokenHash) {
      return;
    }

    _lastEditorTheme = editor;
    _lastTokenColorsHash = tokenHash;

    final pair = SyntaxHighlightService.createPair(
      language: controller.language,
      queryaTheme: queryaTheme,
    );

    controller.updateTheme(
      lightHighlighter: pair.light,
      darkHighlighter: pair.dark,
      lightThemeConfig: pair.lightThemeConfig,
      darkThemeConfig: pair.darkThemeConfig,
      wrapperColor: editor.foreground,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncThemeIfNeeded(
      context.queryaTheme,
      transitioning: QueryaThemeScope.isTransitioning(context),
    );
  }

  @override
  void didUpdateWidget(QueryaCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachListener(oldWidget.controller ?? _internalController);
      if (oldWidget.controller == null && widget.controller != null) {
        _internalController?.dispose();
        _internalController = null;
      } else if (widget.controller == null && _internalController == null) {
        _internalController = material.TextEditingController();
      }
      _lastEditorTheme = null;
      _lastTokenColorsHash = 0;
      _attachListener();
      _syncThemeIfNeeded(
        context.queryaTheme,
        transitioning: QueryaThemeScope.isTransitioning(context),
      );
    }
  }

  @override
  void dispose() {
    _detachListener();
    _internalController?.dispose();
    super.dispose();
  }

  material.TextStyle _textStyle(QueryaEditorTheme editor) {
    final size = widget.fontSize ?? editor.fontSize;
    return material.TextStyle(
      fontFamily: editor.fontFamily,
      fontFamilyFallback: editor.fontFamilyFallback,
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
    final controller = _effectiveController;

    if (widget.variant == QueryaCodeEditorVariant.material) {
      return material.TextField(
        controller: controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        readOnly: widget.readOnly,
        maxLines: widget.expands ? null : widget.maxLines,
        expands: widget.expands,
        style: style,
        textAlignVertical: widget.textAlignVertical,
        decoration: material.InputDecoration(
          border: material.InputBorder.none,
          hintText: widget.hintText,
          contentPadding:
              widget.contentPadding ?? const material.EdgeInsets.all(12),
        ),
        onChanged: widget.onChanged,
      );
    }

    return TextField(
      controller: controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      readOnly: widget.readOnly,
      maxLines: widget.expands ? null : widget.maxLines,
      expands: widget.expands,
      style: style,
      placeholder: placeholder,
      onChanged: widget.onChanged,
    );
  }
}
