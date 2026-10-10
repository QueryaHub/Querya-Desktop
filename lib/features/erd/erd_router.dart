import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';

/// One routed relation: an orthogonal polyline from the FK column row of
/// [relation]'s `fromTable` to the referenced column row of `toTable`.
class ErdRoute {
  const ErdRoute(this.relation, this.points);

  final ErdRelation relation;

  /// First point on the FK card's edge, last on the referenced card's edge.
  final List<Offset> points;
}

/// Orthogonal edge router: A* over a sparse grid made of the card borders
/// (inflated by [clearance]) and the column rows, with a penalty per bend, so
/// edges go around cards. Overlapping parallel segments are then spread
/// apart ("nudged") so they do not draw on top of each other.
abstract final class ErdRouter {
  /// Free space kept around every card.
  static const double clearance = 14;
  static const double _bendCost = 60;
  static const double _nudgeStep = 6;

  static List<ErdRoute> route(ErdSchema schema, ErdLayout layout) {
    final byName = {for (final t in schema.tables) t.name: t};
    final relations = [
      for (final r in schema.relations)
        if (byName.containsKey(r.fromTable) && byName.containsKey(r.toTable)) r,
    ];
    if (relations.isEmpty) return const [];

    final rects = [
      for (final t in schema.tables) layout.rectOf(t).inflate(clearance),
    ];

    // Ports: both sides of each end, at the column row.
    final ports = <_Ends>[];
    final xs = <double>{}, ys = <double>{};
    for (final r in rects) {
      xs..add(r.left)..add(r.right);
      ys..add(r.top)..add(r.bottom);
    }
    for (final rel in relations) {
      final from = byName[rel.fromTable]!, to = byName[rel.toTable]!;
      final fr = layout.rectOf(from), tr = layout.rectOf(to);
      final fy = layout.columnY(from, rel.fromColumn);
      final ty = layout.columnY(to, rel.toColumn);
      ports.add(_Ends(fr, fy, tr, ty));
      ys..add(fy)..add(ty);
    }
    final grid = _Grid(_withMidpoints(xs), _withMidpoints(ys), rects);

    final routes = <List<Offset>>[];
    for (var i = 0; i < relations.length; i++) {
      routes.add(_routeOne(grid, ports[i], relations[i].fromTable == relations[i].toTable));
    }
    _nudge(routes);
    return [
      for (var i = 0; i < relations.length; i++) ErdRoute(relations[i], routes[i]),
    ];
  }

