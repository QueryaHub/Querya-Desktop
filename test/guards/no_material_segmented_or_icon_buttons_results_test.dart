import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1162: results, charts, groupings and the MQL console use UI kit controls:
/// no Material segmented buttons and no bare Material icon buttons.
void main() {
  const scoped = [
    'lib/features/workspace/results_tab.dart',
    'lib/features/workspace/data_grid_groupings_view.dart',
    // Pulled into the results tab through its imports.
    'lib/features/workspace/data_grid_filter_bar.dart',
    'lib/features/workspace/data_grid_value_panel.dart',
    'lib/features/results/charts/quick_chart_view.dart',
    'lib/features/mongodb/mongo_query_workspace.dart',
  ];

  test('results, charts, groupings and the MQL console use UI kit controls', () {
    final banned = RegExp(r'\bmaterial\.(SegmentedButton|IconButton)\b');
    final offenders = <String>[
      for (final path in scoped)
        if (banned.hasMatch(File(path).readAsStringSync())) path,
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'Found Material segmented or icon buttons in: $offenders. '
          'Use QueryaTabStrip and QueryaIconButton instead.',
    );
  });
}
