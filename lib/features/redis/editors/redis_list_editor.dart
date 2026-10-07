import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// Editor for a Redis list: RPUSH add bar plus an indexed item list with
/// in-place edit (LSET) and remove (LREM).
class RedisListEditor extends material.StatefulWidget {
  const RedisListEditor({
    super.key,
    required this.heading,
    required this.items,
    required this.isReadOnly,
    required this.onPush,
    required this.onSet,
    required this.onRemove,
    required this.colorScheme,
    required this.shadcnCs,
    this.footer,
  });

  final String heading;
  final List<RedisBulkValue> items;
  final bool isReadOnly;
  final void Function(String value) onPush;
  final Future<void> Function(
    int index,
    String newValue, {
    RedisBulkValue? expectedCurrent,
  }) onSet;
  final void Function(int index, RedisBulkValue item) onRemove;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;
  final material.Widget? footer;

  @override
  material.State<RedisListEditor> createState() => _RedisListEditorState();
}

class _RedisListEditorState extends material.State<RedisListEditor> {
  final _valueController = material.TextEditingController();

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _edit(int i) async {
    final item = widget.items[i];
    final initialText = item.text ?? item.label;
    final edited = await showAppDialog<String>(
      context: context,
      builder: (ctx) => RedisEditListDialogContent(
        index: i,
        initialValue: initialText,
      ),
    );
    if (edited != null && edited != initialText) {
      await widget.onSet(i, edited, expectedCurrent: item);
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final items = widget.items;
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
                  placeholder: const Text('New item'),
                ),
              ),
              const Gap(8),
              PrimaryButton(
                onPressed: () {
                  final v = _valueController.text;
                  if (v.isEmpty) return;
                  widget.onPush(v);
                  _valueController.clear();
                },
                size: ButtonSize.small,
                child: const Text('RPUSH'),
              ),
            ],
          ),
        ],
        const Gap(12),
        material.Expanded(
          child: items.isEmpty
              ? material.Center(child: const Text('No items').muted())
              : material.ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Gap(4),
                  itemBuilder: (context, i) => RedisIndexedValueRow(
                    index: i,
                    value: items[i].label,
                    isBinary: !items[i].isUtf8,
                    onEdit: widget.isReadOnly || !items[i].isUtf8
                        ? null
                        : () => _edit(i),
                    onDelete: widget.isReadOnly
                        ? null
                        : () => widget.onRemove(i, items[i]),
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

class RedisEditListDialogContent extends material.StatefulWidget {
  const RedisEditListDialogContent({
    super.key,
    required this.index,
    required this.initialValue,
  });

  final int index;
  final String initialValue;

  @override
  material.State<RedisEditListDialogContent> createState() =>
      RedisEditListDialogContentState();
}

class RedisEditListDialogContentState
    extends material.State<RedisEditListDialogContent> {
  late final material.TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = material.TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    return AlertDialog(
      title: Text('Edit Item [${widget.index}]'),
      content: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          const Text('Enter new value').muted().small(),
          const Gap(8),
          TextField(
            controller: _controller,
            placeholder: const Text('Value'),
          ),
        ],
      ),
      actions: [
        GhostButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        PrimaryButton(
          onPressed: () {
            Navigator.of(context).pop(_controller.text);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class RedisIndexedValueRow extends StatelessWidget {
  const RedisIndexedValueRow({
    super.key,
    required this.index,
    required this.value,
    this.isBinary = false,
    this.onEdit,
    this.onDelete,
    required this.colorScheme,
    required this.shadcnCs,
  });

  final int index;
  final String value;
  final bool isBinary;
  final VoidCallback? onEdit;
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
          material.SizedBox(
            width: 40,
            child: Text(
              '$index',
              style: material.TextStyle(
                fontSize: 12,
                fontWeight: material.FontWeight.w600,
                color: shadcnCs.mutedForeground,
              ),
            ),
          ),
          const Gap(12),
          material.Expanded(
            child: material.SelectableText(
              value,
              style: material.TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colorScheme.foreground,
              ),
            ),
          ),
          if (isBinary) ...[
            const Gap(8),
            material.Container(
              padding: const material.EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1.5),
              decoration: material.BoxDecoration(
                color: shadcnCs.muted,
                borderRadius: material.BorderRadius.circular(3),
              ),
              child: Text(
                'binary',
                style: material.TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: shadcnCs.mutedForeground,
                ),
              ),
            ),
          ],
          if (onEdit != null) ...[
            const Gap(8),
            material.Tooltip(
              message: 'Edit item',
              child: material.InkWell(
                onTap: onEdit,
                borderRadius: material.BorderRadius.circular(4),
                child: material.Padding(
                  padding: const material.EdgeInsets.all(4),
                  child: material.Icon(material.Icons.edit_outlined,
                      size: 14, color: shadcnCs.mutedForeground),
                ),
              ),
            ),
          ],
          if (onDelete != null) ...[
            const Gap(8),
            material.Tooltip(
              message: 'Delete item',
              child: material.InkWell(
                onTap: onDelete,
                borderRadius: material.BorderRadius.circular(4),
                child: material.Padding(
                  padding: const material.EdgeInsets.all(4),
                  child: material.Icon(material.Icons.close_rounded,
                      size: 14, color: context.semanticPalette.destructive),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