  static List<double> _withMidpoints(Set<double> values) {
    final sorted = values.toList()..sort();
    final out = <double>[];
    for (var i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 2 * clearance) {
        out.add((sorted[i] + sorted[i - 1]) / 2);
      }
      out.add(sorted[i]);
    }
    return out;
  }

  static List<Offset> _routeOne(_Grid g, _Ends e, bool self) {
    // Start: leave the FK card left or right; goal: enter the target likewise.
    final starts = <(Offset port, Offset stub, int dir)>[
      (Offset(e.from.left, e.fromY), Offset(e.from.left - clearance, e.fromY), _left),
      (Offset(e.from.right, e.fromY), Offset(e.from.right + clearance, e.fromY), _right),
    ];
    final goals = <(Offset port, Offset stub, int dir)>[
      (Offset(e.to.left, e.toY), Offset(e.to.left - clearance, e.toY), _right),
      (Offset(e.to.right, e.toY), Offset(e.to.right + clearance, e.toY), _left),
    ];
    final path = g.search(
      [for (final s in starts) (s.$2, s.$3)],
      [for (final t in goals) (t.$2, t.$3)],
      bendCost: _bendCost,
    );
    if (path == null) {
      // No free path (cards overlap): straight dog-leg between the near sides.
      final s = e.from.center.dx <= e.to.center.dx ? starts[1] : starts[0];
      final t = e.from.center.dx <= e.to.center.dx ? goals[0] : goals[1];
      final midX = (s.$2.dx + t.$2.dx) / 2;
      return _simplify([
        s.$1, s.$2, Offset(midX, s.$2.dy), Offset(midX, t.$2.dy), t.$2, t.$1,
      ]);
    }
    final (points, startIndex, goalIndex) = path;
    return _simplify([starts[startIndex].$1, ...points, goals[goalIndex].$1]);
  }

  static List<Offset> _simplify(List<Offset> pts) {
    final out = <Offset>[];
    for (final p in pts) {
      if (out.isNotEmpty && (out.last - p).distance < 0.01) continue;
      if (out.length >= 2) {
        final a = out[out.length - 2], b = out.last;
        final collinear = (a.dx == b.dx && b.dx == p.dx) ||
            (a.dy == b.dy && b.dy == p.dy);
        if (collinear) {
          out[out.length - 1] = p;
          continue;
        }
      }
      out.add(p);
    }
    return out;
  }

  /// Spreads segments that share a grid line and overlap. The first and last
  /// segments (attached to column rows) never move.
  static void _nudge(List<List<Offset>> routes) {
    final groups = <String, List<(int route, int seg, double lo, double hi)>>{};
    for (var r = 0; r < routes.length; r++) {
      final pts = routes[r];
      for (var s = 1; s < pts.length - 2; s++) {
        final a = pts[s], b = pts[s + 1];
        if (a.dx == b.dx) {
          groups.putIfAbsent('v${a.dx}', () => []).add(
              (r, s, math.min(a.dy, b.dy), math.max(a.dy, b.dy)));
        } else if (a.dy == b.dy) {
          groups.putIfAbsent('h${a.dy}', () => []).add(
              (r, s, math.min(a.dx, b.dx), math.max(a.dx, b.dx)));
        }
      }
    }
    for (final entry in groups.entries) {
      final vertical = entry.key.startsWith('v');
      final segs = entry.value..sort((a, b) => a.$3.compareTo(b.$3));
      // Clusters of overlapping intervals.
      var cluster = <(int, int, double, double)>[];
      var end = double.negativeInfinity;
      void flush() {
        if (cluster.length > 1) {
          final n = cluster.length;
          final step = math.min(_nudgeStep, (2 * (clearance - 4)) / (n - 1));
          for (var k = 0; k < n; k++) {
            final off = (k - (n - 1) / 2) * step;
            final (r, s, _, _) = cluster[k];
            final pts = routes[r];
            pts[s] = vertical
                ? Offset(pts[s].dx + off, pts[s].dy)
                : Offset(pts[s].dx, pts[s].dy + off);
            pts[s + 1] = vertical
                ? Offset(pts[s + 1].dx + off, pts[s + 1].dy)
                : Offset(pts[s + 1].dx, pts[s + 1].dy + off);
          }
        }
        cluster = [];
      }

      for (final seg in segs) {
        if (seg.$3 >= end - 0.5) flush();
        cluster.add(seg);
        end = cluster.length == 1 ? seg.$4 : math.max(end, seg.$4);
      }
      flush();
    }
  }
}

const _left = 0, _right = 1, _up = 2, _down = 3;

class _Ends {
  _Ends(this.from, this.fromY, this.to, this.toY);
  final Rect from, to;
  final double fromY, toY;
}

