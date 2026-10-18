import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/shared/widgets/querya_button.dart';

/// The text input of the kit (#1733, epic #1465): one field for every form.
///
/// A single-line field has the height of a [QueryaControlSize] (the nearest
/// [QueryaControlScope], else `md`), so a field and a button in one row line
/// up; a field with `maxLines` above 1 (or `minLines`, or `expands`) grows
/// with its text. The border takes the accent while the field has the
/// keyboard and the destructive colour with an [errorText].
///
/// [leading] and [trailing] hold an icon or a small button; with
/// [obscureText] a show / hide button is the trailing slot unless [trailing]
/// is given.
class QueryaTextField extends material.StatefulWidget {
  const QueryaTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.size,
    this.leading,
    this.trailing,
    this.errorText,
    this.style,
    this.textAlignVertical,
    this.framed = true,
    this.textAlign = material.TextAlign.start,
    this.autocorrect = true,
    this.contentPadding,
  });

  final material.TextEditingController? controller;
  final material.FocusNode? focusNode;

  /// Hint text shown while the field is empty.
  final String? placeholder;
  final material.ValueChanged<String>? onChanged;
  final material.ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;

  /// Hides the text; a trailing button reveals it.
  final bool obscureText;

  /// One line by default; null or more for a multi-line field.
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final material.TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final material.TextInputAction? textInputAction;

  /// Control size; without one the nearest [QueryaControlScope], else `md`.
  final QueryaControlSize? size;
  final material.Widget? leading;
  final material.Widget? trailing;

  /// Shown under the field in the destructive colour; also turns the border.
  final String? errorText;

  /// Text style; the size and colour of the field by default.
  final material.TextStyle? style;
  final material.TextAlignVertical? textAlignVertical;

  /// False for a field inside a frame of its own (an editor card): no fill,
  /// border or padding.
  final bool framed;
  final material.TextAlign textAlign;
  final bool autocorrect;

  /// Replaces the padding between the border and the text.
  final material.EdgeInsetsGeometry? contentPadding;

  @override
  material.State<QueryaTextField> createState() => _QueryaTextFieldState();
}

class _QueryaTextFieldState extends material.State<QueryaTextField> {
  late material.FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _focused = false;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _attachFocusNode();
  }

  void _attachFocusNode() {
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? material.FocusNode();
    _focused = _focusNode.hasFocus;
    _focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant QueryaTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_onFocus);
      if (_ownsFocusNode) _focusNode.dispose();
      _attachFocusNode();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  bool get _multiline =>
      widget.expands ||
      widget.maxLines == null ||
      widget.maxLines! > 1 ||
      (widget.minLines ?? 1) > 1;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = context.colors;
    final size = widget.size ?? QueryaControlSize.of(context);
    final fontSize = size.scaledFontSize(context);
    final hasError = widget.errorText != null;
    final muted = cs.mutedForeground;

    material.Widget? trailing = widget.trailing;
    if (trailing == null && widget.obscureText) {
      trailing = QueryaButton.icon(
        icon: _revealed
            ? material.Icons.visibility_outlined
            : material.Icons.visibility_off_outlined,
        tooltip: _revealed ? 'Hide' : 'Show',
        size: QueryaControlSize.sm,
        onPressed: widget.enabled
            ? () => setState(() => _revealed = !_revealed)
            : null,
      );
    }

    final field = material.TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText && !_revealed,
      autocorrect: widget.autocorrect,
      textAlign: widget.textAlign,
      maxLines: widget.expands ? null : (widget.obscureText ? 1 : widget.maxLines),
      minLines: widget.expands ? null : widget.minLines,
      expands: widget.expands,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textAlignVertical: widget.textAlignVertical ??
          (_multiline ? material.TextAlignVertical.top : null),
      style: material.TextStyle(
        fontSize: fontSize,
        color: widget.enabled ? cs.foreground : muted,
      ).merge(widget.style),
      cursorColor: cs.primary,
      decoration: material.InputDecoration(
        hintText: widget.placeholder,
        hintStyle: material.TextStyle(
            fontSize: widget.style?.fontSize ?? fontSize, color: muted),
        isDense: true,
        border: material.InputBorder.none,
        enabledBorder: material.InputBorder.none,
        focusedBorder: material.InputBorder.none,
        disabledBorder: material.InputBorder.none,
        errorBorder: material.InputBorder.none,
        contentPadding: widget.contentPadding ??
            (widget.framed
                ? material.EdgeInsets.symmetric(
                    vertical: _multiline ? 8 : 0,
                    horizontal: widget.leading == null ? 10 : 0,
                  )
                : material.EdgeInsets.zero),
      ),
    );

    material.Widget content = widget.framed
        ? material.Container(
            height: _multiline ? null : size.scaledHeight(context),
            constraints: _multiline
                ? material.BoxConstraints(minHeight: size.scaledHeight(context))
                : null,
            padding: material.EdgeInsets.only(
              left: widget.leading == null ? 0 : 10,
              right: trailing == null ? 0 : 4,
            ),
            decoration: material.BoxDecoration(
              color: widget.enabled
                  ? cs.card
                  : cs.muted.withValues(alpha: 0.4),
              borderRadius:
                  material.BorderRadius.circular(size.scaledRadius(context)),
              border: material.Border.all(
                color: hasError
                    ? cs.destructive
                    : _focused
                        ? cs.ring
                        : cs.border.withValues(alpha: 0.7),
              ),
            ),
            child: material.Row(
              crossAxisAlignment: _multiline
                  ? material.CrossAxisAlignment.start
                  : material.CrossAxisAlignment.center,
              children: [
                if (widget.leading != null) ...[
                  material.IconTheme(
                    data: material.IconThemeData(
                      size: size.scaledIconSize(context),
                      color: muted,
                    ),
                    child: widget.leading!,
                  ),
                  const material.SizedBox(width: 8),
                ],
                material.Expanded(child: field),
                if (trailing != null) trailing,
              ],
            ),
          )
        : field;

    if (hasError) {
      content = material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          content,
          const material.SizedBox(height: 4),
          material.Text(
            widget.errorText!,
            style: material.TextStyle(fontSize: 12, color: cs.destructive),
          ),
        ],
      );
    }
    return content;
  }
}
