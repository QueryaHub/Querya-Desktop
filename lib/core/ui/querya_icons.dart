import 'package:flutter/material.dart' as material;

/// Shared Material icon registry for connection trees and chrome.
abstract final class QueryaIcons {
  // -- Tree entity icons (rounded, aligned across PG / MySQL / SQLite) --

  static const material.IconData expandClosed =
      material.Icons.chevron_right_rounded;

  static const material.IconData databasesFolder =
      material.Icons.dns_rounded;
  static const material.IconData database = material.Icons.storage_rounded;
  static const material.IconData schemasFolder =
      material.Icons.account_tree_rounded;
  static const material.IconData schema = material.Icons.diamond_rounded;
  static const material.IconData extension = material.Icons.extension_rounded;
  static const material.IconData publicSchema = material.Icons.public_rounded;

  static const material.IconData tableGroup =
      material.Icons.table_chart_rounded;
  static const material.IconData tableLeaf = material.Icons.grid_on_rounded;
  static const material.IconData viewGroup = material.Icons.view_agenda_rounded;
  static const material.IconData viewLeaf = material.Icons.view_week_rounded;
  static const material.IconData materializedViewGroup =
      material.Icons.dynamic_feed_rounded;
  static const material.IconData functionGroup =
      material.Icons.functions_rounded;
  static const material.IconData functionLeaf = material.Icons.code_rounded;
  static const material.IconData sequence =
      material.Icons.format_list_numbered_rounded;
  static const material.IconData indexes = material.Icons.table_rows_rounded;
  static const material.IconData triggers = material.Icons.bolt_rounded;
  static const material.IconData types = material.Icons.category_rounded;

  static const material.IconData treeError =
      material.Icons.error_outline_rounded;
  static const material.IconData folder = material.Icons.folder_rounded;

  // -- Built-in connection types --

  static material.IconData connectionIcon(String type) => switch (type) {
        'mongodb' => material.Icons.eco_rounded,
        'postgresql' => material.Icons.storage_rounded,
        'mysql' => material.Icons.table_chart_rounded,
        'redis' => material.Icons.memory_rounded,
        'sqlite' => material.Icons.folder_open_rounded,
        _ => material.Icons.extension_rounded,
      };

  static String? connectionAsset(String type) => switch (type) {
        'postgresql' => 'assets/images/postgresql_icon.png',
        'mysql' => 'assets/images/mysql_icon.png',
        'redis' => 'assets/images/redis_icon.png',
        'mongodb' => 'assets/images/mongodb_icon.png',
        _ => null,
      };

  // -- SDUI tree nodes (rounded to match native trees) --

  static material.IconData sduiNodeIcon(
    String? icon, {
    required bool expandable,
  }) {
    switch (icon) {
      case 'database':
        return database;
      case 'table':
        return expandable ? tableGroup : tableLeaf;
      case 'view':
      case 'eye':
        return expandable ? viewGroup : viewLeaf;
      case 'folder':
      case 'folder-table':
        return folder;
      case 'folder-eye':
        return material.Icons.folder_special_rounded;
      case 'folder-book':
      case 'book':
        return material.Icons.menu_book_rounded;
      case 'columns':
        return material.Icons.view_column_rounded;
      case 'archive':
        return material.Icons.inventory_2_rounded;
      default:
        return expandable
            ? folder
            : material.Icons.insert_drive_file_rounded;
    }
  }
}
