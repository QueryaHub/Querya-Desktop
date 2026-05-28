// Supported VS Code `colors` keys → Querya workbench / editor tokens.
// Unknown keys are ignored; see kSupportedVsCodeColorKeys and docs/theme-import.md.

/// Workbench token updated from a VS Code color key.
enum VsCodeWorkbenchField {
  canvas,
  surface,
  sidebarBackground,
  editorBackground,
  borderSubtle,
  accent,
  mutedForeground,
  gitModified,
  gitUntracked,
}

/// Editor token updated from a VS Code color key.
enum VsCodeEditorField {
  background,
  foreground,
  selection,
  lineNumber,
  bracketMatch,
  widgetBorder,
}

/// Optional direct [ColorScheme] fields (shadcn) beyond workbench derivation.
enum VsCodeColorSchemeField {
  foreground,
  background,
  card,
  border,
  input,
  ring,
  mutedForeground,
  accent,
}

/// Maps one VS Code `colors` entry to Querya tokens.
class VsCodeColorTarget {
  const VsCodeColorTarget.workbench(this.workbench)
      : editor = null,
        colorScheme = null;

  const VsCodeColorTarget.editor(this.editor)
      : workbench = null,
        colorScheme = null;

  const VsCodeColorTarget.scheme(this.colorScheme)
      : workbench = null,
        editor = null;

  final VsCodeWorkbenchField? workbench;
  final VsCodeEditorField? editor;
  final VsCodeColorSchemeField? colorScheme;
}

/// VS Code key → Querya target. Keys not listed are ignored.
const Map<String, VsCodeColorTarget> kVsCodeColorMap = {
  'editor.background': VsCodeColorTarget.workbench(
    VsCodeWorkbenchField.editorBackground,
  ),
  'editor.foreground': VsCodeColorTarget.editor(VsCodeEditorField.foreground),
  'editor.selectionBackground': VsCodeColorTarget.editor(
    VsCodeEditorField.selection,
  ),
  'editorLineNumber.foreground': VsCodeColorTarget.editor(
    VsCodeEditorField.lineNumber,
  ),
  'editorBracketMatch.background': VsCodeColorTarget.editor(
    VsCodeEditorField.bracketMatch,
  ),
  'editorWidget.border': VsCodeColorTarget.editor(
    VsCodeEditorField.widgetBorder,
  ),
  'sideBar.background': VsCodeColorTarget.workbench(
    VsCodeWorkbenchField.sidebarBackground,
  ),
  'sideBar.foreground': VsCodeColorTarget.workbench(
    VsCodeWorkbenchField.mutedForeground,
  ),
  'activityBar.background': VsCodeColorTarget.workbench(
    VsCodeWorkbenchField.canvas,
  ),
  'tab.activeBackground': VsCodeColorTarget.workbench(
    VsCodeWorkbenchField.surface,
  ),
  'statusBar.background': VsCodeColorTarget.workbench(
    VsCodeWorkbenchField.canvas,
  ),
  'panel.background': VsCodeColorTarget.workbench(
    VsCodeWorkbenchField.surface,
  ),
  'focusBorder': VsCodeColorTarget.workbench(VsCodeWorkbenchField.accent),
  'input.background': VsCodeColorTarget.workbench(VsCodeWorkbenchField.surface),
  'list.hoverBackground': VsCodeColorTarget.scheme(
    VsCodeColorSchemeField.accent,
  ),
  'gitDecoration.modifiedResourceForeground': VsCodeColorTarget.workbench(
    VsCodeWorkbenchField.gitModified,
  ),
  'gitDecoration.untrackedResourceForeground': VsCodeColorTarget.workbench(
    VsCodeWorkbenchField.gitUntracked,
  ),
};

/// Documented subset of supported VS Code keys (stable API).
const List<String> kSupportedVsCodeColorKeys = [
  'editor.background',
  'editor.foreground',
  'editor.selectionBackground',
  'editorLineNumber.foreground',
  'editorBracketMatch.background',
  'editorWidget.border',
  'sideBar.background',
  'sideBar.foreground',
  'activityBar.background',
  'tab.activeBackground',
  'statusBar.background',
  'panel.background',
  'focusBorder',
  'input.background',
  'list.hoverBackground',
  'gitDecoration.modifiedResourceForeground',
  'gitDecoration.untrackedResourceForeground',
];
