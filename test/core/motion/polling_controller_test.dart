import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/polling_controller.dart';
import 'package:querya_desktop/shared/widgets/poll_stale_overlay.dart';

class _Host extends StatefulWidget {
  const _Host({required this.onTick});

  final VoidCallback onTick;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with PollingState<_Host> {
  @override
  Duration? get pollInterval => const Duration(milliseconds: 100);

  @override
  bool get pollShouldRun => true;

  @override
  Future<void> pollTick() async => widget.onTick();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  const second = Duration(seconds: 1);

  group('PollingController', () {
    testWidgets('a slow tick is never overlapped by the next one',
        (tester) async {
      var started = 0;
      var running = 0;
      var maxRunning = 0;
      final gate = <Completer<void>>[];
      final c = PollingController(
        interval: second,
        tick: () async {
          started++;
          running++;
          maxRunning = running > maxRunning ? running : maxRunning;
          final done = Completer<void>();
          gate.add(done);
          await done.future;
          running--;
        },
      );
      addTearDown(c.dispose);

      c.setActive(true);
      await tester.pump(second);
      expect(started, 1);

      await tester.pump(const Duration(seconds: 30));
      expect(started, 1, reason: 'no new request while one is in flight');

      gate.single.complete();
      await tester.pump();
      await tester.pump(second);
      expect(started, 2);
      expect(maxRunning, 1);
    });

    testWidgets('failures back off up to the cap and a success recovers',
        (tester) async {
      var calls = 0;
      var fail = true;
      final c = PollingController(
        interval: second,
        maxBackoff: const Duration(seconds: 5),
        tick: () async {
          calls++;
          if (fail) throw StateError('down');
        },
      );
      addTearDown(c.dispose);

      c.setActive(true);
      await tester.pump(second);
      expect(calls, 1);
      expect(c.status.value.failures, 1);
      expect(c.status.value.isStale, isTrue);
      expect(c.nextDelay, const Duration(seconds: 2));

      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1, reason: 'still backing off');
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
      expect(c.nextDelay, const Duration(seconds: 4));

      await tester.pump(const Duration(seconds: 4));
      expect(calls, 3);
      expect(c.nextDelay, const Duration(seconds: 5), reason: 'capped');

      fail = false;
      await tester.pump(const Duration(seconds: 5));
      expect(calls, 4);
      expect(c.status.value.isStale, isFalse);
      expect(c.status.value.lastSuccess, isNotNull);
      expect(c.nextDelay, second);
    });

    testWidgets('stopping while a tick runs does not schedule another',
        (tester) async {
      var calls = 0;
      final gate = Completer<void>();
      final c = PollingController(
        interval: second,
        tick: () async {
          calls++;
          await gate.future;
        },
      );
      addTearDown(c.dispose);

      c.setActive(true);
      await tester.pump(second);
      c.setActive(false);
      gate.complete();
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 1);
      expect(c.isActive, isFalse);
    });

    testWidgets('a result that lands after a stop is not reported',
        (tester) async {
      final gate = Completer<void>();
      final c = PollingController(
        interval: second,
        tick: () async {
          await gate.future;
          throw StateError('late');
        },
      );
      addTearDown(c.dispose);

      c.setActive(true);
      await tester.pump(second);
      c.setActive(false);
      c.reset();
      gate.complete();
      await tester.pump();
      expect(c.status.value.failures, 0);
    });

    testWidgets('changing the interval reschedules', (tester) async {
      var calls = 0;
      final c = PollingController(interval: second, tick: () async => calls++);
      addTearDown(c.dispose);

      c.setActive(true);
      c.setInterval(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, 1);
    });
  });

  group('PollingState', () {
    testWidgets('polls only under an enabled TickerMode', (tester) async {
      var ticks = 0;
      Widget app({required bool enabled}) => TickerMode(
            enabled: enabled,
            child: _Host(onTick: () => ticks++),
          );

      await tester.pumpWidget(app(enabled: true));
      await tester.pump(const Duration(milliseconds: 350));
      expect(ticks, greaterThan(0));

      await tester.pumpWidget(app(enabled: false));
      final frozen = ticks;
      await tester.pump(const Duration(seconds: 1));
      expect(ticks, frozen);

      await tester.pumpWidget(app(enabled: true));
      await tester.pump(const Duration(milliseconds: 150));
      expect(ticks, greaterThan(frozen));
    });

    testWidgets('stops when the view is disposed', (tester) async {
      var ticks = 0;
      await tester.pumpWidget(_Host(onTick: () => ticks++));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(const SizedBox.shrink());
      final after = ticks;
      await tester.pump(const Duration(seconds: 1));
      expect(ticks, after);
    });
  });

  group('PollStaleOverlay', () {
    testWidgets('shows the note only while the latest poll failed',
        (tester) async {
      final status = ValueNotifier(const PollStatus());
      await tester.pumpWidget(MaterialApp(
        home: PollStaleOverlay(status: status, child: const SizedBox()),
      ));
      expect(find.byKey(const ValueKey('poll_stale_hint')), findsNothing);

      status.value = PollStatus(
        lastSuccess: DateTime(2026, 1, 1, 9, 5, 7),
        lastError: 'boom',
        failures: 2,
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('poll_stale_hint')), findsOneWidget);
      expect(find.textContaining('09:05:07'), findsOneWidget);

      status.value = PollStatus(lastSuccess: DateTime(2026, 1, 1, 9, 6));
      await tester.pump();
      expect(find.byKey(const ValueKey('poll_stale_hint')), findsNothing);
    });
  });
}
