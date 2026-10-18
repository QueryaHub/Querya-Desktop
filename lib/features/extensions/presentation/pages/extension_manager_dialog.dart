import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/extension_support.dart';
import 'package:querya_desktop/core/extensions/local_extension_installer.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';
import 'package:querya_desktop/core/motion/querya_cross_fade_stack.dart';
import 'package:querya_desktop/features/extensions/presentation/widgets/extension_card.dart';
import 'package:querya_desktop/features/extensions/presentation/widgets/extension_sideload_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Pause after the last keystroke before the marketplace is queried.
const kMarketplaceSearchDebounce = Duration(milliseconds: 250);

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

class _ExtensionManagerContentState
    extends material.State<_ExtensionManagerContent> {
  int _tabIndex = 0;
  List<ExtensionManifest> _installed = [];
  List<ExtensionManifest> _marketplace = [];

  /// Why the catalog could not be loaded (offline, registry down); null when it
  /// loaded, even if it is empty.
  String? _marketplaceError;
  String _query = '';
  bool _loading = true;
  final Map<String, double> _installingProgress = {};
  bool _sideloading = false;
  String? _sideloadError;
  Timer? _searchDebounce;

  /// Bumped on every keystroke and on dispose; only the response that still
  /// matches it is applied, so slow older requests cannot overwrite newer ones.
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchSeq++;
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    await LocalExtensionRegistry.instance.load();
    final installed = LocalExtensionRegistry.instance.manifests;
    var market = const <ExtensionManifest>[];
    String? error;
    try {
      market = await MarketplaceRepository.instance.getTrending();
    } catch (e) {
      error = e is MarketplaceException
          ? e.message
          : 'Could not load the Marketplace.';
    }
    if (mounted) {
      setState(() {
        _installed = installed;
        _marketplace = market;
        _marketplaceError = error;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    _query = query.trim();
    _searchDebounce?.cancel();
    final seq = ++_searchSeq;
    _searchDebounce = Timer(
      kMarketplaceSearchDebounce,
      () => unawaited(_runSearch(query, seq)),
    );
  }

  Future<void> _runSearch(String query, int seq) async {
    try {
      final market = query.trim().isEmpty
          ? await MarketplaceRepository.instance.getTrending()
          : await MarketplaceRepository.instance.search(query);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _marketplace = market;
        _marketplaceError = null;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      showAppToast(
        context: context,
        message: e is MarketplaceException
            ? e.message
            : 'Marketplace search failed.',
        variant: AppToastVariant.error,
      );
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
        showAppToast(
          context: context,
          message: message,
          variant: AppToastVariant.error,
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

  Future<void> _installFromLocalFile() async {
    setState(() {
      _sideloading = true;
      _sideloadError = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Querya extension',
            extensions: ['zip', 'qext'],
          ),
        ],
      );
      if (file == null) return;

      if (!mounted) return;
      final request = await showExtensionSideloadDialog(
        context,
        archivePath: file.path,
      );
      if (request == null) return;

      await LocalExtensionInstaller().installFromPath(
        request.archivePath,
        expectedSha256: request.sha256Checksum,
      );
      await LocalExtensionRegistry.instance.reload();
      if (!mounted) return;
      setState(() {
        _installed = LocalExtensionRegistry.instance.manifests;
        _tabIndex = 0;
      });
    } on MarketplaceException catch (e) {
      if (mounted) setState(() => _sideloadError = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _sideloadError = 'Failed to install extension: $e');
      }
    } finally {
      if (mounted) setState(() => _sideloading = false);
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = context.colors;
    final onPopover = theme.popoverForeground;

    return material.DefaultTextStyle(
      style: material.TextStyle(color: onPopover),
      child: material.IconTheme(
        data: material.IconThemeData(color: onPopover),
        child: QueryaDialogCard(
          constraints: WindowLayout.dialogConstraints(
            context,
            maxWidth: 800,
            minWidth: 600,
            maxHeight: 700,
          ),
          borderColor: theme.border,
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
                          const Text('Extensions')
                              .large()
                              .semiBold()
                              .foreground(),
                          const material.SizedBox(height: 6),
                          const Text('Manage local and marketplace extensions')
                              .muted()
                              .small(),
                        ],
                      ),
                    ),
                    const material.SizedBox(width: 16),
                    QueryaButton.ghost(
                      label: 'Close',
                      onPressed: () => material.Navigator.of(context).pop(),
                      size: QueryaControlSize.lg,
                    ),
                  ],
                ),
              ),
              material.Padding(
                padding: const material.EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 8.0),
                child: QueryaTabStrip(
                  labels: [
                    'Installed (${_installed.length})',
                    'Marketplace',
                    'Updates',
                  ],
                  selectedIndex: _tabIndex,
                  onSelected: (index) => setState(() => _tabIndex = index),
                ),
              ),
              QueryaDivider(height: 1, color: theme.border),
              material.Expanded(
                child: QueryaCrossFadeStack(
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
    );
  }

  material.Widget _buildInstalledTab() {
    if (_loading) {
      return const material.Center(
        child: QueryaSpinner(size: QueryaSpinnerSize.lg),
      );
    }
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Padding(
          padding: const material.EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: material.Row(
            children: [
              QueryaButton.secondary(
                label: _sideloading ? 'Installing…' : 'Install from file…',
                onPressed: _sideloading ? null : _installFromLocalFile,
                size: QueryaControlSize.lg,
              ),
              const material.SizedBox(width: 12),
              material.Expanded(
                child: const Text(
                  'Install a local .zip or .qext package. Integrity verification '
                  'is optional — paste SHA-256 if the publisher provides one.',
                ).muted().small(),
              ),
            ],
          ),
        ),
        if (_sideloadError != null)
          material.Padding(
            padding: const material.EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(_sideloadError!).small(),
          ),
        material.Expanded(
          child: _installed.isEmpty
              ? const material.Center(
                  child: material.Padding(
                    padding: material.EdgeInsets.all(32.0),
                    child: Text(
                      'No extensions installed yet. Use Install from file… '
                      'or explore the Marketplace tab.',
                    ),
                  ),
                )
              : material.ListView.separated(
                  padding: const material.EdgeInsets.all(24),
                  itemCount: _installed.length,
                  separatorBuilder: (_, __) =>
                      const material.SizedBox(height: 16),
                  itemBuilder: (ctx, i) {
                    final manifest = _installed[i];
                    final isInstalling =
                        _installingProgress.containsKey(manifest.id);
                    final progress = _installingProgress[manifest.id];
                    return ExtensionCard(
                      manifest: manifest,
                      isInstalled: true,
                      isInstalling: isInstalling,
                      installProgress: progress,
                      onUninstall: () => _uninstallExtension(manifest),
                    );
                  },
                ),
        ),
      ],
    );
  }

  material.Widget _buildMarketplaceTab() {
    if (_loading) {
      return const material.Center(
        child: QueryaSpinner(size: QueryaSpinnerSize.lg),
      );
    }
    final theme = context.colors;
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
                  child:
                      const Text(ExtensionSupport.databaseDriverPreviewNotice)
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
            placeholder: const material.Text(
                'Search extensions by name, tag, or description...'),
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
          child: _marketplaceError != null && _marketplace.isEmpty
              ? _buildMarketplaceMessage(
                  'Could not load the Marketplace',
                  '$_marketplaceError',
                  retry: true,
                )
              : _marketplace.isEmpty
              ? (_query.isEmpty
                  ? _buildMarketplaceMessage(
                      'No extensions in the registry yet',
                      'Authors publish by adding a record to the extension '
                          'registry. You can still install an extension from a '
                          'file.',
                    )
                  : const material.Center(
                      child: material.Padding(
                        padding: material.EdgeInsets.all(32.0),
                        child:
                            Text('No extensions found matching your search.'),
                      ),
                    ))
              : material.ListView.separated(
                  padding: const material.EdgeInsets.all(24),
                  itemCount: _marketplace.length,
                  separatorBuilder: (_, __) =>
                      const material.SizedBox(height: 16),
                  itemBuilder: (ctx, i) {
                    final manifest = _marketplace[i];
                    final isInstalled =
                        _installed.any((e) => e.id == manifest.id);
                    final isInstalling =
                        _installingProgress.containsKey(manifest.id);
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

  material.Widget _buildMarketplaceMessage(
    String title,
    String detail, {
    bool retry = false,
  }) {
    return material.Center(
      child: material.Padding(
        padding: const material.EdgeInsets.all(32.0),
        child: material.ConstrainedBox(
          constraints: const material.BoxConstraints(maxWidth: 420),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              Text(title).semiBold(),
              const material.SizedBox(height: 8),
              Text(detail, textAlign: material.TextAlign.center)
                  .muted()
                  .small(),
              if (retry) ...[
                const material.SizedBox(height: 16),
                QueryaButton.secondary(
                  label: 'Retry',
                  onPressed: () => unawaited(_loadData()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  material.Widget _buildUpdatesTab() {
    if (_loading) {
      return const material.Center(
        child: QueryaSpinner(size: QueryaSpinnerSize.lg),
      );
    }
    final theme = context.colors;
    return material.Center(
      child: material.Padding(
        padding: const material.EdgeInsets.all(32.0),
        child: material.ConstrainedBox(
          constraints: const material.BoxConstraints(maxWidth: 420),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Icon(
                material.Icons.system_update_alt_rounded,
                size: 36,
                color: theme.mutedForeground,
              ),
              const material.SizedBox(height: 16),
              const Text('Extension update checks are not available yet')
                  .semiBold(),
              const material.SizedBox(height: 8),
              const Text(
                'Automatic update scanning ships with the Marketplace API. '
                'Until then, reinstall from Marketplace or from a local file '
                'to get a newer build.',
              ).muted().small(),
            ],
          ),
        ),
      ),
    );
  }
}
