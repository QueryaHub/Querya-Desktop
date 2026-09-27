// ignore_for_file: depend_on_referenced_packages, invalid_use_of_visible_for_testing_member
//
// Frame-timing benchmark for the real Querya shell, driven through the Demo
// Playground (SQLite) so no external database is needed. Run in profile mode:
//   flutter run --profile -d linux -t benchmark/app_perf_bench.dart
// Optional: --dart-define=ONLY=scroll_v,typing   (comma list of scenario ids)
//           --dart-define=PROFILE=true           (CPU + engine timeline per scenario)
//
// App data goes to a throwaway directory, never to the user's profile.
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:querya_desktop/app/app.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/editor/syntax_highlight_service.dart';
import 'package:querya_desktop/core/layout/ui_scale_controller.dart';
import 'package:querya_desktop/core/motion/display_refresh_service.dart';
import 'package:querya_desktop/core/motion/querya_motion_controller.dart';
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';
import 'package:vm_service/vm_service.dart' as vms;
import 'package:vm_service/vm_service_io.dart' as vms_io;

const only = String.fromEnvironment('ONLY');
const profile = bool.fromEnvironment('PROFILE');

/// With PROFILE: print the Dart callers of samples whose stack mentions this.
const callersOf = String.fromEnvironment('CALLERS');

/// Timeline streams to record ('' = none: no timeline cost at all).
const streams = String.fromEnvironment('STREAMS', defaultValue: 'Embedder,GC');

final _timings = <FrameTiming>[];
vms.VmService? _vm;
String? _isolateId;

const heavySql = '''
WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 5000)
SELECT x AS id, x * 7 % 1000 AS amount, 'customer ' || (x % 311) AS customer,
  'user' || x || '@example.com' AS email, (x % 5) AS bucket,
  CASE x % 3 WHEN 0 THEN 'active' WHEN 1 THEN 'pending' ELSE 'failed' END AS status,
  datetime(1700000000 + x * 3600, 'unixepoch') AS created_at,
  printf('%08d', x * 13) AS code, x * 0.37 AS ratio, 'note number ' || x AS note,
  x % 97 AS a1, x % 89 AS a2, x % 83 AS a3, x % 79 AS a4, x % 73 AS a5,
  x % 71 AS a6, x % 67 AS a7, x % 61 AS a8, x % 59 AS a9, x % 53 AS a10
FROM n;
''';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dataDir = await Directory.systemTemp.createTemp('querya_perf_');
  AppDataRoot.mockPortableRootPath = dataDir.path;
  // Never touch the OS keyring: the throwaway DB reuses low connection ids.
  ConnectionSecretsStore.backend = _MemorySecrets();

  DisplayRefreshService.initialize();
  await LocalDb.initFfi();
  await SyntaxHighlightService.ensureInitialized();
  await ThemeController.instance.load();
  await UiScaleController.instance.load();
  await QueryaMotionController.instance.load();
  await AppSettings.instance.setHasCompletedWelcomeTour(true);
  await _seedBigSchema(dataDir.path);
  SchedulerBinding.instance.addTimingsCallback(_timings.addAll);
  runApp(const QueryaApp());

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await _runAll();
    } catch (e, st) {
      stdout.writeln('BENCH error: $e\n$st');
    }
    await dataDir.delete(recursive: true).catchError((_) => dataDir);
    exit(0);
  });
}

// ---------------------------------------------------------------- scenarios

