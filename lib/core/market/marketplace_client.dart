import 'extension_manifest.dart';
import 'marketplace_repository.dart';

/// Future marketplace API client (mockable until backend exists).
///
/// See [docs/market-tech.md](https://github.com/QueryaHub/Querya-Desktop/blob/main/docs/market-tech.md).
abstract class MarketplaceClient {
  Future<List<ExtensionManifest>> searchExtensions({
    required String query,
    String? type,
  });
}

/// In-memory placeholder for local development and tests that delegates to [MarketplaceRepository].
class MockMarketplaceClient implements MarketplaceClient {
  MockMarketplaceClient({List<ExtensionManifest>? seed})
      : _repository = MockMarketplaceRepository(seed: seed);

  final MockMarketplaceRepository _repository;

  @override
  Future<List<ExtensionManifest>> searchExtensions({
    required String query,
    String? type,
  }) async {
    return _repository.search(query);
  }
}

