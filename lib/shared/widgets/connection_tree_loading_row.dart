import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/ui/querya_tree_tokens.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Compact inline spinner row used while connection trees lazy-load children.
class ConnectionTreeLoadingRow extends material.StatelessWidget {
  const ConnectionTreeLoadingRow.connection({
    super.key,
    this.label = 'Loading...',
  })  : padding = QueryaTreeTokens.loadingPaddingConnection,
        spinnerSize = QueryaTreeTokens.spinnerConnection,
        strokeWidth = QueryaTreeTokens.spinnerStroke,
        gap = 8;

  const ConnectionTreeLoadingRow.nested({
    super.key,
    this.label = 'Loading...',
  })  : padding = QueryaTreeTokens.loadingPaddingNested,
        spinnerSize = QueryaTreeTokens.spinnerNested,
        strokeWidth = QueryaTreeTokens.spinnerStroke,
        gap = 6;

  final String label;
  final material.EdgeInsetsGeometry padding;
  final double spinnerSize;
  final double strokeWidth;
  final double gap;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Padding(
      padding: padding,
      child: material.Row(
        children: [
          material.SizedBox(
            width: spinnerSize,
            height: spinnerSize,
            child: material.CircularProgressIndicator(strokeWidth: strokeWidth),
          ),
          Gap(gap),
          Text(label).muted().xSmall(),
        ],
      ),
    );
  }
}
