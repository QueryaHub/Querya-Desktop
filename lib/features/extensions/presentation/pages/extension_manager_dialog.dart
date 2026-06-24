import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

void showExtensionManagerDialog(material.BuildContext context) {
  showAppDialog<void>(
    context: context,
    builder: (ctx) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(ctx),
      child: const _ExtensionManagerContent(),
    ),
  );
}

class _ExtensionManagerContent extends material.StatefulWidget {
  const _ExtensionManagerContent();

  @override
  material.State<_ExtensionManagerContent> createState() =>
      _ExtensionManagerContentState();
}

class _ExtensionManagerContentState extends material.State<_ExtensionManagerContent> {
  int _tabIndex = 0;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = material.Theme.of(context).colorScheme;
    final radius = material.Theme.of(context).radiusXxl;
    final onPopover = theme.popoverForeground;

    return material.DefaultTextStyle(
      style: material.TextStyle(color: onPopover),
      child: material.IconTheme(
        data: material.IconThemeData(color: onPopover),
        child: material.Container(
          constraints: WindowLayout.dialogConstraints(
            context,
            maxWidth: 800,
            minWidth: 600,
            maxHeight: 700,
          ),
          decoration: material.BoxDecoration(
            color: theme.popover,
            borderRadius: material.BorderRadius.circular(radius),
            border: material.Border.all(color: theme.border),
          ),
          child: material.ClipRRect(
            borderRadius: material.BorderRadius.circular(radius),
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                material.Padding(
                  padding: const material.EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: material.Row(
                    mainAxisAlignment: material.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: material.CrossAxisAlignment.center,
                    children: [
                      material.Column(
                        crossAxisAlignment: material.CrossAxisAlignment.start,
                        children: [
                          const Text('Extensions').large().semiBold().foreground(),
                          const material.SizedBox(height: 6),
                          const Text('Manage local and marketplace extensions')
                              .muted()
                              .small(),
                        ],
                      ),
                      PrimaryButton(
                        onPressed: () => material.Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                material.Padding(
                  padding: const material.EdgeInsets.symmetric(
                      horizontal: 24.0, vertical: 8.0),
                  child: material.Row(
                    children: [
                      _buildTabButton(0, 'Installed'),
                      const material.SizedBox(width: 8),
                      _buildTabButton(1, 'Marketplace'),
                      const material.SizedBox(width: 8),
                      _buildTabButton(2, 'Updates'),
                    ],
                  ),
                ),
                material.Divider(height: 1, color: theme.border),
                material.Expanded(
                  child: material.IndexedStack(
                    index: _tabIndex,
                    children: [
                      _buildInstalledTab(),
                      _buildMarketplaceTab(),
                      _buildUpdatesTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  material.Widget _buildTabButton(int index, String label) {
    final isSelected = _tabIndex == index;
    return SecondaryButton(
      onPressed: () => setState(() => _tabIndex = index),
      child: Text(label).withColor(
        isSelected ? material.Theme.of(context).colorScheme.primary : null,
      ),
    );
  }

  material.Widget _buildInstalledTab() {
    return const material.Center(child: Text('Installed extensions will appear here.'));
  }

  material.Widget _buildMarketplaceTab() {
    return const material.Center(child: Text('Marketplace extensions will appear here.'));
  }

  material.Widget _buildUpdatesTab() {
    return const material.Center(child: Text('Extension updates will appear here.'));
  }
}
