// ignore_for_file: depend_on_referenced_packages, use_build_context_synchronously

// Frame-timing benchmark for VirtualResultGrid. Run in profile mode:
//   flutter run --profile -d linux -t benchmark/grid_perf_bench.dart --dart-define=MODE=scroll
// MODE: scroll (horizontal pan) | edit (staged cell edits on a sorted grid)
//       | select (mouse-drag selection through ResultsTab, incl. stats)
//       | dialog (open / close showAppDialog repeatedly over a busy grid)
//       | rerun (a new result set every 400 ms, like re-running a query)
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';
import 'package:querya_desktop/features/workspace/results_tab.dart';
import 'package:querya_desktop/shared/widgets/app_dialog.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vm_service/vm_service.dart' as vms;
import 'package:vm_service/vm_service_io.dart' as vms_io;

const mode = String.fromEnvironment('MODE', defaultValue: 'scroll');
const rowCount = int.fromEnvironment('ROWS', defaultValue: 5000);
const colCount = int.fromEnvironment('COLS', defaultValue: 120);
const seconds = int.fromEnvironment('SECS', defaultValue: 6);
final dialogHost = GlobalKey();
final rerunData = ValueNotifier<(List<String>, List<List<String>>)>((const [], const []));
const profile = bool.fromEnvironment('PROFILE', defaultValue: false);

vms.VmService? _vm;
String? _isolateId;

Future<void> _connectVm() async {
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  if (uri == null) return;
  final ws = uri.replace(scheme: 'ws', path: '${uri.path}ws').toString();
  _vm = await vms_io.vmServiceConnectUri(ws);
  _isolateId = developer.Service.getIsolateId(Isolate.current);
}


final timings = <FrameTiming>[];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SchedulerBinding.instance.addTimingsCallback(timings.addAll);
  final columns = [for (var c = 0; c < colCount; c++) 'col_$c'];
  final rows = [
    for (var r = 0; r < rowCount; r++)
      [for (var c = 0; c < colCount; c++) c == 0 ? '${(r * 7919) % rowCount}' : 'v${r}_$c'],
  ];
  final buffer = DataGridStagingBuffer(columns: columns, rows: rows);
  final td = QueryaTheme.darkDefault
      .toShadcnThemeData()
      .copyWith(platform: () => TargetPlatform.linux);
  runApp(ShadcnApp(
    theme: td,
    home: material.Scaffold(
      body: mode == 'rerun'
          ? ValueListenableBuilder(
              valueListenable: rerunData,
              builder: (_, d, __) => ResultsTab(columns: d.$1, rows: d.$2),
            )
          : mode == 'dialog'
          ? KeyedSubtree(
              key: dialogHost,
              child: ListenableBuilder(
                listenable: buffer,
                builder: (_, __) => VirtualResultGrid(
                  columns: columns,
                  rows: buffer.effectiveRows,
                  stagingBuffer: buffer,
                ),
              ),
            )
          : mode == 'select'
          ? ListenableBuilder(
              listenable: buffer,
              builder: (_, __) => ResultsTab(
                columns: columns,
                rows: rows,
                stagingBuffer: buffer,
              ),
            )
          : ListenableBuilder(
              listenable: buffer,
              builder: (_, __) => VirtualResultGrid(
                columns: columns,
                rows: buffer.effectiveRows,
                stagingBuffer: buffer,
              ),
            ),
    ),
  ));
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    await _run(buffer);
  });
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