/// Sparse orthogonal visibility grid.
///
/// Obstacles are rasterized once: a node or a grid segment inside a card is
/// marked blocked, so the search asks O(1) questions instead of testing every
/// card for every expansion. The marks use the same strict bounds as the
/// point test they replace.
class _Grid {
  _Grid(this.xs, this.ys, this.rects) {
    final w = xs.length, h = ys.length;
    _node = Uint8List(w * h);
    // Horizontal segment from node i to i+1 in row j: index i * h + j.
    _hSeg = Uint8List(math.max(0, w - 1) * h);
    // Vertical segment from node j to j+1 in column i: index i * (h - 1) + j.
    _vSeg = Uint8List(w * math.max(0, h - 1));
    final xm = [for (var i = 0; i + 1 < w; i++) (xs[i] + xs[i + 1]) / 2];
    final ym = [for (var j = 0; j + 1 < h; j++) (ys[j] + ys[j + 1]) / 2];
    for (final r in rects) {
      final xLo = _upperBound(xs, r.left + 0.01);
      final xHi = _lowerBound(xs, r.right - 0.01);
      final yLo = _upperBound(ys, r.top + 0.01);
      final yHi = _lowerBound(ys, r.bottom - 0.01);
      for (var i = xLo; i < xHi; i++) {
        for (var j = yLo; j < yHi; j++) {
          _node[i * h + j] = 1;
        }
      }
      // Horizontal segments: midpoint x inside the card, row inside it.
      final mxLo = _upperBound(xm, r.left + 0.01);
      final mxHi = _lowerBound(xm, r.right - 0.01);
      for (var k = mxLo; k < mxHi; k++) {
        for (var j = yLo; j < yHi; j++) {
          _hSeg[k * h + j] = 1;
        }
      }
      // Vertical segments: column inside the card, midpoint y inside it.
      final myLo = _upperBound(ym, r.top + 0.01);
      final myHi = _lowerBound(ym, r.bottom - 0.01);
      for (var i = xLo; i < xHi; i++) {
        for (var k = myLo; k < myHi; k++) {
          _vSeg[i * (h - 1) + k] = 1;
        }
      }
    }
  }

  final List<double> xs, ys;
  final List<Rect> rects;
  late final Uint8List _node;

  // Search state, one entry per (cell, direction). Sized lazily on first search.
  late final int _states = xs.length * ys.length * 4;
  late final Float64List _cost = Float64List(_states);
  late final Int32List _prev = Int32List(_states);
  late final Int32List _startOf = Int32List(_states);
  late final Int32List _stamp = Int32List(_states);
  late final Int32List _closed = Int32List(_states);
  int _generation = 0;
  late final Uint8List _hSeg;
  late final Uint8List _vSeg;

  bool _blockedNode(int i, int j) => _node[i * ys.length + j] == 1;

  /// Whether the grid segment leaving node (i, j) in direction [d] is blocked.
  bool _blockedSegment(int i, int j, int d) {
    final h = ys.length;
    switch (d) {
      case _left:
        return _hSeg[(i - 1) * h + j] == 1;
      case _right:
        return _hSeg[i * h + j] == 1;
      case _up:
        return _vSeg[i * (h - 1) + (j - 1)] == 1;
      default:
        return _vSeg[i * (h - 1) + j] == 1;
    }
  }

