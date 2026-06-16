import 'package:flutter/material.dart';
import 'package:refresh_rate/refresh_rate.dart';

import '../ui/panel_widgets.dart';

class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.info,
    required this.status,
    required this.frameBudgetMs,
    required this.maxBudgetMs,
    required this.liveStateColor,
    required this.largeHero,
    required this.supportedRatesText,
  });

  final DisplayInfo info;
  final String status;
  final double frameBudgetMs;
  final double maxBudgetMs;
  final Color liveStateColor;
  final bool largeHero;
  final String supportedRatesText;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: PanelHeader(
                  eyebrow: 'refresh_rate v1.0',
                  title: 'Diagnostic Console',
                  subtitle:
                      'Live instrumentation for display state, frame budget, control requests, and benchmark sessions.',
                ),
              ),
              SignalBadge(
                label: status.toUpperCase(),
                color: liveStateColor,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              HeroMetric(
                label: 'Current Rate',
                value: '${info.currentRate.toStringAsFixed(1)} Hz',
                caption: 'Observed display target',
                accent: const Color(0xFF00F0FF),
                wide: largeHero,
              ),
              HeroMetric(
                label: 'Peak Capability',
                value: '${info.maxRate.toStringAsFixed(1)} Hz',
                caption: 'Device-reported maximum',
                accent: const Color(0xFF36FF8B),
                wide: largeHero,
              ),
              HeroMetric(
                label: 'Frame Budget',
                value: '${frameBudgetMs.toStringAsFixed(2)} ms',
                caption: frameBudgetMs > 0
                    ? 'Target at ${info.currentRate.toStringAsFixed(1)} Hz'
                    : 'Waiting for rate data',
                accent: const Color(0xFFFFBA20),
                wide: largeHero,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TelemetryChip(label: 'Supported', value: supportedRatesText),
              TelemetryChip(
                label: 'VRR',
                value: info.isVariableRefreshRate ? 'Enabled' : 'Fixed',
              ),
              TelemetryChip(
                label: 'Low Power',
                value: RefreshRate.isLowPowerMode ? 'On' : 'Off',
              ),
              TelemetryChip(
                label: 'Thermal',
                value: RefreshRate.thermalState.name,
              ),
              TelemetryChip(
                label: 'Peak Budget',
                value: maxBudgetMs > 0
                    ? '${maxBudgetMs.toStringAsFixed(2)} ms'
                    : 'n/a',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
