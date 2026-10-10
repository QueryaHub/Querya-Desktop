import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/shared/widgets/querya_search_field.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Find-a-table field and the tables it matches. Enter picks the first.
class ErdSearchPanel extends material.StatelessWidget {
  const ErdSearchPanel({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.matches,
    required this.onChanged,
    required this.onPick,
  });

  final material.TextEditingController controller;
  final material.FocusNode focusNode;

  /// The trimmed text typed so far; the result list shows once it is not empty.
  final String query;

  /// The tables matching [query], best first.
  final List<ErdTable> matches;
  final void Function(String text) onChanged;

  /// Called with the name of the table to pick.
  final void Function(String name) onPick;

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    return material.Column(
      mainAxisSize: material.MainAxisSize.min,
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        QueryaSearchField(
          controller: controller,
          focusNode: focusNode,
          placeholder: 'Find table',
          debounceDuration: Duration.zero,
          onChanged: onChanged,
          onSubmitted: (_) {
            if (matches.isNotEmpty) onPick(matches.first.name);
          },
        ),
        if (query.isNotEmpty)
          material.Container(
            margin: const material.EdgeInsets.only(top: 4),
            decoration: material.BoxDecoration(
              color: wb.surface,
              borderRadius: material.BorderRadius.circular(8),
              border: material.Border.all(color: wb.borderSubtle),
            ),
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                if (matches.isEmpty)
                  material.Padding(
                    padding: const material.EdgeInsets.all(8),
                    child: const Text('No tables match').muted().small(),
                  ),
                for (final t in matches)
                  material.GestureDetector(
                    key: material.ValueKey('erd_search_result_${t.name}'),
                    behavior: material.HitTestBehavior.opaque,
                    onTap: () => onPick(t.name),
                    child: material.Padding(
                      padding: const material.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: material.Text(t.name,
                          style: const material.TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