  /// First index whose value is >= [v].
  static int _lowerBound(List<double> v, double x) {
    var lo = 0, hi = v.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (v[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// First index whose value is > [v].
  static int _upperBound(List<double> v, double x) {
    var lo = 0, hi = v.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (v[mid] <= x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  int _ix(double x) => _index(xs, x);
  int _iy(double y) => _index(ys, y);

  static int _index(List<double> v, double x) {
    var lo = 0, hi = v.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if ((v[mid] - x).abs() < 0.01) return mid;
      if (v[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  /// A* from any start (point, direction it leaves in) to any goal (point,
  /// direction it must arrive in). Returns grid points, start and goal index.
  (List<Offset>, int, int)? search(
    List<(Offset, int)> starts,
    List<(Offset, int)> goals, {
    required double bendCost,
  }) {
    final w = xs.length, h = ys.length;
    int key(int i, int j, int d) => ((i * h) + j) * 4 + d;
    final goalAt = <int, (int goalIndex, int dir)>{};
    for (var g = 0; g < goals.length; g++) {
      final i = _ix(goals[g].$1.dx), j = _iy(goals[g].$1.dy);
      if (i < 0 || j < 0 || _blockedNode(i, j)) continue;
      goalAt[i * h + j] = (g, goals[g].$2);
    }
    if (goalAt.isEmpty) return null;

    double heuristic(int i, int j) {
      var best = double.infinity;
      for (final g in goals) {
        final d = (xs[i] - g.$1.dx).abs() + (ys[j] - g.$1.dy).abs();
        if (d < best) best = d;
      }
      return best;
    }

    // Per-state data lives in flat arrays shared by every search of this grid.
    // An entry is valid only when its stamp is the current search's generation,
    // so nothing is cleared between searches.
    final gen = ++_generation;
    double costOf(int k) => _stamp[k] == gen ? _cost[k] : double.infinity;
    void setCost(int k, double c) {
      _stamp[k] = gen;
      _cost[k] = c;
    }

    final heap = _Heap();
    for (var s = 0; s < starts.length; s++) {
      final i = _ix(starts[s].$1.dx), j = _iy(starts[s].$1.dy);
      if (i < 0 || j < 0 || _blockedNode(i, j)) continue;
      final k = key(i, j, starts[s].$2);
      setCost(k, 0);
      _prev[k] = -1;
      _startOf[k] = s;
      heap.push(k, heuristic(i, j));
    }

    // A goal is final once nothing cheaper is left in the heap (f >= g).
    var bestCost = double.infinity;
    int? bestKey;
    var bestGoal = -1;
    var expanded = 0;
    while (heap.isNotEmpty) {
      if (heap.peekPriority >= bestCost) break;
      final k = heap.pop();
      if (_closed[k] == gen) continue;
      _closed[k] = gen;
      if (++expanded > w * h * 4) break;
      final d = k % 4, cell = k ~/ 4, i = cell ~/ h, j = cell % h;
      final c = _cost[k];
      final goal = goalAt[cell];
      if (goal != null) {
        final want = goal.$2;
        final opposite = (d ^ want) == 1 && (d >> 1) == (want >> 1);
        final total = c + (d == want ? 0 : opposite ? 2 * bendCost : bendCost);
        if (total < bestCost) {
          bestCost = total;
          bestKey = k;
          bestGoal = goal.$1;
        }
      }
      for (final nd in const [_left, _right, _up, _down]) {
        final ni = i + (nd == _left ? -1 : nd == _right ? 1 : 0);
        final nj = j + (nd == _up ? -1 : nd == _down ? 1 : 0);
        if (ni < 0 || nj < 0 || ni >= w || nj >= h || _blockedNode(ni, nj)) continue;
        // No U-turns.
        if ((d == _left && nd == _right) ||
            (d == _right && nd == _left) ||
            (d == _up && nd == _down) ||
            (d == _down && nd == _up)) {
          continue;
        }
        final a = Offset(xs[i], ys[j]), b = Offset(xs[ni], ys[nj]);
        if (_blockedSegment(i, j, nd)) continue;
        final nc = c + (a - b).distance + (nd == d ? 0 : bendCost);
        final nk = key(ni, nj, nd);
        if (nc < costOf(nk)) {
          setCost(nk, nc);
          _prev[nk] = k;
          heap.push(nk, nc + heuristic(ni, nj));
        }
      }
    }
    final end = bestKey;
    if (end == null) return null;
    final pts = <Offset>[];
    var cur = end;
    while (true) {
      final cc = cur ~/ 4;
      pts.add(Offset(xs[cc ~/ h], ys[cc % h]));
      final p = _prev[cur];
      if (p < 0) break;
      cur = p;
    }
    return (pts.reversed.toList(), _startOf[cur], bestGoal);
  }
}

/// Binary min-heap of (key, priority).
class _Heap {
  final _keys = <int>[];
  final _prio = <double>[];

  bool get isNotEmpty => _keys.isNotEmpty;
  bool get isEmpty => _keys.isEmpty;
  double get peekPriority => _prio.first;

  void push(int k, double p) {
    _keys.add(k);
    _prio.add(p);
    var i = _keys.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_prio[parent] <= _prio[i]) break;
      _swap(i, parent);
      i = parent;
    }
  }

  int pop() {
    final top = _keys.first;
    final lastK = _keys.removeLast(), lastP = _prio.removeLast();
    if (_keys.isNotEmpty) {
      _keys[0] = lastK;
      _prio[0] = lastP;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _keys.length && _prio[l] < _prio[m]) m = l;
        if (r < _keys.length && _prio[r] < _prio[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final k = _keys[a];
    _keys[a] = _keys[b];
    _keys[b] = k;
    final p = _prio[a];
    _prio[a] = _prio[b];
    _prio[b] = p;
  }
}
