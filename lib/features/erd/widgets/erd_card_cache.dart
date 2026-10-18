import 'dart:math' show min;

import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/features/erd/widgets/erd_card_inputs.dart';

/// The table cards of an open diagram, built only when something they show
/// changed, and a chunk per frame while a big diagram opens (#1546).
///
/// A rebuild of the diagram (a pick, a drag, a toolbar change) hands back the
/// same widget for every card whose [ErdCardInputs] are equal to the last
/// build's, so Flutter skips its subtree instead of rebuilding 200 cards.
class ErdCardCache {
  ErdCardCache({required this.isMounted, required this.rebuild});

  /// Above this many tables the first frame carries [mountChunk] of them and
  /// each following frame mounts [mountChunk] more.
  static const progressiveFrom = 60;
  static const mountChunk = 24;

  final bool Function() isMounted;
  final VoidCallback rebuild;

  var _byTable = <String, (ErdCardInputs, Widget)>{};
  int _mounted = 1 << 30;
  bool _pending = false;

  /// A diagram of [tableCount] tables was loaded: start over.
  void reset(int tableCount) {
    _byTable = {};
    _mounted = tableCount > progressiveFrom ? mountChunk : 1 << 30;
  }

  /// The cards of [tables] that are mounted so far, in order.
  List<Widget> cards({
    required List<ErdTable> tables,
    required ErdCardInputs Function(ErdTable table) inputsFor,
    required Widget Function(ErdTable table) build,
  }) {
    final shown = min(tables.length, _mounted);
    final next = <String, (ErdCardInputs, Widget)>{};
    final cards = <Widget>[];
    for (var i = 0; i < shown; i++) {
      final t = tables[i];
      final inputs = inputsFor(t);
      final cached = _byTable[t.name];
      final card = cached != null && cached.$1 == inputs ? cached.$2 : build(t);
      next[t.name] = (inputs, card);
      cards.add(card);
    }
    _byTable = next;
    if (shown < tables.length) _mountMore();
    return cards;
  }

  void _mountMore() {
    if (_pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!isMounted()) return;
      _mounted += mountChunk;
      rebuild();
    });
  }
}