Future<void> _runAll() async {
  await _wait(2000);
  final view = PlatformDispatcher.instance.views.first;
  stdout.writeln('BENCH window=${view.physicalSize.width.toInt()}x'
      '${view.physicalSize.height.toInt()} dpr=${view.devicePixelRatio} '
      'semantics=${SemanticsBinding.instance.semanticsEnabled} '
      'displayHz=${view.display.refreshRate}');
  await _connectVm();

  await _scenario('idle_empty', () => _wait(1500));

  await _tap(_byKey('empty_try_demo_playground'));
  await _waitFor(() => SqlEditorCommandBridge.instance.canExecute, 'SQL workspace');
  await _wait(1500);
  await _scenario('idle_workspace', () => _wait(1500));

  await _scenario('sidebar_toggle', () async {
    for (var i = 0; i < 8; i++) {
      (_findState((s) => s.runtimeType.toString() == '_MainContentSplitState')
              as dynamic)
          .toggleSidebar();
      await _wait(450);
    }
  });

  final editor = _editor();
  _setText(editor, heavySql);
  await _wait(300);
  await _scenario('run_heavy_query', () async {
    SqlEditorCommandBridge.instance.invokeExecute();
    await _waitFor(() => _find((e) => e.widget is VirtualResultGrid) != null,
        'result grid', onTimeout: () {
      final texts = <String>[];
      void v(Element e) {
        if (e.widget is Text) {
          final d = (e.widget as Text).data;
          if (d != null && d.length < 120) texts.add(d);
        }
        e.visitChildren(v);
      }
      WidgetsBinding.instance.rootElement!.visitChildren(v);
      final eds = <String>[];
      void ve(Element e) {
        if (e is StatefulElement && e.state is EditableTextState) {
          final st = e.state as EditableTextState;
          eds.add('${st.widget.controller.runtimeType}:${st.textEditingValue.text.length}:ro=${st.widget.readOnly}');
        }
        e.visitChildren(ve);
      }
      WidgetsBinding.instance.rootElement!.visitChildren(ve);
      stdout.writeln('BENCH debug editors: $eds');
      stdout.writeln('BENCH debug alltexts: ${texts.where((t) => t.length > 12).take(40).toList()}');
      stdout.writeln('BENCH debug texts: ${texts.where((t) => t.contains('row') || t.contains('rror') || t.contains('Run') || t.contains('ompleted')).take(12).toList()} editorLen=${editor.textEditingValue.text.length} canExec=${SqlEditorCommandBridge.instance.canExecute}');
    });
    await _wait(1500);
  });

  await _scenario('scroll_v', () => _scrollGrid(Axis.vertical, 24, 3000));
  await _scenario('scroll_h', () => _scrollGrid(Axis.horizontal, 18, 3000));
  await _scenario('hover_grid', _hoverGrid);

  await _scenario('typing', () async {
    final end = DateTime.now().add(const Duration(seconds: 3));
    var i = 0;
    while (DateTime.now().isBefore(end)) {
      final ch = 'select_x '[i++ % 9];
      _setText(editor, editor.textEditingValue.text + ch);
      await _wait(33); // ~30 chars/s, a fast typist
    }
  });

  // ---- connections tree with a large schema (#723)
  // The chevron (AnimatedRotation) in the Big Schema tile expands it.
  Element? tile;
  _byText('Big Schema (1500 tables)').visitAncestorElements((a) {
    if (a.widget.runtimeType.toString() == '_SqliteConnectionTile') {
      tile = a;
      return false;
    }
    return true;
  });
  Element? chevron;
  void findChevron(Element e) {
    if (chevron != null) return;
    if (e.widget is AnimatedRotation) {
      chevron = e;
      return;
    }
    e.visitChildren(findChevron);
  }
  tile!.visitChildren(findChevron);
  await _tap(chevron!);
  await _waitFor(() => _findText('Tables (1500)') != null, 'Tables group');
  await _wait(800);
  await _scenario('tree_expand_1500', () async {
    await _tap(_byText('Tables (1500)'));
    await _wait(1200);
  });
  await _scenario('tree_scroll', () => _scrollLoop(
        () => _find((e) => e.widget is ConnectionsPanel)!,
        Axis.vertical,
        30,
        3000,
        minExtent: 1000,
      ));
  await _scenario('tree_collapse_1500', () async {
    await _tap(_byText('Tables (1500)'));
    await _wait(1200);
  });

  await _scenario('new_tab_and_switch', () async {
    SqlEditorCommandBridge.instance.invokeNew();
    await _wait(500);
    for (var i = 0; i < 6; i++) {
      SqlEditorCommandBridge.instance.invokeNextTab();
      await _wait(400);
    }
  });
}

