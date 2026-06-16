import 'extension_manifest.dart';

/// Future marketplace API client (mockable until backend exists).
///
/// See [docs/market-tech.md](https://github.com/QueryaHub/Querya-Desktop/blob/main/docs/market-tech.md).
abstract class MarketplaceClient {
  Future<List<ExtensionManifest>> searchExtensions({
    required String query,
    String? type,
  });
}

/// In-memory placeholder for local development and tests.
class MockMarketplaceClient implements MarketplaceClient {
  MockMarketplaceClient({List<ExtensionManifest>? seed})
      : _items = List<ExtensionManifest>.from(seed ?? const []);

  final List<ExtensionManifest> _items;

  @override
  Future<List<ExtensionManifest>> searchExtensions({
    required String query,
    String? type,
  }) async {
    final normalized = query.trim().toLowerCase();
    return _items.where((item) {
      if (type != null && item.type != type) return false;
      if (normalized.isEmpty) return true;
      return item.name.toLowerCase().contains(normalized) ||
          item.id.toLowerCase().contains(normalized);
    }).toList(growable: false);
  }
}