Future<void> _tapText(String text) async {
  final e = _find((e) => e.widget is Text && (e.widget as Text).data == text);
  final box = e!.renderObject! as RenderBox;
  final pos = box.localToGlobal(box.size.center(Offset.zero));
  final b = GestureBinding.instance;
  b.handlePointerEvent(PointerDownEvent(position: pos, pointer: 99));
  b.handlePointerEvent(PointerUpEvent(position: pos, pointer: 99));
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

Future<void> _run(DataGridStagingBuffer buffer) async {
  if (mode == 'edit') await _tapText('col_0'); // sort ascending
  Offset? dragStart;
  if (mode == 'select') {
    final e = _find((e) => e.widget is Text && (e.widget as Text).data == 'v2_1');
    final box = e!.renderObject! as RenderBox;
    dragStart = box.localToGlobal(box.size.center(Offset.zero));
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(
      position: dragStart,
      pointer: 7,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    ));
  }
  if (profile) {
    await _connectVm();
    await _vm?.clearCpuSamples(_isolateId!);
    await _vm?.setVMTimelineFlags(['Embedder', 'Dart', 'GC']);
    await _vm?.clearVMTimeline();
  }
  timings.clear();
  final startMicros = DateTime.now().microsecondsSinceEpoch;
  final end = DateTime.now().add(const Duration(seconds: seconds));
  var i = 0;
  ScrollPosition? pos;
  if (mode == 'scroll') {
    final e = _find((e) =>
        e.widget is Scrollable && (e.widget as Scrollable).axis == Axis.horizontal);
    pos = (e as StatefulElement).state is ScrollableState
        ? ((e.state) as ScrollableState).position
        : null;
  }
  var dir = 1.0;
  if (mode == 'dialog') {
    final ctx = dialogHost.currentContext!;
    while (DateTime.now().isBefore(end)) {
      unawaited(showAppDialog<void>(
        context: ctx,
        builder: (_) => const Center(
          child: SizedBox(
            width: 420,
            height: 260,
            child: Card(child: Center(child: Text('bench dialog'))),
          ),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      Navigator.of(ctx).pop();
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }
  if (mode == 'rerun') {
    var n = 0;
    while (DateTime.now().isBefore(end)) {
      n++;
      final cols = [for (var c = 0; c < 20; c++) 'column_${c}_$n'];
      rerunData.value = (
        cols,
        [
          for (var r = 0; r < 5000; r++)
            [for (var c = 0; c < 20; c++) c % 4 == 0 ? '${r * c + n}' : 'value $r/$c run $n'],
        ],
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }
  while (mode != 'dialog' && mode != 'rerun' && DateTime.now().isBefore(end)) {
    await SchedulerBinding.instance.endOfFrame;
    if (mode == 'scroll') {
      final p = pos!;
      final next = p.pixels + dir * 14;
      if (next > p.maxScrollExtent || next < 0) dir = -dir;
      p.jumpTo((p.pixels + dir * 14).clamp(0.0, p.maxScrollExtent));
    } else if (mode == 'select') {
      _dragStep(dragStart!, i++);
    } else {
      buffer.setCell((i * 37) % rowCount, 1 + i % 5, 'edit$i');
      i++;
    }
  }
  if (mode == 'select') {
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(
      position: dragStart!,
      pointer: 7,
      kind: PointerDeviceKind.mouse,
    ));
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  _report();
  if (profile) {
    await _reportCpu(startMicros);
    await _reportTimeline();
  }
  exit(0);
}

void _report() {
  double ms(Duration d) => d.inMicroseconds / 1000.0;
  double pct(List<double> v, double p) {
    final s = [...v]..sort();
    return s[((s.length - 1) * p).round()];
  }
  final build = [for (final t in timings) ms(t.buildDuration)];
  final raster = [for (final t in timings) ms(t.rasterDuration)];
  final total = [for (final t in timings) ms(t.totalSpan)];
  const budget = 1000 / 120;
  int over(List<double> v) => v.where((x) => x > budget).length;
  String row(String n, List<double> v) =>
      '$n  p50=${pct(v, .5).toStringAsFixed(2)}  p90=${pct(v, .9).toStringAsFixed(2)}  '
      'p99=${pct(v, .99).toStringAsFixed(2)}  max=${pct(v, 1).toStringAsFixed(2)}  '
      'over8.33ms=${over(v)}/${v.length}';
  final view = PlatformDispatcher.instance.views.first;
  stdout.writeln('BENCH window=${view.physicalSize.width.toInt()}x${view.physicalSize.height.toInt()} dpr=${view.devicePixelRatio}');
  stdout.writeln('BENCH semantics=${SemanticsBinding.instance.semanticsEnabled}');
  stdout.writeln('BENCH mode=$mode rows=$rowCount cols=$colCount frames=${timings.length}');
  stdout.writeln('BENCH ${row('build ', build)}');
  stdout.writeln('BENCH ${row('raster', raster)}');
  stdout.writeln('BENCH ${row('total ', total)}');
  // Real smoothness: gap between consecutive presented frames. At 120 Hz a gap
  // above ~12.5 ms means at least one vsync was missed (a visible stutter).
  final starts = [for (final t in timings) t.timestampInMicroseconds(FramePhase.vsyncStart)]..sort();
  final gaps = [for (var i = 1; i < starts.length; i++) (starts[i] - starts[i - 1]) / 1000.0];
  if (gaps.isNotEmpty) {
    final missed = gaps.where((g) => g > 12.5).length;
    final secs = (starts.last - starts.first) / 1e6;
    stdout.writeln('BENCH frames: ${timings.length} in ${secs.toStringAsFixed(1)} s = ${(timings.length / secs).toStringAsFixed(0)} fps, '
        'gap p50=${pct(gaps, .5).toStringAsFixed(2)} p99=${pct(gaps, .99).toStringAsFixed(2)} max=${pct(gaps, 1).toStringAsFixed(1)} ms, '
        'stutters(>12.5ms)=$missed');
  }
}

Future<void> _reportCpu(int startMicros) async {
  final vm = _vm;
  if (vm == null) {
    stdout.writeln('PROFILE no VM service');
    return;
  }
  final samples = await vm.getCpuSamples(_isolateId!, 0, 0x7fffffffffff);
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
      final o = owner is vms.ClassRef
          ? '${owner.name}.'
          : owner is vms.LibraryRef
              ? '${owner.name?.split('.').last}::'
              : '';
      return '$o${f.name}';
    }
    return '${funcs[i].function}';
  }
  final total = samples.sampleCount ?? 0;
  void top(String title, Map<int, int> m) {
    final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    stdout.writeln('PROFILE == $title (samples=$total) ==');
    for (final x in e.take(30)) {
      stdout.writeln(
          'PROFILE ${(100 * x.value / total).toStringAsFixed(1).padLeft(5)}%  ${name(x.key)}');
    }
  }
  top('self time', self);
  top('inclusive time', incl);
}

/// Moves the held mouse pointer to a new cell each frame, zig-zagging down and
/// across, so the drag selection (and its statistics) changes on every frame.
Offset? _lastDrag;

void _dragStep(Offset start, int i) {
  final rowsDown = 1 + (i % 40); // sweep 1..40 rows
  final colsAcross = 1 + ((i ~/ 40) % 6);
  final pos = start + Offset(colsAcross * 110.0, rowsDown * 28.0);
  GestureBinding.instance.handlePointerEvent(PointerMoveEvent(
    position: pos,
    delta: pos - (_lastDrag ?? start),
    pointer: 7,
    kind: PointerDeviceKind.mouse,
    buttons: kPrimaryButton,
  ));
  _lastDrag = pos;
}

/// Sums engine / framework timeline slices per thread, so raster-thread cost
/// can be broken down (the Dart CPU profile only sees the UI isolate).
Future<void> _reportTimeline() async {
  final vm = _vm;
  if (vm == null) return;
  final tl = await vm.getVMTimeline();
  final threadNames = <int, String>{};
  final open = <int, List<(String, int)>>{};
  final total = <String, double>{};
  final count = <String, int>{};
  void add(int tid, String name, int durUs) {
    final key = '${threadNames[tid] ?? tid} :: $name';
    total[key] = (total[key] ?? 0) + durUs / 1000.0;
    count[key] = (count[key] ?? 0) + 1;
  }
  final events = [for (final e in tl.traceEvents ?? const <vms.TimelineEvent>[]) e.json!];
  for (final e in events) {
    if (e['ph'] == 'M' && e['name'] == 'thread_name') {
      threadNames[e['tid'] as int] = '${(e['args'] as Map)['name']}';
    }
  }
  for (final e in events) {
    final tid = e['tid'] as int? ?? 0;
    final name = '${e['name']}';
    switch (e['ph']) {
      case 'X':
        add(tid, name, (e['dur'] as num? ?? 0).toInt());
      case 'B':
        (open[tid] ??= []).add((name, (e['ts'] as num).toInt()));
      case 'E':
        final stack = open[tid];
        if (stack != null && stack.isNotEmpty) {
          final (n, ts) = stack.removeLast();
          add(tid, n, (e['ts'] as num).toInt() - ts);
        }
    }
  }
  final sorted = total.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  stdout.writeln('TIMELINE == top slices by total ms (thread :: name, count) ==');
  for (final x in sorted.take(45)) {
    stdout.writeln('TIMELINE ${x.value.toStringAsFixed(1).padLeft(9)} ms  n=${count[x.key]}  ${x.key}');
  }
}
