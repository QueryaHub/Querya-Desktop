import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/ticker_gated_polling.dart';

void main() {
  testWidgets('cancels timer when TickerMode is disabled', (tester) async {
    Timer? timer;
    var ticks = 0;

    await tester.pumpWidget(
      TickerMode(
        enabled: true,
        child: Builder(
          builder: (context) {
            timer = syncTickerGatedPeriodicTimer(
              context: context,
              timer: timer,
              shouldRun: true,
              interval: const Duration(milliseconds: 20),
              onTick: () => ticks++,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(ticks, greaterThan(0));
    expect(timer, isNotNull);

    await tester.pumpWidget(
      TickerMode(
        enabled: false,
        child: Builder(
          builder: (context) {
            timer = syncTickerGatedPeriodicTimer(
              context: context,
              timer: timer,
              shouldRun: true,
              interval: const Duration(milliseconds: 20),
              onTick: () => ticks++,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final afterDisable = ticks;
    await tester.pump(const Duration(milliseconds: 60));
    expect(ticks, afterDisable);
    expect(timer, isNull);
  });
}
