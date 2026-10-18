import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/shared/widgets/querya_button.dart';
import 'package:querya_desktop/shared/widgets/querya_dropdown.dart';
import 'package:querya_desktop/shared/widgets/querya_icon_button.dart';
import 'package:querya_desktop/shared/widgets/querya_text.dart';
import 'package:gap/gap.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Gap, TextExtension;

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
  late ValuePanelLanguage _initialDetectedLanguage;
  String? _validationError;
  bool _wordWrap = true;
  bool _preserveCompact = false;
  Timer? _debounceTimer;
  bool _isProgrammaticUpdate = false;

  static bool _isCompact(String input) {
    final trimmed = input.trim();
    return !trimmed.contains('\n') && !trimmed.contains('\r');
  }

  static ValuePanelLanguage _detectLanguage(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return ValuePanelLanguage.json;
    }
    if (trimmed.startsWith('<')) {
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

  @override
  void initState() {
    super.initState();
    _initialDetectedLanguage = _detectLanguage(widget.cellValue);
    _preserveCompact = _isCompact(widget.cellValue);
    _controller = material.TextEditingController(text: _formatInitialValue(widget.cellValue));
    _controller.addListener(_onTextChanged);
    _validateContent();
  }

  void _setControllerTextProgrammatically(String text) {
    if (_controller.text == text) return;
    _isProgrammaticUpdate = true;
    try {
      _controller.text = text;
    } finally {
      _isProgrammaticUpdate = false;
      _debounceTimer?.cancel();
    }
  }

  void _onTextChanged() {
    if (_isProgrammaticUpdate) return;
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
      _initialDetectedLanguage = _detectLanguage(widget.cellValue);
      _preserveCompact = _isCompact(widget.cellValue);
      _setControllerTextProgrammatically(_formatInitialValue(widget.cellValue));
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
    if (_isCompact(input)) {
      return input;
    }
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
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return ValuePanelLanguage.json;
    }
    if (trimmed.startsWith('<')) {
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
    if (_initialDetectedLanguage != ValuePanelLanguage.text && trimmed.isNotEmpty) {
      return _initialDetectedLanguage;
    }
    return ValuePanelLanguage.text;
  }

  String? _computeValidationError([String? textToValidate]) {
    final text = (textToValidate ?? _controller.text).trim();
    if (text.isEmpty) return null;

    final lang = _effectiveLanguage;
    if (lang == ValuePanelLanguage.json) {
      try {
        jsonDecode(text);
        return null;
      } catch (e) {
        return 'Invalid JSON: $e';
      }
    } else if (lang == ValuePanelLanguage.xml) {
      return XmlHtmlFormatter.validate(text);
    }
    return null;
  }

  void _validateContent() {
    final err = _computeValidationError();
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
        setState(() => _setControllerTextProgrammatically(pretty));
        _validateContent();
      } catch (_) {}
    } else if (lang == ValuePanelLanguage.xml) {
      final pretty = XmlHtmlFormatter.format(_controller.text);
      setState(() => _setControllerTextProgrammatically(pretty));
      _validateContent();
    }
  }

  void _minifyCode() {
    final lang = _effectiveLanguage;
    if (lang == ValuePanelLanguage.json) {
      try {
        final parsed = jsonDecode(_controller.text);
        final compact = jsonEncode(parsed);
        setState(() {
          _setControllerTextProgrammatically(compact);
          _preserveCompact = true;
        });
        _validateContent();
      } catch (_) {}
    } else if (lang == ValuePanelLanguage.xml) {
      final compact = XmlHtmlFormatter.minify(_controller.text);
      setState(() {
        _setControllerTextProgrammatically(compact);
        _preserveCompact = true;
      });
      _validateContent();
    }
  }

  void _handleUpdateValue() {
    _debounceTimer?.cancel();
    final err = _computeValidationError();
    if (err != null) {
      setState(() => _validationError = err);
      return;
    }

    String textToSave = _controller.text;
    final lang = _effectiveLanguage;

    if (_preserveCompact) {
      if (lang == ValuePanelLanguage.json) {
        try {
          final parsed = jsonDecode(textToSave);
          textToSave = jsonEncode(parsed);
        } catch (_) {}
      } else if (lang == ValuePanelLanguage.xml) {
        try {
          textToSave = XmlHtmlFormatter.minify(textToSave);
        } catch (_) {}
      }
    }

    widget.onUpdateValue?.call(textToSave);
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
    final cs = context.colors;
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
                QueryaIconButton(
                  size: QueryaControlSize.sm,
                  icon: const material.Icon(material.Icons.close, size: 14),
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
                QueryaDropdown<ValuePanelLanguage>(
                  compact: true,
                  value: _selectedLanguage,
                  items: const [
                    QueryaDropdownItem(
                        value: ValuePanelLanguage.auto, label: 'Auto'),
                    QueryaDropdownItem(
                        value: ValuePanelLanguage.json, label: 'JSON'),
                    QueryaDropdownItem(
                        value: ValuePanelLanguage.xml, label: 'XML/HTML'),
                    QueryaDropdownItem(
                        value: ValuePanelLanguage.sql, label: 'SQL'),
                    QueryaDropdownItem(
                        value: ValuePanelLanguage.text, label: 'Plain Text'),
                  ],
                  onSelected: (val) {
                    if (val != null) {
                      setState(() => _selectedLanguage = val);
                      _validateContent();
                    }
                  },
                ),
                const Gap(6),
                if (activeLang == ValuePanelLanguage.json || activeLang == ValuePanelLanguage.xml) ...[
                  QueryaButton.ghost(
 label: 'Format',
 size: QueryaControlSize.sm,
 onPressed: _formatCode,
 ),
                  const Gap(4),
                  QueryaButton.ghost(
 label: 'Minify',
 size: QueryaControlSize.sm,
 onPressed: _minifyCode,
 ),
                ],
                const material.Spacer(),
                QueryaIconButton(
                  size: QueryaControlSize.sm,
                  icon: material.Icon(
                    _wordWrap ? material.Icons.wrap_text : material.Icons.notes,
                    size: 14,
                  ),
                  isActive: _wordWrap,
                  onPressed: () => setState(() => _wordWrap = !_wordWrap),
                ),
                QueryaIconButton(
                  size: QueryaControlSize.sm,
                  icon: const material.Icon(material.Icons.copy_rounded, size: 14),
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
              child: material.Column(
                mainAxisSize: material.MainAxisSize.min,
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  if (activeLang == ValuePanelLanguage.json || activeLang == ValuePanelLanguage.xml) ...[
                    material.Padding(
                      padding: const material.EdgeInsets.only(bottom: 6),
                      child: material.Row(
                        children: [
                          material.SizedBox(
                            height: 18,
                            width: 18,
                            child: material.Checkbox(
                              value: _preserveCompact,
                              onChanged: (val) {
                                setState(() => _preserveCompact = val ?? false);
                              },
                              materialTapTargetSize: material.MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const Gap(6),
                          material.GestureDetector(
                            onTap: () {
                              setState(() => _preserveCompact = !_preserveCompact);
                            },
                            child: Text(
                              'Preserve compact formatting',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.foreground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  QueryaButton.primary(
 label: 'Update Cell Value',
 size: QueryaControlSize.sm,
 onPressed: _validationError != null ? null : _handleUpdateValue,
 ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
