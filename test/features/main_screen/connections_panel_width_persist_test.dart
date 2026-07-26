import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/main_screen/connections_panel_width_persist.dart';

void main() {
  test('discrete resize debounces and persists latest width', () async {
    final written = <double>[];
    final persist = ConnectionsPanelWidthPersist(
      write: (w) async => written.add(w),
      discreteDebounce: const Duration(milliseconds: 50),
    );

    var width = 200.0;
    persist.onDiscreteResize(() => width);
    width = 220;
    persist.onDiscreteResize(() => width);
    width = 240;
    persist.onDiscreteResize(() => width);

    expect(written, isEmpty);
    expect(persist.dirty, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(written, [240]);
    expect(persist.dirty, isFalse);
  });

  test('disposeFlush writes pending dirty width and cancels timer', () async {
    final written = <double>[];
    final persist = ConnectionsPanelWidthPersist(
      write: (w) async => written.add(w),
      discreteDebounce: const Duration(milliseconds: 500),
    );

    persist.onDiscreteResize(() => 310);
    expect(written, isEmpty);

    persist.disposeFlush(310);
    // Allow microtask/future from unawaited write.
    await Future<void>.delayed(Duration.zero);
    expect(written, [310]);
    expect(persist.dirty, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 520));
    expect(written, [310]);
  });

  test('disposeFlush is a no-op when not dirty', () async {
    final written = <double>[];
    final persist = ConnectionsPanelWidthPersist(
      write: (w) async => written.add(w),
    );

    persist.disposeFlush(999);
    await Future<void>.delayed(Duration.zero);
    expect(written, isEmpty);
  });

  test('cancelDiscreteTimer prevents delayed write', () async {
    final written = <double>[];
    final persist = ConnectionsPanelWidthPersist(
      write: (w) async => written.add(w),
      discreteDebounce: const Duration(milliseconds: 40),
    );

    persist.onDiscreteResize(() => 280);
    persist.cancelDiscreteTimer();
    // Still dirty — dispose/settle path should flush.
    expect(persist.dirty, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(written, isEmpty);

    await persist.persist(280);
    expect(written, [280]);
  });
}
