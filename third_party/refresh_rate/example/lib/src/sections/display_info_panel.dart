import 'package:flutter/material.dart';

import '../models/info_item.dart';
import '../ui/panel_widgets.dart';

class DisplayInfoPanel extends StatelessWidget {
  const DisplayInfoPanel({
    super.key,
    required this.items,
  });

  final List<InfoItem> items;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelHeader(
            eyebrow: 'Telemetry',
            title: 'Display Info',
            subtitle:
                'Hardware capability, operating state, and platform-level diagnostics.',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 3
                  : constraints.maxWidth >= 560
                      ? 2
                      : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 76,
                ),
                itemBuilder: (context, index) => InfoTile(item: items[index]),
              );
            },
          ),
        ],
      ),
    );
  }
}
