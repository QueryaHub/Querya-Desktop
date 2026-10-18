import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/database/query_error_text.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/core/widgets/virtual_selectable_text_view.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// A failed query: the driver's message as the headline, the rest (without the
/// statement the app wrapped around the user's SQL) behind "Show details", and
/// a Copy button (#1557). Shared by the SQL results pane and the Mongo query
/// workspace.
///
/// [inline] is for a panel that has its own title row (a box above results):
/// left aligned and without the large icon and title.
class QueryErrorView extends material.StatefulWidget {
  const QueryErrorView({
    super.key,
    required this.error,
    this.action,
    this.inline = false,
  });

  final QueryErrorText error;

  /// Shown under the error, e.g. a way to fix the connection.
  final material.Widget? action;
  final bool inline;

  @override
  material.State<QueryErrorView> createState() => _QueryErrorViewState();
}

class _QueryErrorViewState extends material.State<QueryErrorView> {
  bool _showDetails = false;
  bool _copied = false;

  @override
  void didUpdateWidget(covariant QueryErrorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.error.detail != widget.error.detail) {
      _showDetails = false;
      _copied = false;
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.error.detail));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final error = widget.error;
    final inline = widget.inline;
    final align = inline
        ? material.CrossAxisAlignment.start
        : material.CrossAxisAlignment.center;
    return material.Column(
      mainAxisAlignment: material.MainAxisAlignment.center,
      mainAxisSize: material.MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        if (!inline) ...[
          material.Icon(
            material.Icons.error_outline_rounded,
            size: 48,
            color: cs.destructive,
          ),
          const Gap(16),
          const Text('Query Error').large().semiBold(),
          const Gap(8),
        ],
        material.SelectableText(
          error.summary,
          textAlign: inline ? material.TextAlign.start : material.TextAlign.center,
          style: material.TextStyle(color: cs.foreground, fontSize: 14),
        ),
        if (error.hasDetail) ...[
          const Gap(12),
          material.Row(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              QueryaButton.ghost(
                label: _showDetails ? 'Hide details' : 'Show details',
                icon: _showDetails
                    ? material.Icons.expand_less_rounded
                    : material.Icons.expand_more_rounded,
                size: QueryaControlSize.sm,
                onPressed: () => setState(() => _showDetails = !_showDetails),
              ),
              const Gap(6),
              QueryaButton.ghost(
                label: _copied ? 'Copied' : 'Copy error',
                icon: _copied
                    ? material.Icons.check_rounded
                    : material.Icons.copy_rounded,
                size: QueryaControlSize.sm,
                onPressed: () => unawaited(_copy()),
              ),
            ],
          ),
        ],
        if (error.hasDetail && _showDetails) ...[
          const Gap(8),
          // A long driver message scrolls inside the space left, instead of
          // pushing the column past the pane.
          material.Flexible(
            child: VirtualSelectableTextView(
              text: error.detail,
              style: material.TextStyle(
                color: cs.mutedForeground,
                fontSize: 13,
              ),
            ),
          ),
        ],
        if (widget.action != null) ...[
          const Gap(16),
          widget.action!,
        ],
      ],
    );
  }
}
