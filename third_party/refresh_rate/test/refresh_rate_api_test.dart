import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/generated/refresh_rate_api.g.dart';
import 'package:refresh_rate/src/refresh_rate_api_adapter.dart';

class _FakeHostApi implements RefreshRateApiAdapter {
  final calls = <String>[];
  @override
  DisplayInfoMessage getDisplayInfo() => DisplayInfoMessage(
        currentRate: 120.0, maxRate: 120.0, minRate: 60.0,
        supportedRates: [60.0, 120.0], isVariableRefreshRate: true,
        engineTargetRate: 120.0, thermalStateIndex: 0,
      );

  @override void enable() { calls.add('enable'); }
  @override void disable() { calls.add('disable'); }
  @override void preferMax() { calls.add('preferMax'); }
  @override void preferDefault() { calls.add('preferDefault'); }
  @override void matchContent(double fps) { calls.add('matchContent:$fps'); }
  @override void boost(int durationMs) { calls.add('boost:$durationMs'); }
  @override void setCategory(int c) { calls.add('setCategory:$c'); }
  @override void setTouchBoost(bool e) { calls.add('setTouchBoost:$e'); }
  @override bool isSupported() => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeHostApi fakeApi;

  setUp(() {
    fakeApi = _FakeHostApi();
    RefreshRate.setApiForTesting(fakeApi);
  });

  tearDown(() => RefreshRate.clearApiForTesting());

  test('enable() calls platform enable', () async {
    RefreshRate.enable();
    expect(fakeApi.calls, contains('enable'));
  });

  test('preferMax() calls platform preferMax', () {
    RefreshRate.preferMax();
    expect(fakeApi.calls, contains('preferMax'));
  });

  test('matchContent passes fps to platform', () {
    RefreshRate.matchContent(24.0);
    expect(fakeApi.calls, contains('matchContent:24.0'));
  });

  test('category(high) calls setCategory(3)', () {
    RefreshRate.category(RateCategory.high);
    expect(fakeApi.calls, contains('setCategory:3'));
  });

  test('info returns fallback before first fetch', () {
    expect(RefreshRate.info.currentRate, isA<double>());
  });
}
