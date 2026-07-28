/// Shared UI: re-exports of shadcn_flutter widgets used across the app.
/// Import this file to avoid duplicating imports.
///
/// Frequently used widgets:
/// - Card, PrimaryButton, OutlineButton, GhostButton
/// - Tabs, TabItem, IndexedStack
/// - TextField, Text (with .semiBold(), .muted(), .small())
/// - Gap, VerticalDivider
library;

export 'app_dialog.dart';
export 'app_toast.dart';
export 'export_menu_button.dart';
export 'querya_dialog_card.dart';
export 'querya_tab_strip.dart';
export 'querya_dropdown.dart'
    show
        QueryaDropdown,
        QueryaDropdownItem,
        QueryaDropdownTokens,
        kPreferencesLabelWidth;
export 'tree_load_error.dart';
export 'package:shadcn_flutter/shadcn_flutter.dart';
