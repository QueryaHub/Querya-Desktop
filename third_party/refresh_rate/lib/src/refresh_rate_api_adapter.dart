import 'dart:async';

import 'generated/refresh_rate_api.g.dart';

/// Abstract interface for the host API, used as the test seam.
///
/// The real implementation ([PigeonRefreshRateApiAdapter]) delegates to the
/// pigeon-generated [RefreshRateHostApi]. Tests implement this interface
/// directly with synchronous fakes — no await required.
abstract class RefreshRateApiAdapter {
  /// Fetches the latest display configuration.
  FutureOr<DisplayInfoMessage> getDisplayInfo();
  /// Enables High Refresh Rate overrides.
  FutureOr<void> enable();
  /// Disables High Refresh Rate overrides.
  FutureOr<void> disable();
  /// Requests the highest possible display refresh rate.
  FutureOr<void> preferMax();
  /// Resets to the system default refresh rate.
  FutureOr<void> preferDefault();
  /// Attempts to set the display refresh rate to match [fps].
  FutureOr<void> matchContent(double fps);
  /// Temporarily boosts the refresh rate for [durationMs].
  FutureOr<void> boost(int durationMs);
  /// Sets the refresh rate based on a given category.
  FutureOr<void> setCategory(int categoryIndex);
  /// Enables or disables automatic refresh rate boost on touch interactions.
  FutureOr<void> setTouchBoost(bool enabled);
  /// Checks whether the refresh rate overrides are supported by the platform.
  FutureOr<bool> isSupported();
}

/// Production implementation that delegates to the pigeon-generated channel.
class PigeonRefreshRateApiAdapter implements RefreshRateApiAdapter {
  final RefreshRateHostApi _pigeon;

  /// Creates a new [PigeonRefreshRateApiAdapter].
  PigeonRefreshRateApiAdapter() : _pigeon = RefreshRateHostApi();

  @override
  Future<DisplayInfoMessage> getDisplayInfo() => _pigeon.getDisplayInfo();

  @override
  Future<void> enable() => _pigeon.enable();

  @override
  Future<void> disable() => _pigeon.disable();

  @override
  Future<void> preferMax() => _pigeon.preferMax();

  @override
  Future<void> preferDefault() => _pigeon.preferDefault();

  @override
  Future<void> matchContent(double fps) => _pigeon.matchContent(fps);

  @override
  Future<void> boost(int durationMs) => _pigeon.boost(durationMs);

  @override
  Future<void> setCategory(int categoryIndex) => _pigeon.setCategory(categoryIndex);

  @override
  Future<void> setTouchBoost(bool enabled) => _pigeon.setTouchBoost(enabled);

  @override
  Future<bool> isSupported() => _pigeon.isSupported();
}
