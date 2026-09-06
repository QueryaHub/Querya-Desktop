import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'xml_html_formatter.dart';

/// Language mode for Value Panel inspector.
enum ValuePanelLanguage {
  auto,
  json,
  xml,
  sql,
  text,
}

/// Collapsible right-hand side panel for inspecting cell content in detail.
class DataGridValuePanel extends material.StatefulWidget {
  const DataGridValuePanel({
    super.key,
    required this.columnName,
    required this.cellValue,
    required this.rowIndex,
    required this.onClose,
    this.onUpdateValue,
  });

  final String columnName;
  final String cellValue;
  final int? rowIndex;
  final material.VoidCallback onClose;
  final ValueChanged<String>? onUpdateValue;

  @override
  material.State<DataGridValuePanel> createState() => _DataGridValuePanelState();
}

class _DataGridValuePanelState extends material.State<DataGridValuePanel> {
  late final material.TextEditingController _controller;
  ValuePanelLanguage _selectedLanguage = ValuePanelLanguage.auto;
  String? _validationError;
  bool _wordWrap = true;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller = material.TextEditingController(text: _formatInitialValue(widget.cellValue));
    _controller.addListener(_onTextChanged);
    _validateContent();
  }

  void _onTextChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        _validateContent();
      }
    });
  }

  @override
  void didUpdateWidget(covariant DataGridValuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cellValue != widget.cellValue) {
      _debounceTimer?.cancel();
      _controller.text = _formatInitialValue(widget.cellValue);
      _validateContent();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  String _formatInitialValue(String input) {
    final trimmed = input.trim();
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        final parsed = jsonDecode(trimmed);
        return const JsonEncoder.withIndent('  ').convert(parsed);
      } catch (_) {}
    } else if (trimmed.startsWith('<') && trimmed.endsWith('>')) {
      try {
        return XmlHtmlFormatter.format(trimmed);
      } catch (_) {}
    }
    return input;
  }

  ValuePanelLanguage get _effectiveLanguage {
    if (_selectedLanguage != ValuePanelLanguage.auto) {
      return _selectedLanguage;
    }
    final trimmed = _controller.text.trim();
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      return ValuePanelLanguage.json;
    }
    if (trimmed.startsWith('<') && trimmed.endsWith('>')) {
      return ValuePanelLanguage.xml;
    }
    final upper = trimmed.toUpperCase();
    if (upper.startsWith('SELECT ') ||
        upper.startsWith('INSERT ') ||
        upper.startsWith('UPDATE ') ||
        upper.startsWith('CREATE ') ||
        upper.startsWith('WITH ')) {
      return ValuePanelLanguage.sql;
    }
    return ValuePanelLanguage.text;
  }

  void _validateContent() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      if (_validationError != null) {
        setState(() => _validationError = null);
      }
      return;
    }

    final lang = _effectiveLanguage;
    String? err;

    if (lang == ValuePanelLanguage.json) {
      try {
        jsonDecode(text);
      } catch (e) {
        err = 'Invalid JSON: $e';
      }
    } else if (lang == ValuePanelLanguage.xml) {
      err = XmlHtmlFormatter.validate(text);
    }

    if (err != _validationError) {
      setState(() => _validationError = err);
    }
  }

  void _formatCode() {
    final lang = _effectiveLanguage;
    if (lang == ValuePanelLanguage.json) {
      try {
        final parsed = jsonDecode(_controller.text);
        final pretty = const JsonEncoder.withIndent('  ').convert(parsed);
        setState(() => _controller.text = pretty);
      } catch (_) {}
    } else if (lang == ValuePanelLanguage.xml) {
      final pretty = XmlHtmlFormatter.format(_controller.text);
      setState(() => _controller.text = pretty);
    }
  }

  void _minifyCode() {
    final lang = _effectiveLanguage;
    if (lang == ValuePanelLanguage.json) {
      try {
        final parsed = jsonDecode(_controller.text);
        final compact = jsonEncode(parsed);
        setState(() => _controller.text = compact);
      } catch (_) {}
    } else if (lang == ValuePanelLanguage.xml) {
      final compact = XmlHtmlFormatter.minify(_controller.text);
      setState(() => _controller.text = compact);
    }
  }

  QueryaCodeLanguage _toQueryaLanguage(ValuePanelLanguage lang) {
    switch (lang) {
      case ValuePanelLanguage.json:
        return QueryaCodeLanguage.json;
      case ValuePanelLanguage.sql:
        return QueryaCodeLanguage.sql;
      default:
        return QueryaCodeLanguage.plain;
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeLang = _effectiveLanguage;

    return material.Container(
      width: 340,
      decoration: material.BoxDecoration(
        color: cs.card,
        border: material.Border(
          left: material.BorderSide(
            color: cs.border.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          // Panel Header
          material.Container(
            height: 36,
            padding: const material.EdgeInsets.symmetric(horizontal: 10),
            decoration: material.BoxDecoration(
              border: material.Border(
                bottom: material.BorderSide(
                  color: cs.border.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
            ),
            child: material.Row(
              children: [
                material.Icon(
                  material.Icons.data_object_rounded,
                  size: 15,
                  color: cs.primary,
                ),
                const Gap(6),
                material.Expanded(
                  child: Text(
                    '${widget.columnName}${widget.rowIndex != null ? ' [Row ${widget.rowIndex! + 1}]' : ''}',
                    maxLines: 1,
                    overflow: material.TextOverflow.ellipsis,
                  ).small().semiBold(),
                ),
                material.IconButton(
                  icon: const material.Icon(material.Icons.close, size: 14),
                  padding: material.EdgeInsets.zero,
                  constraints: const material.BoxConstraints(minWidth: 24, minHeight: 24),
                  color: cs.mutedForeground,
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          // Toolbar with language selector and actions
          material.Container(
            padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: cs.background.withValues(alpha: 0.4),
            child: material.Row(
              children: [
                // Language Dropdown / Pill
                material.DropdownButton<ValuePanelLanguage>(
                  value: _selectedLanguage,
                  isDense: true,
                  underline: const material.SizedBox(),
                  icon: const material.Icon(material.Icons.arrow_drop_down, size: 16),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                  items: const [
                    material.DropdownMenuItem(
                      value: ValuePanelLanguage.auto,
                      child: Text('Auto'),
                    ),
                    material.DropdownMenuItem(
                      value: ValuePanelLanguage.json,
                      child: Text('JSON'),
                    ),
                    material.DropdownMenuItem(
                      value: ValuePanelLanguage.xml,
                      child: Text('XML/HTML'),
                    ),
                    material.DropdownMenuItem(
                      value: ValuePanelLanguage.sql,
                      child: Text('SQL'),
                    ),
                    material.DropdownMenuItem(
                      value: ValuePanelLanguage.text,
                      child: Text('Plain Text'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedLanguage = val);
                      _validateContent();
                    }
                  },
                ),
                const Gap(6),
                if (activeLang == ValuePanelLanguage.json || activeLang == ValuePanelLanguage.xml) ...[
                  material.TextButton(
                    onPressed: _formatCode,
                    style: material.TextButton.styleFrom(
                      padding: const material.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      minimumSize: material.Size.zero,
                      tapTargetSize: material.MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Format').small(),
                  ),
                  const Gap(4),
                  material.TextButton(
                    onPressed: _minifyCode,
                    style: material.TextButton.styleFrom(
                      padding: const material.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      minimumSize: material.Size.zero,
                      tapTargetSize: material.MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Minify').small(),
                  ),
                ],
                const material.Spacer(),
                material.IconButton(
                  icon: material.Icon(
                    _wordWrap ? material.Icons.wrap_text : material.Icons.notes,
                    size: 14,
                  ),
                  padding: material.EdgeInsets.zero,
                  constraints: const material.BoxConstraints(minWidth: 24, minHeight: 24),
                  color: _wordWrap ? cs.primary : cs.mutedForeground,
                  onPressed: () => setState(() => _wordWrap = !_wordWrap),
                ),
                material.IconButton(
                  icon: const material.Icon(material.Icons.copy_rounded, size: 14),
                  padding: material.EdgeInsets.zero,
                  constraints: const material.BoxConstraints(minWidth: 24, minHeight: 24),
                  color: cs.mutedForeground,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _controller.text));
                  },
                ),
              ],
            ),
          ),

          // Validation Error Banner (if any)
          if (_validationError != null)
            material.Container(
              padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: cs.destructive.withValues(alpha: 0.12),
              child: material.Row(
                children: [
                  material.Icon(
                    material.Icons.warning_amber_rounded,
                    size: 14,
                    color: cs.destructive,
                  ),
                  const Gap(6),
                  material.Expanded(
                    child: Text(
                      _validationError!,
                      maxLines: 2,
                      overflow: material.TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: cs.destructive,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Code Editor Area with Syntax Highlighting
          material.Expanded(
            child: material.Padding(
              padding: const material.EdgeInsets.all(6),
              child: QueryaCodeEditor(
                controller: _controller,
                language: _toQueryaLanguage(activeLang),
                enableHighlighting: true,
                fontSize: 12,
                variant: QueryaCodeEditorVariant.material,
              ),
            ),
          ),

          // Apply button if editable
          if (widget.onUpdateValue != null)
            material.Container(
              padding: const material.EdgeInsets.all(8),
              decoration: material.BoxDecoration(
                border: material.Border(
                  top: material.BorderSide(
                    color: cs.border.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
              ),
              child: material.ElevatedButton(
                onPressed: () {
                  widget.onUpdateValue!(_controller.text);
                },
                style: material.ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.primaryForeground,
                  padding: const material.EdgeInsets.symmetric(vertical: 8),
                  minimumSize: material.Size.zero,
                ),
                child: const Text('Update Cell Value').small().bold(),
              ),
            ),
        ],
      ),
    );
  }
}
