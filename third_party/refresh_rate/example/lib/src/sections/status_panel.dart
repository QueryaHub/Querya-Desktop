import 'package:flutter/material.dart';

import '../ui/panel_widgets.dart';

class StatusPanel extends StatelessWidget {
  const StatusPanel({
    super.key,
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelHeader(
            eyebrow: 'System',
            title: 'Run Status',
            subtitle:
                'Recent command state and what the console is currently signaling to the platform.',
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E0E),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: Color(0xFFE5E2E1),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
