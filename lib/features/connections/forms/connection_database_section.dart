import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Reusable Database name input field for connection forms (#1364).
class ConnectionDatabaseSection extends StatelessWidget {
  const ConnectionDatabaseSection({
    super.key,
    required this.databaseController,
    this.label = 'Database',
    this.placeholder = 'postgres',
    this.hint,
  });

  final material.TextEditingController databaseController;
  final String label;
  final String placeholder;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      mainAxisSize: material.MainAxisSize.min,
      children: [
        Text(label).small().semiBold(),
        if (hint != null) ...[
          const Gap(4),
          Text(hint!).muted().small(),
        ],
        const Gap(8),
        TextField(
          controller: databaseController,
          placeholder: Text(placeholder),
        ),
      ],
    );
  }
}
