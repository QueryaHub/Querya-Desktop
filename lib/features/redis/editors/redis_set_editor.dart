import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// Editor for a Redis set: SADD add bar plus a member list.
class RedisSetEditor extends material.StatefulWidget {
  const RedisSetEditor({
    super.key,
    required this.heading,
    required this.members,
    required this.isReadOnly,
    required this.onAdd,
    required this.onRemove,
    required this.colorScheme,
    required this.shadcnCs,
    this.footer,
  });

  final String heading;
  final List<RedisBulkValue> members;
  final bool isReadOnly;
  final void Function(String member) onAdd;
  final void Function(RedisBulkValue member) onRemove;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;
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
                child: TextField(
                  controller: _valueController,
                  placeholder: const Text('New member'),
                ),
              ),
              const Gap(8),
              PrimaryButton(
                onPressed: () {
                  final v = _valueController.text.trim();
                  if (v.isEmpty) return;
                  widget.onAdd(v);
                  _valueController.clear();
                },
                size: ButtonSize.small,
                child: const Text('SADD'),
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
                    colorScheme: widget.colorScheme,
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
    required this.member,
    this.onDelete,
    required this.colorScheme,
    required this.shadcnCs,
  });

  final String member;
  final VoidCallback? onDelete;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: material.BoxDecoration(
        color: colorScheme.card,
        borderRadius: material.BorderRadius.circular(6),
        border: material.Border.all(
            color: colorScheme.border.withValues(alpha: 0.3)),
      ),
      child: material.Row(
        children: [
          material.Expanded(
            child: material.SelectableText(
              member,
              style: material.TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colorScheme.foreground,
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
