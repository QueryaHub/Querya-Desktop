import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/features/extensions/presentation/widgets/extension_card.dart';
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

  final List<ExtensionManifest> _installedMocks = [
    const ExtensionManifest(
      id: 'queryahub.clickhouse-driver',
      name: 'ClickHouse Driver',
      version: '1.0.0',
      publisher: 'QueryaHub',
      type: ExtensionType.databaseDriver,
      engines: {'querya_desktop': '^0.4.7'},
      description: 'Full support for ClickHouse databases including Dictionaries and Materialized Views.',
    ),
  ];

  final List<ExtensionManifest> _marketMocks = [
    const ExtensionManifest(
      id: 'community.redis-driver',
      name: 'Redis Driver',
      version: '0.9.5',
      publisher: 'Community',
      type: ExtensionType.databaseDriver,
      engines: {'querya_desktop': '^0.4.7'},
      description: 'Connect to Redis instances and visualize key-value storage.',
    ),
  ];

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;
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
      child: material.Text(
        label,
        style: material.TextStyle(
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
    );
  }

  material.Widget _buildInstalledTab() {
    return material.ListView.separated(
      padding: const material.EdgeInsets.all(24),
      itemCount: _installedMocks.length,
      separatorBuilder: (_, __) => const material.SizedBox(height: 16),
      itemBuilder: (ctx, i) => ExtensionCard(
        manifest: _installedMocks[i],
        isInstalled: true,
        onUninstall: () {},
      ),
    );
  }

  material.Widget _buildMarketplaceTab() {
    return material.ListView.separated(
      padding: const material.EdgeInsets.all(24),
      itemCount: _marketMocks.length,
      separatorBuilder: (_, __) => const material.SizedBox(height: 16),
      itemBuilder: (ctx, i) => ExtensionCard(
        manifest: _marketMocks[i],
        isInstalled: false,
        onInstall: () {},
      ),
    );
  }

  material.Widget _buildUpdatesTab() {
    return const material.Center(child: material.Text('No updates available.'));
  }
}
