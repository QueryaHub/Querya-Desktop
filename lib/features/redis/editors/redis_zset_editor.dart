import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// Editor for a Redis sorted set: ZADD add bar plus a scored member list.
class RedisZsetEditor extends material.StatefulWidget {
  const RedisZsetEditor({
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
  final List<(RedisBulkValue, double)> members;
  final bool isReadOnly;
  final void Function(String member, double score) onAdd;
  final void Function(RedisBulkValue member) onRemove;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;
  final material.Widget? footer;

  @override
  material.State<RedisZsetEditor> createState() => _RedisZsetEditorState();
}

class _RedisZsetEditorState extends material.State<RedisZsetEditor> {
  final _memberController = material.TextEditingController();
  final _scoreController = material.TextEditingController();

  @override
  void dispose() {
    _memberController.dispose();
    _scoreController.dispose();
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
                flex: 2,
                child: TextField(
                  controller: _memberController,
                  placeholder: const Text('Member'),
                ),
              ),
              const Gap(8),
              material.Expanded(
                child: TextField(
                  controller: _scoreController,
                  placeholder: const Text('Score'),
                ),
              ),
              const Gap(8),
              PrimaryButton(
                onPressed: () {
                  final m = _memberController.text.trim();
                  final s = double.tryParse(_scoreController.text.trim());
                  if (m.isEmpty || s == null) return;
                  widget.onAdd(m, s);
                  _memberController.clear();
                  _scoreController.clear();
                },
                size: ButtonSize.small,
                child: const Text('ZADD'),
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
                  itemBuilder: (context, index) {
                    final (member, score) = members[index];
                    return RedisScoredMemberRow(
                      member: member.label,
                      score: score,
                      onDelete: widget.isReadOnly
                          ? null
                          : () => widget.onRemove(member),
                      colorScheme: widget.colorScheme,
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

class RedisScoredMemberRow extends StatelessWidget {
  const RedisScoredMemberRow({
    super.key,
    required this.member,
    required this.score,
    this.onDelete,
    required this.colorScheme,
    required this.shadcnCs,
  });

  final String member;
  final double score;
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
          material.Container(
            padding:
                const material.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: material.BoxDecoration(
              color: shadcnCs.muted.withValues(alpha: 0.3),
              borderRadius: material.BorderRadius.circular(4),
            ),
            child: Text(
              score.toStringAsFixed(score == score.roundToDouble() ? 0 : 2),
              style: material.TextStyle(
                fontSize: 11,
                fontWeight: material.FontWeight.w600,
                color: shadcnCs.primary,
              ),
            ),
          ),
          const Gap(12),
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
