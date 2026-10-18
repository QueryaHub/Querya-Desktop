import 'package:querya_desktop/core/erd/erd_group_ops.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';

/// What the user has done to a diagram, apart from where the cards are:
/// the picked table and relation, marks, density, groups, notes and saved
/// views. No widgets and no layout geometry, so each rule is a plain method
/// that a unit test can call (#1690).
///
/// The view owns the layout, the routes and the viewport, and asks this for
/// the rest. Mutators change the state; the view decides when to rebuild and
/// to save.
class ErdViewController {
  /// The table being dragged.
  String? dragging;

  /// The table picked by a click or search: its edges stay highlighted.
  String? selected;

  /// A relation picked by a click on its edge (#1281): its two tables and
  /// columns are highlighted and its label stays until Esc.
  ErdRelation? pickedRelation;

  /// Tables marked with Shift / Ctrl / Cmd + click, to be grouped.
  final Set<String> marked = {};

  /// Density: only PK and FK columns, cards collapsed to their header, and
  /// tables hidden from the diagram.
  ErdDetail detail = ErdDetail.all;
  final Set<String> collapsed = {};
  final Set<String> hidden = {};

  /// Header colour picked per table (palette slot names, #1276).
  final Map<String, String> headerColors = {};

  /// The user's table groups, saved with the layout (#1282).
  final List<ErdGroup> groups = [];

  /// The group whose frame is being dragged by its title.
  String? draggingGroup;

  /// Sticky notes on the canvas, saved with the layout (#1283).
  final List<ErdNote> notes = [];
  String? draggingNote;

  /// Saved views of the diagram (#1284), the one the user is in, and the
  /// *All tables* state while a view is active.
  final List<ErdSavedView> views = [];
  String? activeView;
  ErdSavedLayout base = const ErdSavedLayout();

  /// Neighbours per table, for the focus of a hover or a pick.
  Map<String, Set<String>> neighbours = const {};

  /// Many-to-many link tables and what they link: `users and roles` (#1281).
  Map<String, String> junctions = const {};

  bool searchOpen = false;
  String query = '';
}
