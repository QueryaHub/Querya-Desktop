import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Editor for a Redis string key. Binary (non-UTF-8) values are shown as
/// read-only hex / base64. The [controller] is owned by the parent so it can
/// track the dirty state.
class RedisStringEditor extends material.StatelessWidget {
  const RedisStringEditor({
    super.key,
    required this.value,
    required this.controller,
    required this.isReadOnly,
    required this.onSave,
    required this.colorScheme,
  });

  final RedisBulkValue? value;
  final material.TextEditingController controller;
  final bool isReadOnly;
  final VoidCallback onSave;
  final ColorScheme colorScheme;

  @override
  material.Widget build(material.BuildContext context) {
    final bulk = value;
    if (bulk != null && !bulk.isUtf8) {
      return material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          Text('Binary value (${bulk.bytes.length} bytes)').semiBold(),
          const Gap(8),
          const Text(
            'Not valid UTF-8. Save as text is disabled so the original bytes are not overwritten.',
          ).muted().small(),
          const Gap(12),
          const Text('Hex').semiBold().small(),
          const Gap(4),
          material.SelectableText(
            bulk.toHex(),
            style: const material.TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
          const Gap(12),
          const Text('Base64').semiBold().small(),
          const Gap(4),
          material.SelectableText(
            bulk.toBase64(),
            style: const material.TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      );
    }
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('Value').semiBold(),
            if (!isReadOnly) ...[
              const Spacer(),
              PrimaryButton(
                onPressed: onSave,
                size: ButtonSize.small,
                leading:
                    const material.Icon(material.Icons.save_rounded, size: 14),
                child: const Text('Save'),
              ),
            ],
          ],
        ),
        const Gap(8),
        material.Container(
          constraints: const material.BoxConstraints(minHeight: 200),
          decoration: material.BoxDecoration(
            border: material.Border.all(
                color: colorScheme.border.withValues(alpha: 0.3)),
            borderRadius: material.BorderRadius.circular(8),
          ),
          child: material.TextField(
            controller: controller,
            readOnly: isReadOnly,
            maxLines: null,
            style: const material.TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            decoration: const material.InputDecoration(
              border: material.InputBorder.none,
              contentPadding: material.EdgeInsets.all(12),
            ),
          ),
        ),
      ],
    );
  }
}
