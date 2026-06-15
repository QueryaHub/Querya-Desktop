import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/display_refresh_service.dart';

void main() {
  group('displayRefreshOverlayEnabled', () {
    test('false in release or when flag unset', () {
      expect(
        DisplayRefreshService.displayRefreshOverlayEnabled(
          debugMode: false,
          overlayFlag: true,
        ),
        isFalse,
      );
      expect(
        DisplayRefreshService.displayRefreshOverlayEnabled(
          debugMode: true,
          overlayFlag: false,
        ),
        isFalse,
      );
    });

    test('true only in debug with QUERYA_REFRESH_OVERLAY', () {
      expect(
        DisplayRefreshService.displayRefreshOverlayEnabled(
          debugMode: true,
          overlayFlag: true,
        ),
        isTrue,
      );
    });
  });
}
