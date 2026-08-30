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

  @override
  State<QueryaCodeEditor> createState() => _QueryaCodeEditorState();
}

class _QueryaCodeEditorState extends State<QueryaCodeEditor> {
  material.TextEditingController? _plainController;
  QueryaHighlightController? _highlightController;
  bool _ownsPlainController = false;
  bool _ownsHighlightController = false;
  bool _syncing = false;
  QueryaEditorTheme? _highlightEditorTheme;
  QueryaCodeLanguage? _highlightLanguage;
  int _highlightTokenColorsHash = 0;

  material.TextEditingController get _activeController =>
      _highlightController ?? _plainController!;

  bool get _useHighlighting =>
      widget.enableHighlighting &&
      widget.language != QueryaCodeLanguage.plain &&
      SyntaxHighlightService.isInitialized;

  @override
  void initState() {
    super.initState();
    if (!_useHighlighting) {
      _initPlainController(widget.controller);
      _plainController!.addListener(_onTextChanged);
    }
  }

  void _initPlainController(material.TextEditingController? external) {
    if (external == null) {
      _plainController = material.TextEditingController();
      _ownsPlainController = true;
    } else {
      _plainController = external;
      _ownsPlainController = false;
    }
  }

  void _onTextChanged() {
    widget.onChanged?.call(_activeController.text);
  }

  void _syncFromExternal() {
    final external = widget.controller;
    final highlight = _highlightController;
    if (external == null || highlight == null || _syncing) return;
    if (external.text == highlight.text &&
        external.selection == highlight.selection) {
      return;
    }
    _syncing = true;
    highlight.value = external.value;
    _syncing = false;
  }

  void _syncToExternal() {
    final external = widget.controller;
    final highlight = _highlightController;
    if (external == null || highlight == null || _syncing) return;
    if (external.text == highlight.text &&
        external.selection == highlight.selection) {
      return;
    }
    _syncing = true;
    external.value = highlight.value;
    _syncing = false;
  }

  void _disposeHighlight() {
    final highlight = _highlightController;
    if (highlight == null) return;
    highlight.removeListener(_onTextChanged);
    highlight.removeListener(_syncToExternal);
    widget.controller?.removeListener(_syncFromExternal);
    if (_ownsHighlightController) {
      highlight.dispose();
    }
    _highlightController = null;
    _highlightEditorTheme = null;
    _highlightLanguage = null;
    _highlightTokenColorsHash = 0;
  }

  void _ensureHighlightController(QueryaTheme queryaTheme) {
    if (!_useHighlighting) return;

    final editor = queryaTheme.editor;
    final tokenHash = Object.hashAll(queryaTheme.tokenColors);
    if (_highlightController != null &&
        _highlightEditorTheme == editor &&
        _highlightLanguage == widget.language &&
        _highlightTokenColorsHash == tokenHash) {
      return;
    }

    final pair = SyntaxHighlightService.createPair(
      language: widget.language,
      queryaTheme: queryaTheme,
    );

    final external = widget.controller;
    final text = external?.text ?? _highlightController?.text ?? '';

    _disposeHighlight();

    _highlightController = QueryaHighlightController(
      text: text,
      language: widget.language,
      lightHighlighter: pair.light,
      darkHighlighter: pair.dark,
      lightThemeConfig: pair.lightThemeConfig,
      darkThemeConfig: pair.darkThemeConfig,
      grammarJson: pair.grammarJson,
      wrapperColor: editor.foreground,
    );
    _ownsHighlightController = external == null;
    _highlightEditorTheme = editor;
    _highlightLanguage = widget.language;
    _highlightTokenColorsHash = tokenHash;

    _highlightController!.addListener(_onTextChanged);
    if (external != null) {
      external.addListener(_syncFromExternal);
      _highlightController!.addListener(_syncToExternal);
    }
  }

  void _switchToPlain(material.TextEditingController? external) {
    _disposeHighlight();
    final text = external?.text ?? _plainController?.text ?? '';
    if (_plainController != null) {
      _plainController!.removeListener(_onTextChanged);
      if (_ownsPlainController) {
        _plainController!.dispose();
      }
    }
    _initPlainController(external);
    if (_ownsPlainController && text.isNotEmpty) {
      _plainController!.text = text;
    }
    _plainController!.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final queryaTheme = context.queryaTheme;
    if (_useHighlighting) {
      if (_plainController != null) {
        _plainController!.removeListener(_onTextChanged);
        if (_ownsPlainController) {
          _plainController!.dispose();
        }
        _plainController = null;
        _ownsPlainController = false;
      }
      _ensureHighlightController(queryaTheme);
    } else if (_highlightController != null) {
      _highlightController!.removeListener(_onTextChanged);
      _switchToPlain(widget.controller);
    } else if (_plainController == null) {
      _initPlainController(widget.controller);
      _plainController!.addListener(_onTextChanged);
    }
  }

  @override
  void didUpdateWidget(QueryaCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _highlightController?.removeListener(_onTextChanged);
      _plainController?.removeListener(_onTextChanged);
      _disposeHighlight();
      if (_plainController != null) {
        _plainController!.removeListener(_onTextChanged);
        if (_ownsPlainController) {
          _plainController!.dispose();
        }
        _plainController = null;
      }
      if (_useHighlighting) {
        _ensureHighlightController(context.queryaTheme);
        _highlightController!.addListener(_onTextChanged);
      } else {
        _initPlainController(widget.controller);
        _plainController!.addListener(_onTextChanged);
      }
    } else if (oldWidget.language != widget.language ||
        oldWidget.enableHighlighting != widget.enableHighlighting) {
      _highlightEditorTheme = null;
      _highlightLanguage = null;
      _highlightTokenColorsHash = 0;
      if (_useHighlighting) {
        _ensureHighlightController(context.queryaTheme);
      } else {
        _switchToPlain(widget.controller);
      }
    }
  }

  @override
  void dispose() {
    _disposeHighlight();
    if (_plainController != null) {
      _plainController!.removeListener(_onTextChanged);
      if (_ownsPlainController) {
        _plainController!.dispose();
      }
    }
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
    if (_useHighlighting) {
      _ensureHighlightController(context.queryaTheme);
    }

    final editor = context.editorTheme;
    final style = _textStyle(editor);
    final placeholder = _resolvedPlaceholder();
    final controller = _highlightController ?? _plainController!;

    if (widget.variant == QueryaCodeEditorVariant.material) {
      return material.TextField(
        controller: controller,
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
      readOnly: widget.readOnly,
      maxLines: widget.expands ? null : widget.maxLines,
      expands: widget.expands,
      style: style,
      placeholder: placeholder,
      onChanged: widget.onChanged,
    );
  }
}
