import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/ui/querya_icon_sizes.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';

void main() {
  group('QueryaIcons.connectionIcon', () {
    test('maps built-in connection types', () {
      expect(
        QueryaIcons.connectionIcon('postgresql'),
        material.Icons.storage_rounded,
      );
      expect(
        QueryaIcons.connectionIcon('mysql'),
        material.Icons.table_chart_rounded,
      );
      expect(
        QueryaIcons.connectionIcon('redis'),
        material.Icons.memory_rounded,
      );
      expect(
        QueryaIcons.connectionIcon('mongodb'),
        material.Icons.eco_rounded,
      );
      expect(
        QueryaIcons.connectionIcon('sqlite'),
        material.Icons.folder_open_rounded,
      );
    });

    test('falls back to extension icon for unknown types', () {
      expect(
        QueryaIcons.connectionIcon('clickhouse'),
        material.Icons.extension_rounded,
      );
    });
  });

  group('QueryaIcons.connectionAsset', () {
    test('returns bundled logos for known SQL/NoSQL drivers', () {
      expect(
        QueryaIcons.connectionAsset('postgresql'),
        'assets/images/postgresql_icon.png',
      );
      expect(QueryaIcons.connectionAsset('sqlite'), isNull);
    });
  });

  group('QueryaIcons.sduiNodeIcon', () {
    test('uses rounded tree icons for SDUI nodes', () {
      expect(
        QueryaIcons.sduiNodeIcon('database', expandable: false),
        QueryaIcons.database,
      );
      expect(
        QueryaIcons.sduiNodeIcon('table', expandable: true),
        QueryaIcons.tableGroup,
      );
      expect(
        QueryaIcons.sduiNodeIcon('table', expandable: false),
        QueryaIcons.tableLeaf,
      );
      expect(
        QueryaIcons.sduiNodeIcon('view', expandable: true),
        QueryaIcons.viewGroup,
      );
      expect(
        QueryaIcons.sduiNodeIcon('view', expandable: false),
        QueryaIcons.viewLeaf,
      );
      expect(
        QueryaIcons.sduiNodeIcon(null, expandable: true),
        QueryaIcons.folder,
      );
      expect(
        QueryaIcons.sduiNodeIcon(null, expandable: false),
        material.Icons.insert_drive_file_rounded,
      );
    });
  });

  test('tree size tokens are ordered leaf < group < sdui', () {
    expect(QueryaIconSizes.treeLeaf, lessThan(QueryaIconSizes.treeGroup));
    expect(QueryaIconSizes.treeGroup, lessThan(QueryaIconSizes.sduiNode));
  });
}