/// Live scroll position with extent under [root] along [axis], or null.
ScrollPosition? _scrollPosition(Element root, Axis axis, {double minExtent = 0}) {
  ScrollPosition? pos;
  void visit(Element e) {
    if (pos != null) return;
    if (e.widget is Scrollable && (e.widget as Scrollable).axis == axis) {
      final st = (e as StatefulElement).state as ScrollableState;
      if (st.mounted && st.position.maxScrollExtent > minExtent) {
        pos = st.position;
        return;
      }
    }
    e.visitChildren(visit);
  }

  root.visitChildren(visit);
  return pos;
}

/// Scrolls back and forth by [step] px per frame for [ms], re-finding the
/// scrollable if the widget rebuilt it.
Future<void> _scrollLoop(
  Element Function() root,
  Axis axis,
  double step,
  int ms, {
  double minExtent = 0,
}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  var dir = 1.0;
  ScrollPosition? p;
  while (DateTime.now().isBefore(end)) {
    await SchedulerBinding.instance.endOfFrame;
    p ??= _scrollPosition(root(), axis, minExtent: minExtent);
    if (p == null) {
      stdout.writeln('BENCH skip: no $axis scrollable');
      return;
    }
    var next = p.pixels + dir * step;
    if (next > p.maxScrollExtent || next < 0) {
      dir = -dir;
      next = p.pixels + dir * step;
    }
    try {
      p.jumpTo(next.clamp(0.0, p.maxScrollExtent));
    } catch (_) {
      p = null; // the scrollable was replaced; find it again next frame
    }
  }
}

Future<void> _scrollGrid(Axis axis, double step, int ms) => _scrollLoop(
      () => _find((e) => e.widget is VirtualResultGrid)!,
      axis,
      step,
      ms,
    );

Future<void> _hoverGrid() async {
  final grid = _find((e) => e.widget is VirtualResultGrid)!;
  final box = grid.renderObject! as RenderBox;
  final origin = box.localToGlobal(Offset.zero);
  final size = box.size;
  final end = DateTime.now().add(const Duration(seconds: 3));
  var t = 0.0;
  Offset? last;
  while (DateTime.now().isBefore(end)) {
    await SchedulerBinding.instance.endOfFrame;
    t += 0.035;
    final pos = origin +
        Offset(
          size.width * (0.5 + 0.45 * math.sin(t)),
          size.height * (0.5 + 0.4 * math.sin(t * 1.7)),
        );
    GestureBinding.instance.handlePointerEvent(PointerHoverEvent(
      position: pos,
      delta: last == null ? Offset.zero : pos - last,
      kind: PointerDeviceKind.mouse,
    ));
    last = pos;
  }
}

// ---------------------------------------------------------------- measuring

Future<void> _scenario(String id, Future<void> Function() body) async {
  if (only.isNotEmpty && !only.split(',').contains(id)) {
    await body(); // still run it: later scenarios depend on its state
    return;
  }
  await _vm?.setVMTimelineFlags(
      streams.isEmpty ? const [] : streams.split(','));
  await _vm?.clearVMTimeline();
  if (profile) {
    await _vm?.clearCpuSamples(_isolateId!);
    await _vm?.getAllocationProfile(_isolateId!, reset: true);
  }
  await SchedulerBinding.instance.endOfFrame;
  _timings.clear();
  final sw = Stopwatch()..start();
  await body();
  await _wait(200);
  sw.stop();
  _report(id, sw.elapsedMilliseconds);
  if (streams.contains('Embedder')) await _reportPresents(id);
  if (profile) {
    await _reportAllocations(id);
    await _reportCpu(id);
    if (streams.isNotEmpty) await _reportTimeline(id);
  }
}

