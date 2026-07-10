import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/extension_support.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';
import 'package:querya_desktop/features/extensions/presentation/widgets/extension_card.dart';
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
  List<ExtensionManifest> _installed = [];
  List<ExtensionManifest> _marketplace = [];
  bool _loading = true;
  final Map<String, double> _installingProgress = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    await LocalExtensionRegistry.instance.load();
    final installed = LocalExtensionRegistry.instance.manifests;
    final market = await MarketplaceRepository.instance.getTrending();
    if (mounted) {
      setState(() {
        _installed = installed;
        _marketplace = market;
        _loading = false;
      });
    }
  }

  Future<void> _onSearchChanged(String query) async {
    if (query.trim().isEmpty) {
      final market = await MarketplaceRepository.instance.getTrending();
      if (mounted) setState(() => _marketplace = market);
    } else {
      final market = await MarketplaceRepository.instance.search(query);
      if (mounted) setState(() => _marketplace = market);
    }
  }

  Future<void> _installExtension(ExtensionManifest manifest) async {
    setState(() => _installingProgress[manifest.id] = 0.01);
    try {
      await MarketplaceRepository.instance.install(
        manifest,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _installingProgress[manifest.id] = progress);
          }
        },
      );
      if (mounted) {
        setState(() {
          _installingProgress.remove(manifest.id);
          _installed = LocalExtensionRegistry.instance.manifests;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _installingProgress.remove(manifest.id));
        final message = e is MarketplaceException
            ? e.message
            : 'Failed to install "${manifest.name}".';
        material.ScaffoldMessenger.of(context).showSnackBar(
          material.SnackBar(content: material.Text(message)),
        );
      }
    }
  }

  Future<void> _uninstallExtension(ExtensionManifest manifest) async {
    await MarketplaceRepository.instance.uninstall(manifest.id);
    if (mounted) {
      setState(() {
        _installed = LocalExtensionRegistry.instance.manifests;
      });
    }
  }

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
                      material.Expanded(
                        child: material.Column(
                          crossAxisAlignment: material.CrossAxisAlignment.start,
                          children: [
                            const Text('Extensions').large().semiBold().foreground(),
                            const material.SizedBox(height: 6),
                            const Text('Manage local and marketplace extensions')
                                .muted()
                                .small(),
                          ],
                        ),
                      ),
                      const material.SizedBox(width: 16),
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
                  child: material.Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildTabButton(0, 'Installed', count: _installed.length),
                      _buildTabButton(1, 'Marketplace'),
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

  material.Widget _buildTabButton(int index, String label, {int? count}) {
    final isSelected = _tabIndex == index;
    final displayLabel = count != null ? '$label ($count)' : label;
    return SecondaryButton(
      onPressed: () => setState(() => _tabIndex = index),
      child: material.Text(
        displayLabel,
        style: material.TextStyle(
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
          fontWeight: isSelected ? material.FontWeight.w600 : material.FontWeight.w400,
        ),
      ),
    );
  }

  material.Widget _buildInstalledTab() {
    if (_loading) {
      return const material.Center(
        child: material.CircularProgressIndicator(),
      );
    }
    if (_installed.isEmpty) {
      return const material.Center(
        child: material.Padding(
          padding: material.EdgeInsets.all(32.0),
          child: Text('No extensions installed yet. Explore the Marketplace tab to get started!'),
        ),
      );
    }
    return material.ListView.separated(
      padding: const material.EdgeInsets.all(24),
      itemCount: _installed.length,
      separatorBuilder: (_, __) => const material.SizedBox(height: 16),
      itemBuilder: (ctx, i) {
        final manifest = _installed[i];
        final isInstalling = _installingProgress.containsKey(manifest.id);
        final progress = _installingProgress[manifest.id];
        return ExtensionCard(
          manifest: manifest,
          isInstalled: true,
          isInstalling: isInstalling,
          installProgress: progress,
          onUninstall: () => _uninstallExtension(manifest),
        );
      },
    );
  }

  material.Widget _buildMarketplaceTab() {
    if (_loading) {
      return const material.Center(
        child: material.CircularProgressIndicator(),
      );
    }
    final theme = Theme.of(context).colorScheme;
    return material.Column(
      children: [
        material.Padding(
          padding: const material.EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: material.Container(
            width: double.infinity,
            padding: const material.EdgeInsets.all(12),
            decoration: material.BoxDecoration(
              color: theme.muted.withValues(alpha: 0.35),
              borderRadius: material.BorderRadius.circular(8),
              border: material.Border.all(color: theme.border),
            ),
            child: material.Row(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                material.Icon(
                  material.Icons.info_outline_rounded,
                  size: 18,
                  color: theme.mutedForeground,
                ),
                const material.SizedBox(width: 10),
                material.Expanded(
                  child: Text(ExtensionSupport.databaseDriverPreviewNotice)
                      .muted()
                      .small(),
                ),
              ],
            ),
          ),
        ),
        material.Padding(
          padding: const material.EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: TextField(
            placeholder: const material.Text('Search extensions by name, tag, or description...'),
            onChanged: _onSearchChanged,
            features: const [
              InputFeature.leading(
                Padding(
                  padding: material.EdgeInsets.only(right: 8),
                  child: material.Icon(material.Icons.search_rounded, size: 18),
                ),
              ),
            ],
          ),
        ),
        material.Expanded(
          child: _marketplace.isEmpty
              ? const material.Center(
                  child: material.Padding(
                    padding: material.EdgeInsets.all(32.0),
                    child: Text('No extensions found matching your search.'),
                  ),
                )
              : material.ListView.separated(
                  padding: const material.EdgeInsets.all(24),
                  itemCount: _marketplace.length,
                  separatorBuilder: (_, __) => const material.SizedBox(height: 16),
                  itemBuilder: (ctx, i) {
                    final manifest = _marketplace[i];
                    final isInstalled = _installed.any((e) => e.id == manifest.id);
                    final isInstalling = _installingProgress.containsKey(manifest.id);
                    final progress = _installingProgress[manifest.id];
                    return ExtensionCard(
                      manifest: manifest,
                      isInstalled: isInstalled,
                      isInstalling: isInstalling,
                      installProgress: progress,
                      onInstall: () => _installExtension(manifest),
                      onUninstall: () => _uninstallExtension(manifest),
                    );
                  },
                ),
        ),
      ],
    );
  }

  material.Widget _buildUpdatesTab() {
    return const material.Center(
      child: material.Padding(
        padding: material.EdgeInsets.all(32.0),
        child: Text('All installed extensions are up to date!'),
      ),
    );
  }
}
