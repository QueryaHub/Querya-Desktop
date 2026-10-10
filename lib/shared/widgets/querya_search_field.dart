import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Standard search and filter input field with debounce, clear button, and shortcut support.
class QueryaSearchField extends material.StatefulWidget {
  const QueryaSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder = 'Search...',
    this.onChanged,
    this.onSubmitted,
    this.debounceDuration = const Duration(milliseconds: 250),
    this.autofocus = false,
    this.height,
    this.size,
    this.shortcutHint,
    this.width,
  });

  /// Optional external controller. If omitted, an internal controller is managed.
  final material.TextEditingController? controller;

  /// Optional external focus node.
  final material.FocusNode? focusNode;

  /// Placeholder hint text.
  final String placeholder;

  /// Callback fired after debounce duration when input text changes.
  final ValueChanged<String>? onChanged;

  /// Callback fired immediately upon Enter / submit.
  final ValueChanged<String>? onSubmitted;

  /// Debounce delay. Set to [Duration.zero] for immediate invocation.
  final Duration debounceDuration;

  /// Whether to autofocus this search field.
  final bool autofocus;

  /// Explicit height in px; wins over [size]. Prefer [size].
  final double? height;

  /// Control size (height, font, icon, radius). Without one the field takes the
  /// nearest [QueryaControlScope], then [QueryaControlSize.md] (32 px).
  final QueryaControlSize? size;

  /// Optional keybinding hint displayed at the trailing end (e.g. 'ESC', 'Ctrl+F').
  final String? shortcutHint;

  /// Optional fixed width constraint.
  final double? width;

  @override
  material.State<QueryaSearchField> createState() => _QueryaSearchFieldState();
}

class _QueryaSearchFieldState extends material.State<QueryaSearchField> {
  late material.TextEditingController _controller;
  late material.FocusNode _focusNode;
  Timer? _debounceTimer;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? material.TextEditingController();
    _focusNode = widget.focusNode ?? material.FocusNode();
    _hasText = _controller.text.isNotEmpty;

    _controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant QueryaSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && widget.controller != _controller) {
      if (oldWidget.controller == null) {
        _controller.dispose();
      } else {
        _controller.removeListener(_handleControllerChange);
      }
      _controller = widget.controller!;
      _hasText = _controller.text.isNotEmpty;
      _controller.addListener(_handleControllerChange);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_handleControllerChange);
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleControllerChange() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _onInputChanged(String value) {
    if (widget.onChanged == null) return;

    if (widget.debounceDuration == Duration.zero) {
      widget.onChanged!(value);
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceDuration, () {
      if (mounted) {
        widget.onChanged!(value);
      }
    });
  }

  void _clear() {
    _debounceTimer?.cancel();
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workbench = QueryaThemeScope.maybeOf(context)?.workbench;
    final controlSize = widget.size ?? QueryaControlSize.of(context);
    final fieldHeight = widget.height ?? controlSize.scaledHeight(context);
    final fieldFont = controlSize.scaledFontSize(context);

    final searchIconColor = _hasText
        ? (workbench?.accent ?? cs.primary)
        : (workbench?.mutedForeground ?? cs.mutedForeground);

    material.Widget content = material.Container(
      height: fieldHeight,
      decoration: material.BoxDecoration(
        color: cs.card,
        borderRadius:
            material.BorderRadius.circular(controlSize.scaledRadius(context)),
        border: material.Border.all(
          color: _hasText
              ? (workbench?.accent ?? cs.primary).withValues(alpha: 0.5)
              : cs.border.withValues(alpha: 0.7),
          width: 1,
        ),
      ),
      child: material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.center,
        children: [
          material.Padding(
            padding: const material.EdgeInsets.only(left: 8, right: 6),
            child: material.Icon(
              material.Icons.search_rounded,
              size: controlSize.scaledIconSize(context),
              color: searchIconColor,
            ),
          ),
          material.Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  if (_hasText) {
                    _clear();
                  } else {
                    _focusNode.unfocus();
                  }
                },
              },
              child: material.TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                onChanged: _onInputChanged,
                onSubmitted: widget.onSubmitted,
                style: material.TextStyle(
                  fontSize: fieldFont,
                  color: cs.foreground,
                ),
                cursorHeight: 14,
                cursorColor: workbench?.accent ?? cs.primary,
                decoration: material.InputDecoration(
                  hintText: widget.placeholder,
                  hintStyle: material.TextStyle(
                    fontSize: fieldFont,
                    color: workbench?.mutedForeground ?? cs.mutedForeground,
                  ),
                  isDense: true,
                  border: material.InputBorder.none,
                  focusedBorder: material.InputBorder.none,
                  enabledBorder: material.InputBorder.none,
                  contentPadding: const material.EdgeInsets.symmetric(vertical: 7),
                ),
              ),
            ),
          ),
          if (_hasText)
            material.Padding(
              padding: const material.EdgeInsets.only(right: 4),
              child: material.IconButton(
                icon: const material.Icon(material.Icons.close_rounded, size: 14),
                splashRadius: 12,
                padding: material.EdgeInsets.zero,
                constraints: const material.BoxConstraints(
                  minWidth: 20,
                  minHeight: 20,
                ),
                color: cs.mutedForeground,
                hoverColor: cs.muted.withValues(alpha: 0.3),
                tooltip: 'Clear search (Esc)',
                onPressed: _clear,
              ),
            )
          else if (widget.shortcutHint != null)
            material.Padding(
              padding: const material.EdgeInsets.only(right: 6),
              child: material.Container(
                padding: const material.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                decoration: material.BoxDecoration(
                  color: cs.muted.withValues(alpha: 0.3),
                  borderRadius: material.BorderRadius.circular(3),
                ),
                child: material.Text(
                  widget.shortcutHint!,
                  style: material.TextStyle(
                    fontSize: 9,
                    fontWeight: material.FontWeight.w500,
                    color: cs.mutedForeground,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.width != null) {
      content = material.SizedBox(width: widget.width, child: content);
    }

    return content;
  }
}