void _report(String id, int wallMs) {
  if (_timings.isEmpty) {
    stdout.writeln('BENCH $id: no frames in ${wallMs}ms (idle, nothing drawn)');
    return;
  }
  double ms(Duration d) => d.inMicroseconds / 1000.0;
  double pct(List<double> v, double p) {
    final s = [...v]..sort();
    return s[((s.length - 1) * p).round()];
  }

  final build = [for (final t in _timings) ms(t.buildDuration)];
  final raster = [for (final t in _timings) ms(t.rasterDuration)];
  final starts = [
    for (final t in _timings) t.timestampInMicroseconds(FramePhase.vsyncStart)
  ]..sort();
  final gaps = [
    for (var i = 1; i < starts.length; i++) (starts[i] - starts[i - 1]) / 1000.0
  ];
  const budget = 1000 / 120;
  int over(List<double> v) => v.where((x) => x > budget).length;
  final stutters = gaps.where((g) => g > 12.5 && g < 150).length;
  stdout.writeln(
    'BENCH ${id.padRight(20)} frames=${_timings.length.toString().padLeft(4)} '
    'build p50/p90/max=${pct(build, .5).toStringAsFixed(1)}/${pct(build, .9).toStringAsFixed(1)}/${pct(build, 1).toStringAsFixed(1)} '
    'raster p50/p90/max=${pct(raster, .5).toStringAsFixed(1)}/${pct(raster, .9).toStringAsFixed(1)}/${pct(raster, 1).toStringAsFixed(1)} '
    'over8.3 build=${over(build)} raster=${over(raster)} stutters=$stutters '
    'gap p50=${gaps.isEmpty ? 0 : pct(gaps, .5).toStringAsFixed(2)}ms',
  );
}

Future<void> _connectVm() async {
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  if (uri == null) return;
  _vm = await vms_io.vmServiceConnectUri(
    uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
  );
  _isolateId = developer.Service.getIsolateId(Isolate.current);
}

Future<void> _reportCpu(String id) async {
  final samples = await _vm!.getCpuSamples(_isolateId!, 0, 0x7fffffffffff);
  final self = <int, int>{};
  final incl = <int, int>{};
  for (final s in samples.samples ?? const <vms.CpuSample>[]) {
    final stack = s.stack ?? const <int>[];
    if (stack.isEmpty) continue;
    self.update(stack.first, (v) => v + 1, ifAbsent: () => 1);
    for (final f in stack.toSet()) {
      incl.update(f, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  final funcs = samples.functions ?? const <vms.ProfileFunction>[];
  String name(int i) {
    final f = funcs[i].function;
    if (f is vms.FuncRef) {
      final owner = f.owner;
      final o = owner is vms.ClassRef ? '${owner.name}.' : '';
      return '$o${f.name}';
    }
    return '${funcs[i].function}';
  }

  final total = math.max(1, samples.sampleCount ?? 0);
  if (callersOf.isNotEmpty) {
    final chains = <String, int>{};
    for (final s in samples.samples ?? const <vms.CpuSample>[]) {
      final stack = s.stack ?? const <int>[];
      final hit = stack.indexWhere((f) => name(f).contains(callersOf));
      if (hit < 0) continue;
      final dart = [
        for (final f in stack.skip(hit + 1))
          name(f).replaceAll('[NativeFunction name: ', 'N:').replaceAll('[Native] ', '').replaceAll(']', '')
      ].take(14).join(' < ');
      chains[dart] = (chains[dart] ?? 0) + 1;
    }
    final e = chains.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final x in e.take(12)) {
      stdout.writeln('CALLERS $id ${(100 * x.value / total).toStringAsFixed(1)}%  ${x.key}');
    }
  }
  for (final (title, m) in [('self', self), ('incl', incl)]) {
    final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final x in e.take(title == 'self' ? 20 : 40)) {
      stdout.writeln('CPU $id $title '
          '${(100 * x.value / total).toStringAsFixed(1).padLeft(5)}%  ${name(x.key)}');
    }
  }
}

Future<void> _reportTimeline(String id) async {
  final tl = await _vm!.getVMTimeline();
  final names = <int, String>{};
  final open = <int, List<(String, int)>>{};
  final total = <String, double>{};
  final count = <String, int>{};
  final events = [
    for (final e in tl.traceEvents ?? const <vms.TimelineEvent>[]) e.json!
  ];
  for (final e in events) {
    if (e['ph'] == 'M' && e['name'] == 'thread_name') {
      names[e['tid'] as int] =
          '${(e['args'] as Map)['name']}'.replaceAll(RegExp(r' \(\d+\)'), '');
    }
  }
  void add(int tid, String n, int us) {
    final k = '${names[tid] ?? tid} :: $n';
    total[k] = (total[k] ?? 0) + us / 1000.0;
    count[k] = (count[k] ?? 0) + 1;
  }

  for (final e in events) {
    final tid = e['tid'] as int? ?? 0;
    final n = '${e['name']}';
    switch (e['ph']) {
      case 'X':
        add(tid, n, (e['dur'] as num? ?? 0).toInt());
      case 'B':
        (open[tid] ??= []).add((n, (e['ts'] as num).toInt()));
      case 'E':
        final st = open[tid];
        if (st != null && st.isNotEmpty) {
          final (on, ts) = st.removeLast();
          add(tid, on, (e['ts'] as num).toInt() - ts);
        }
    }
  }
  final sorted = total.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final x in sorted.take(30)) {
    stdout.writeln('TL $id ${x.value.toStringAsFixed(1).padLeft(8)} ms '
        'n=${count[x.key]} ${x.key}');
  }
}

