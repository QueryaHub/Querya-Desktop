import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/actions/querya_command_host.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/features/command_palette/command_match_highlight.dart';
import 'package:querya_desktop/features/command_palette/list_reveal.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Threshold where filter runs on a worker isolate (hundreds of tables).
const kQuickSwitcherIsolateThreshold = 250;

/// Opens the Quick Switcher (`Ctrl/Cmd+K`). Motion Off snaps via [showAppDialog].
Future<void> showQuickSwitcher(
  BuildContext hostContext, {
  String initialQuery = '',
  List<QueryaSchemaObject>? seed,
  Future<List<QueryaSchemaObject>> Function()? load,
}) {
  return showAppDialog<void>(
    context: hostContext,
    builder: (dialogContext) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(dialogContext),
      child: QuickSwitcherDialog(
        hostContext: hostContext,
        initialQuery: initialQuery,
        seed: seed,
        load: load,
      ),
    ),
  );
}

class QuickSwitcherDialog extends StatefulWidget {
  const QuickSwitcherDialog({
    super.key,
    required this.hostContext,
    this.initialQuery = '',
    this.seed,
    this.load,
  });

  final BuildContext hostContext;
  final String initialQuery;
  final List<QueryaSchemaObject>? seed;
  final Future<List<QueryaSchemaObject>> Function()? load;

  @override
  State<QuickSwitcherDialog> createState() => _QuickSwitcherDialogState();
}

class _QuickSwitcherDialogState extends State<QuickSwitcherDialog> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  final _scroll = material.ScrollController();
  var _selected = 0;

  /// Set by keyboard navigation: the list moves under a still pointer, and the
  /// hover that causes must not take the selection back. Cleared as soon as
  /// the mouse really moves.
  var _ignoreHover = false;

  static const _itemExtent = 40.0;
  static const _listPadding = EdgeInsets.fromLTRB(8, 4, 8, 8);
  var _loading = false;
  String? _error;
  List<QueryaSchemaObject> _all = const [];
  List<QueryaSchemaObject> _hits = const [];
  var _filterSeq = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _controller.addListener(_onQueryChanged);
    final seed = widget.seed;
    if (seed != null) {
      _all = seed;
      _hits = filterSchemaObjects(seed, widget.initialQuery);
    } else {
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _scroll.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final objects = await (widget.load?.call() ??
          Future<List<QueryaSchemaObject>>.value(const []));
      if (!mounted) return;
      setState(() {
        _all = objects;
        _loading = false;
        _error = null;
      });
      await _applyFilter(_controller.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _onQueryChanged() {
    setState(() => _selected = 0);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _applyFilter(_controller.text);
  }

  Future<void> _applyFilter(String query) async {
    final seq = ++_filterSeq;
    final source = _all;
    final List<QueryaSchemaObject> next;
    if (source.length >= kQuickSwitcherIsolateThreshold) {
      next = await compute(_filterSchemaObjectsIsolate, (source, query));
    } else {
      next = filterSchemaObjects(source, query);
    }
    if (!mounted || seq != _filterSeq) return;
    setState(() => _hits = next);
  }

  void _open(QueryaSchemaObject object) {
    Navigator.of(context).pop();
    final target =
        widget.hostContext.mounted ? widget.hostContext : context;
    QueryaCommandHost.maybeOf(target)?.onOpenSchemaObject?.call(object);
  }

  void _move(int delta) {
    if (_hits.isEmpty) return;
    setState(() {
      _selected = (_selected + delta) % _hits.length;
      if (_selected < 0) _selected += _hits.length;
      _ignoreHover = true;
    });
    material.WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  /// Scrolls the list so the selected row is visible (#1369).
  void _reveal() {
    if (!mounted || !_scroll.hasClients || _hits.isEmpty) return;
    final index = _selected.clamp(0, _hits.length - 1);
    final position = _scroll.position;
    final target = revealOffsetForItem(
      index: index,
      itemExtent: _itemExtent,
      offset: position.pixels,
      viewportExtent: position.viewportDimension,
      leadingPadding: _listPadding.top,
      trailingPadding: _listPadding.bottom,
    );
    if (target == null) return;
    _scroll.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hits = _hits;
    final selectedIndex =
        hits.isEmpty ? 0 : _selected.clamp(0, hits.length - 1);

    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: 520,
        minWidth: 360,
        maxHeight: 420,
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
          const SingleActivator(LogicalKeyboardKey.enter): () {
            if (hits.isNotEmpty) _open(hits[selectedIndex]);
          },
        },
        child: SizedBox(
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  placeholder: const Text('Go to table, view, collection…'),
                  onSubmitted: (_) {
                    if (hits.isNotEmpty) _open(hits[selectedIndex]);
                  },
                ),
              ),
              const Divider(),
              Expanded(child: _body(theme.colorScheme, hits, selectedIndex)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    ColorScheme colors,
    List<QueryaSchemaObject> hits,
    int selectedIndex,
  ) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Loading objects…'),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!),
        ),
      );
    }
    if (hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _all.isEmpty
                ? 'No objects in the active connection'
                : 'No matching objects',
          ),
        ),
      );
    }
    return material.Listener(
      onPointerHover: (_) => _ignoreHover = false,
      child: ListView.builder(
      controller: _scroll,
      padding: _listPadding,
      itemCount: hits.length,
      itemExtent: _itemExtent,
      itemBuilder: (context, index) {
        final object = hits[index];
        final active = index == selectedIndex;
        return material.Semantics(
          button: true,
          selected: active,
          child: material.InkWell(
          key: ValueKey(object.id),
          onTap: () => _open(object),
          onHover: (_) {
            if (_ignoreHover) return;
            setState(() => _selected = index);
          },
          borderRadius: BorderRadius.circular(6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: active
                  ? colors.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(object.icon, size: 16),
                  const Gap(8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CommandMatchHighlight(
                          text: object.qualifiedName,
                          query: _controller.text,
                        ),
                        Text(object.kindLabel).xSmall().muted(),
                      ],
                    ),
                  ),
                  if (object.rowCount != null)
                    Text('${object.rowCount}').xSmall().muted(),
                ],
              ),
            ),
          ),
          ),
        );
      },
      ),
    );
  }
}

List<QueryaSchemaObject> _filterSchemaObjectsIsolate(
  (List<QueryaSchemaObject>, String) args,
) {
  return filterSchemaObjects(args.$1, args.$2);
}
