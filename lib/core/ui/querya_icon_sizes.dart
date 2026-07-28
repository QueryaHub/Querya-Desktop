/// Semantic icon sizes for connection trees and shared chrome.
abstract final class QueryaIconSizes {
  /// Leaf row icon (table name, view name, …).
  static const double treeLeaf = 12;

  /// Group / schema / default tree row icon.
  static const double treeGroup = 13;

  /// Expand chevron in tree rows.
  static const double treeExpand = 13;

  /// Expand chevron on connection / folder headers in the sidebar (#496).
  static const double sidebarExpand = 16;

  /// Connection-type icon / logo on sidebar header rows.
  static const double sidebarConnectionIcon = 16;

  /// Database / connection-level tree nodes.
  static const double treeConnection = 14;

  /// Inline tree error indicator.
  static const double treeError = 14;

  /// Menu / dialog leading icons.
  static const double menuLeading = 18;
}
