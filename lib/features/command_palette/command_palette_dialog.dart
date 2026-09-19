import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/actions/querya_command.dart';
import 'package:querya_desktop/core/actions/querya_command_registry.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Opens the Command Palette (`Ctrl/Cmd+P`). Motion Off snaps via [showAppDialog].
Future<void> showCommandPalette(BuildContext hostContext) {
  QueryaCommandRegistry.instance.ensureCoreDefaults();
  return showAppDialog<void>(
    context: hostContext,
    builder: (dialogContext) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(dialogContext),
      child: CommandPaletteDialog(hostContext: hostContext),
    ),
  );
}

class CommandPaletteDialog extends StatefulWidget {
  const CommandPaletteDialog({
    super.key,
    required this.hostContext,
  });

  /// Context that owns [QueryaCommandHost] / workspace (not the overlay).
  final BuildContext hostContext;

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  var _selected = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _selected = 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<QueryaCommand> get _hits {
    final ctx = widget.hostContext.mounted ? widget.hostContext : context;
    return QueryaCommandRegistry.instance.search(_controller.text, context: ctx);
  }

  void _run(QueryaCommand command) {
    Navigator.of(context).pop();
    final target =
        widget.hostContext.mounted ? widget.hostContext : context;
    command.execute(target);
  }

  void _move(int delta) {
    final hits = _hits;
    if (hits.isEmpty) return;
    setState(() {
      _selected = (_selected + delta) % hits.length;
      if (_selected < 0) _selected += hits.length;
    });
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
            if (hits.isNotEmpty) _run(hits[selectedIndex]);
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
                  placeholder: const Text('Type a command…'),
                  onSubmitted: (_) {
                    if (hits.isNotEmpty) _run(hits[selectedIndex]);
                  },
                ),
              ),
              const Divider(),
              Expanded(
                child: hits.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No matching commands'),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        itemCount: hits.length,
                        itemExtent: 36,
                        itemBuilder: (context, index) {
                          final command = hits[index];
                          final active = index == selectedIndex;
                          return material.InkWell(
                            key: ValueKey(command.id),
                            onTap: () => _run(command),
                            onHover: (_) => setState(() => _selected = index),
                            borderRadius: BorderRadius.circular(6),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: active
                                    ? theme.colorScheme.primary
                                        .withValues(alpha: 0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  children: [
                                    if (command.icon != null) ...[
                                      Icon(command.icon, size: 16),
                                      const Gap(8),
                                    ],
                                    Expanded(
                                      child: _HighlightedLabel(
                                        text: command.title,
                                        query: _controller.text,
                                      ),
                                    ),
                                    if (command.shortcutLabel != null)
                                      Text(command.shortcutLabel!)
                                          .xSmall()
                                          .muted(),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedLabel extends StatelessWidget {
  const _HighlightedLabel({
    required this.text,
    required this.query,
  });

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) return Text(text);
    final lower = text.toLowerCase();
    final needle = q.toLowerCase();
    final index = lower.indexOf(needle);
    if (index < 0) return Text(text);
    final theme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, index)),
          TextSpan(
            text: text.substring(index, index + needle.length),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: theme.primary,
            ),
          ),
          TextSpan(text: text.substring(index + needle.length)),
        ],
      ),
    );
  }
}
