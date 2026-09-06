import 'package:flutter/material.dart' as material;

/// Categorized sections of the [PreferencesDialog].
enum PreferencesCategory {
  general(
    id: 'general',
    label: 'General',
    description: 'Startup, updates, release channel',
    icon: material.Icons.tune_rounded,
  ),
  appearance(
    id: 'appearance',
    label: 'Appearance',
    description: 'Themes, dark mode, scaling, animations',
    icon: material.Icons.palette_outlined,
  ),
  sql(
    id: 'sql',
    label: 'SQL & Editor',
    description: 'Editor font, statement timeouts, query history',
    icon: material.Icons.terminal_rounded,
  ),
  dataGrid(
    id: 'dataGrid',
    label: 'Data Grid',
    description: 'Result rows limit, column sizing, safety',
    icon: material.Icons.table_chart_outlined,
  ),
  extensions(
    id: 'extensions',
    label: 'Extensions',
    description: 'Sideloading .qext/.zip packages, extension folder',
    icon: material.Icons.extension_outlined,
  ),
  shortcuts(
    id: 'shortcuts',
    label: 'Shortcuts',
    description: 'Keyboard shortcuts reference and keymap',
    icon: material.Icons.keyboard_outlined,
  ),
  about(
    id: 'about',
    label: 'About & Storage',
    description: 'App version, local SQLite storage, paths',
    icon: material.Icons.info_outline_rounded,
  );

  const PreferencesCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });

  final String id;
  final String label;
  final String description;
  final material.IconData icon;
}
