import 'dart:async';

import 'package:flutter/widgets.dart';

/// Starts/stops a [Timer.periodic] based on [TickerMode] (keep-alive morph).
///
/// Call from [State.build] or [State.didChangeDependencies]. When the ancestor
/// [TickerMode] is disabled (inactive [QueryaSwitchingBody] /
/// [QueryaCrossFadeStack] layer), the timer is cancelled so network polls do
/// not run offscreen. Re-enabling restarts the timer when [shouldRun] is true.
Timer? syncTickerGatedPeriodicTimer({
  required BuildContext context,
  required Timer? timer,
  required bool shouldRun,
  required Duration interval,
  required void Function() onTick,
}) {
  final active = TickerMode.valuesOf(context).enabled && shouldRun;
  if (!active) {
    timer?.cancel();
    return null;
  }
  return timer ?? Timer.periodic(interval, (_) => onTick());
}
