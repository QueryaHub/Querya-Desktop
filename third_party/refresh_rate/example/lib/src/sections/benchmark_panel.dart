import 'package:flutter/material.dart';

import '../models/action_spec.dart';
import '../models/info_item.dart';
import '../ui/panel_widgets.dart';
import 'action_panel.dart';

class BenchmarkPanel extends StatelessWidget {
  const BenchmarkPanel({
    super.key,
    required this.actions,
    required this.reportItems,
  });

  final List<ActionSpec> actions;
  final List<InfoItem>? reportItems;

  @override
  Widget build(BuildContext context) {
    return ActionPanel(
      eyebrow: 'Benchmark',
      title: 'Session Capture',
      subtitle:
          'Run a named session, exercise scrolling or animations, then inspect verdict and missed-frame behavior.',
      actions: actions,
      footer: reportItems == null
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E0E),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'No report captured yet. Start a session, interact with the scroll test, then end the session to inspect the results.',
                style: TextStyle(
                  color: Color(0xFFB9CACB),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            )
          : ReportSummary(items: reportItems!),
    );
  }
}
