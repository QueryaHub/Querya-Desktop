import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/security/connection_environment.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/shared/widgets/connection_environment_badge.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Connection form block that tags a connection as Development, Staging or
/// Production (or leaves it untagged). Production connections open read-only.
class EnvironmentSection extends material.StatelessWidget {
  const EnvironmentSection({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ConnectionEnvironment? value;
  final material.ValueChanged<ConnectionEnvironment?> onChanged;

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        const Text('Environment').small().semiBold(),
        const Gap(8),
        material.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Option(
              optionKey: 'none',
              label: 'None',
              color: wb.mutedForeground,
              selected: value == null,
              onTap: () => onChanged(null),
            ),
            for (final env in ConnectionEnvironment.values)
              _Option(
                optionKey: env.storageValue,
                label: env.label,
                color: environmentAccentColor(wb, env),
                selected: value == env,
                onTap: () => onChanged(env),
              ),
          ],
        ),
        if (value == ConnectionEnvironment.production) ...[
          const Gap(6),
          Text(
            'Opens read-only. Writing requires typing the connection name to '
            'unlock, and locks again after 5 minutes.',
            style: material.TextStyle(color: wb.mutedForeground, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _Option extends material.StatelessWidget {
  const _Option({
    required this.optionKey,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String optionKey;
  final String label;
  final material.Color color;
  final bool selected;
  final material.VoidCallback onTap;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Semantics(
      button: true,
      selected: selected,
      label: label,
      child: material.InkWell(
        key: material.Key('environment_option_$optionKey'),
        onTap: onTap,
        borderRadius: material.BorderRadius.circular(6),
        child: material.Container(
          padding:
              const material.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: material.BoxDecoration(
            color: selected ? color.withValues(alpha: 0.16) : null,
            borderRadius: material.BorderRadius.circular(6),
            border: material.Border.all(
              color: selected ? color : color.withValues(alpha: 0.35),
            ),
          ),
          child: material.Row(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Container(
                width: 8,
                height: 8,
                decoration:
                    material.BoxDecoration(color: color, shape: material.BoxShape.circle),
              ),
              const Gap(6),
              Text(label, style: const material.TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
