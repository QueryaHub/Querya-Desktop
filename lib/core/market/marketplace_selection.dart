import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'marketplace_repository.dart';
import 'static_registry_repository.dart';

/// `--dart-define=QUERYA_MARKETPLACE_INDEX=<url>`: read another registry index
/// (a fork, a test registry; `http://localhost` is accepted in debug builds).
const _indexUrl = String.fromEnvironment(
  'QUERYA_MARKETPLACE_INDEX',
  defaultValue: StaticRegistryRepository.defaultIndexUrl,
);

/// `--dart-define=QUERYA_MARKETPLACE_MOCK=true`: the built-in demo catalog, for
/// working on the Marketplace page without a registry. Never in a release.
const _useMock = bool.fromEnvironment('QUERYA_MARKETPLACE_MOCK');

/// Chooses the Marketplace catalog once, at startup. The app lists and installs
/// what the extension registry publishes; nothing else reaches users.
Future<void> installMarketplaceRepository() async {
  if (_useMock) {
    assert(kDebugMode || kProfileMode, 'the demo catalog is not for releases');
    return; // MarketplaceRepository.instance stays the demo catalog.
  }
  var version = '0.0.0';
  try {
    version = (await PackageInfo.fromPlatform()).version;
  } catch (e) {
    // Nothing is compatible with 0.0.0, so an unreadable version shows an empty
    // catalog rather than extensions that might not run.
    debugPrint('Marketplace: could not read the app version: $e');
  }
  MarketplaceRepository.instance = StaticRegistryRepository(
    indexUrl: _indexUrl,
    hostVersion: version,
  );
}
