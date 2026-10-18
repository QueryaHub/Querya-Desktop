import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_ui_colors.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Editor for a Redis hash: HSET add bar plus a field/value list.
class RedisHashEditor extends material.StatefulWidget {
  const RedisHashEditor({
    super.key,
    required this.heading,
    required this.entries,
    required this.isReadOnly,
    required this.onSet,
    required this.onDelete,
    required this.colors,
    required this.shadcnCs,
    this.footer,
  });

  final String heading;
  final List<MapEntry<RedisBulkValue, RedisBulkValue>> entries;
  final bool isReadOnly;
  final void Function(String field, String value) onSet;
  final void Function(RedisBulkValue field) onDelete;
  final QueryaUiColors colors;
  final QueryaUiColors shadcnCs;
  final material.Widget? footer;

  @override
  material.State<RedisHashEditor> createState() => _RedisHashEditorState();
}

class _RedisHashEditorState extends material.State<RedisHashEditor> {
  final _fieldController = material.TextEditingController();
  final _valueController = material.TextEditingController();

  @override
  void dispose() {
    _fieldController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final entries = widget.entries;
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Text(widget.heading).semiBold(),
        if (!widget.isReadOnly) ...[
          const Gap(8),
          material.Row(
            children: [
              material.Expanded(
                child: TextField(
                  controller: _fieldController,
                  placeholder: const Text('Field'),
                ),
              ),
              const Gap(8),
              material.Expanded(
                child: TextField(
                  controller: _valueController,
                  placeholder: const Text('Value'),
                ),
              ),
              const Gap(8),
              QueryaButton.primary(
                label: 'HSET',
                onPressed: () {
                  final f = _fieldController.text.trim();
                  final v = _valueController.text;
                  if (f.isEmpty) return;
                  widget.onSet(f, v);
                  _fieldController.clear();
                  _valueController.clear();
                },
                size: QueryaControlSize.sm,
              ),
            ],
          ),
        ],
        const Gap(12),
        material.Expanded(
          child: entries.isEmpty
              ? material.Center(child: const Text('No fields').muted())
              : material.ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Gap(4),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return RedisFieldRow(
                      field: entry.key.label,
                      value: entry.value.label,
                      onDelete: widget.isReadOnly
                          ? null
                          : () => widget.onDelete(entry.key),
                      colors: widget.colors,
                      shadcnCs: widget.shadcnCs,
                    );
                  },
                ),
        ),
        if (widget.footer != null) widget.footer!,
      ],
    );
  }
}

class RedisFieldRow extends StatelessWidget {
  const RedisFieldRow({
    super.key,
    required this.field,
    required this.value,
    this.onDelete,
    required this.colors,
    required this.shadcnCs,
  });

  final String field;
  final String value;
  final VoidCallback? onDelete;
  final QueryaUiColors colors;
  final QueryaUiColors shadcnCs;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: material.BoxDecoration(
        color: colors.card,
        borderRadius: material.BorderRadius.circular(6),
        border: material.Border.all(
            color: colors.border.withValues(alpha: 0.3)),
      ),
      child: material.Row(
        children: [
          material.SizedBox(
            width: 160,
            child: material.Text(
              field,
              overflow: material.TextOverflow.ellipsis,
              style: material.TextStyle(
                fontSize: 12,
                fontFamily: QueryaTypography.mono,
                fontFamilyFallback: QueryaTypography.monoFontFamilyFallback,
                fontWeight: material.FontWeight.w600,
                color: shadcnCs.primary,
              ),
            ),
          ),
          const Gap(12),
          material.Expanded(
            child: material.SelectableText(
              value,
              style: material.TextStyle(
                fontSize: 12,
                fontFamily: QueryaTypography.mono,
                fontFamilyFallback: QueryaTypography.monoFontFamilyFallback,
                color: colors.foreground,
              ),
            ),
          ),
          const Gap(8),
          if (onDelete != null)
            material.InkWell(
              onTap: onDelete,
              borderRadius: material.BorderRadius.circular(4),
              child: material.Padding(
                padding: const material.EdgeInsets.all(4),
                child: material.Icon(material.Icons.close_rounded,
                    size: 14, color: context.semanticPalette.destructive),
              ),
            ),
        ],
      ),
    );
  }
}