// ---------------------------------------------------------------- tree utils

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

Future<void> _waitFor(bool Function() cond, String what,
    {void Function()? onTimeout}) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      onTimeout?.call();
      throw StateError('timeout waiting for $what');
    }
    await _wait(50);
  }
}

Element? _find(bool Function(Element) test) {
  Element? found;
  void visit(Element e) {
    if (found != null) return;
    if (test(e)) {
      found = e;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement!.visitChildren(visit);
  return found;
}

State? _findState(bool Function(State) test) {
  final e = _find((e) => e is StatefulElement && test(e.state));
  return (e as StatefulElement?)?.state;
}

Element? _findText(String text) => _find((e) =>
    (e.widget is Text && (e.widget as Text).data == text) ||
    (e.widget is RichText && (e.widget as RichText).text.toPlainText() == text));

Element _byText(String text) {
  final e = _findText(text);
  if (e == null) throw StateError('no text "$text"');
  return e;
}

Future<void> _seedBigSchema(String dir) async {
  final path = '$dir/big_schema.sqlite';
  final db = await databaseFactoryFfi.openDatabase(path);
  final batch = db.batch();
  for (var i = 0; i < 1500; i++) {
    batch.execute('CREATE TABLE t_${i.toString().padLeft(4, '0')}_orders (id INTEGER PRIMARY KEY, v TEXT)');
  }
  await batch.commit(noResult: true);
  await db.close();
  await LocalDb.instance.addConnection(ConnectionRow(
    type: 'sqlite',
    name: 'Big Schema (1500 tables)',
    host: path,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  ));
}

Element _byKey(String key) {
  final e = _find((e) => e.widget.key == Key(key));
  if (e == null) throw StateError('no widget with key $key');
  return e;
}

Future<void> _tap(Element e) async {
  final box = e.renderObject! as RenderBox;
  final pos = box.localToGlobal(box.size.center(Offset.zero));
  final b = GestureBinding.instance;
  b.handlePointerEvent(PointerDownEvent(position: pos, pointer: 42));
  b.handlePointerEvent(PointerUpEvent(position: pos, pointer: 42));
  await _wait(400);
}

/// The SQL editor: the EditableText driven by the syntax-highlight controller.
EditableTextState _editor() {
  EditableTextState? found;
  void visit(Element e) {
    if (found != null) return;
    if (e is StatefulElement && e.state is EditableTextState) {
      final s = e.state as EditableTextState;
      if (s.widget.controller.runtimeType.toString() ==
          'QueryaHighlightController') {
        found = s;
        return;
      }
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement!.visitChildren(visit);
  return found!;
}

void _setText(EditableTextState s, String text) {
  s.widget.controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

/// Presented frames from the engine timeline: one `GPURasterizer::Draw` per
/// frame on the raster thread. Works whether or not FrameTiming is reported.
Future<void> _reportPresents(String id) async {
  final tl = await _vm!.getVMTimeline();
  final starts = <int>[];
  final durs = <double>[];
  final uiFrames = <double>[];
  final open = <int, List<(String, int)>>{};
  for (final t in tl.traceEvents ?? const <vms.TimelineEvent>[]) {
    final e = t.json!;
    final n = '${e['name']}';
    final tid = e['tid'] as int? ?? 0;
    if (e['ph'] == 'B') {
      (open[tid] ??= []).add((n, (e['ts'] as num).toInt()));
    } else if (e['ph'] == 'E') {
      final st = open[tid];
      if (st == null || st.isEmpty) continue;
      final (on, ts) = st.removeLast();
      final dur = ((e['ts'] as num).toInt() - ts) / 1000.0;
      if (on == 'GPURasterizer::Draw') {
        starts.add(ts);
        durs.add(dur);
      } else if (on == 'Animator::BeginFrame' || on == 'Frame') {
        uiFrames.add(dur);
      }
    }
  }
  if (starts.length < 2) {
    stdout.writeln('PRESENT $id: ${starts.length} draws');
    return;
  }
  starts.sort();
  double pct(List<double> v, double p) {
    final s = [...v]..sort();
    return s[((s.length - 1) * p).round()];
  }
  final gaps = [
    for (var i = 1; i < starts.length; i++) (starts[i] - starts[i - 1]) / 1000.0
  ].where((g) => g < 150).toList();
  if (gaps.isEmpty) {
    stdout.writeln('PRESENT $id: ${starts.length} isolated draws');
    return;
  }
  final active = gaps.fold<double>(0, (a, b) => a + b) / 1000.0;
  stdout.writeln('PRESENT ${id.padRight(20)} draws=${starts.length} '
      'fps(active)=${active > 0 ? (gaps.length / active).toStringAsFixed(0) : '-'} '
      'gap p50/p90/p99=${pct(gaps, .5).toStringAsFixed(2)}/${pct(gaps, .9).toStringAsFixed(2)}/${pct(gaps, .99).toStringAsFixed(2)} '
      '>12.5ms=${gaps.where((g) => g > 12.5).length} '
      'raster p50/p99=${pct(durs, .5).toStringAsFixed(2)}/${pct(durs, .99).toStringAsFixed(2)}');
}

/// Bytes allocated per class during the scenario (drives GC pauses).
Future<void> _reportAllocations(String id) async {
  final prof = await _vm!.getAllocationProfile(_isolateId!);
  final rows = <(String, int, int)>[];
  for (final m in prof.members ?? const <vms.ClassHeapStats>[]) {
    final bytes = m.accumulatedSize ?? 0;
    if (bytes <= 0) continue;
    rows.add(('${m.classRef?.name}', bytes, m.instancesAccumulated ?? 0));
  }
  rows.sort((a, b) => b.$2.compareTo(a.$2));
  final total = rows.fold<int>(0, (a, r) => a + r.$2);
  stdout.writeln('ALLOC $id total=${(total / 1048576).toStringAsFixed(1)} MB');
  for (final r in rows.take(25)) {
    stdout.writeln('ALLOC $id ${(r.$2 / 1048576).toStringAsFixed(2).padLeft(8)} MB '
        '${r.$3.toString().padLeft(9)} x ${r.$1}');
  }
}

class _MemorySecrets implements SecretsStorageBackend {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
