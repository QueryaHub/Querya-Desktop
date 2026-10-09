import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/shared/widgets/querya_icon_button.dart';

/// Overlay in the bottom-right corner of the diagram: zoom out, the current
/// zoom, zoom in and fit to screen.
class ErdZoomControls extends material.StatelessWidget {
  const ErdZoomControls({
    super.key,
    required this.scale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final double scale;
  final material.VoidCallback onZoomIn;
  final material.VoidCallback onZoomOut;
  final material.VoidCallback onFit;

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    return material.DecoratedBox(
      decoration: material.BoxDecoration(
        color: wb.surface,
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(color: wb.borderSubtle),
      ),
      child: material.Padding(
        padding: const material.EdgeInsets.symmetric(horizontal: 2),
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            QueryaIconButton(
              key: const material.ValueKey('erd_zoom_out'),
              icon: const material.Icon(material.Icons.remove_rounded),
              tooltip: 'Zoom out (Ctrl/Cmd+-)',
              density: QueryaIconButtonDensity.dense,
              onPressed: onZoomOut,
            ),
            material.SizedBox(
              width: 48,
              child: material.Text(
                '${(scale * 100).round()}%',
                key: const material.ValueKey('erd_zoom_label'),
                textAlign: material.TextAlign.center,
                style: material.TextStyle(
                    fontSize: 12, color: wb.mutedForeground),
              ),
            ),
            QueryaIconButton(
              key: const material.ValueKey('erd_zoom_in'),
              icon: const material.Icon(material.Icons.add_rounded),
              tooltip: 'Zoom in (Ctrl/Cmd++)',
              density: QueryaIconButtonDensity.dense,
              onPressed: onZoomIn,
            ),
            QueryaIconButton(
              key: const material.ValueKey('erd_fit'),
              icon: const material.Icon(material.Icons.fit_screen_rounded),
              tooltip: 'Fit to screen (Ctrl/Cmd+0)',
              density: QueryaIconButtonDensity.dense,
              onPressed: onFit,
            ),
          ],
        ),
      ),
    );
  }
}
