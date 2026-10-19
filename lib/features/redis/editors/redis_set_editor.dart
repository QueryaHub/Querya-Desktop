import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_ui_colors.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Editor for a Redis set: SADD add bar plus a member list.
class RedisSetEditor extends material.StatefulWidget {
  const RedisSetEditor({
    super.key,
    required this.heading,
    required this.members,
    required this.isReadOnly,
    required this.onAdd,
    required this.onRemove,
    required this.colors,
    required this.shadcnCs,
    this.footer,
  });

  final String heading;
  final List<RedisBulkValue> members;
  final bool isReadOnly;
  final void Function(String member) onAdd;
  final void Function(RedisBulkValue member) onRemove;
  final QueryaUiColors colors;
  final QueryaUiColors shadcnCs;
  final material.Widget? footer;

  @override
  material.State<RedisSetEditor> createState() => _RedisSetEditorState();
}

class _RedisSetEditorState extends material.State<RedisSetEditor> {
  final _valueController = material.TextEditingController();

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final members = widget.members;
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Text(widget.heading).semiBold(),
        if (!widget.isReadOnly) ...[
          const Gap(8),
          material.Row(
            children: [
              material.Expanded(
                child: QueryaTextField(
                  controller: _valueController,
                  placeholder: 'New member',
                ),
              ),
              const Gap(8),
              QueryaButton.primary(
                label: 'SADD',
                onPressed: () {
                  final v = _valueController.text.trim();
                  if (v.isEmpty) return;
                  widget.onAdd(v);
                  _valueController.clear();
                },
                size: QueryaControlSize.sm,
              ),
            ],
          ),
        ],
        const Gap(12),
        material.Expanded(
          child: members.isEmpty
              ? material.Center(child: const Text('No members').muted())
              : material.ListView.separated(
                  itemCount: members.length,
                  separatorBuilder: (_, __) => const Gap(4),
                  itemBuilder: (context, index) => RedisMemberRow(
                    member: members[index].label,
                    onDelete: widget.isReadOnly
                        ? null
                        : () => widget.onRemove(members[index]),
                    colors: widget.colors,
                    shadcnCs: widget.shadcnCs,
                  ),
                ),
        ),
        if (widget.footer != null) widget.footer!,
      ],
    );
  }
}

class RedisMemberRow extends StatelessWidget {
  const RedisMemberRow({
    super.key,
    required this.member,
    this.onDelete,
    required this.colors,
    required this.shadcnCs,
  });

  final String member;
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
          material.Expanded(
            child: material.SelectableText(
              member,
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
