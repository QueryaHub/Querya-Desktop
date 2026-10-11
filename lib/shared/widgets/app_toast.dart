import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/shared/widgets/querya_icon_button.dart';

enum AppToastVariant {
  info,
  success,
  error,
}

/// Shows non-blocking app feedback in the bottom-right corner of the window.
///
/// Toasts share one entry in the root overlay and stack upwards. Each one
/// fades and slides in over [QueryaMotion.standard] (instantly under reduced
/// motion), stays for [showDuration] and closes itself, or earlier through its
/// close button.
void showAppToast({
  required material.BuildContext context,
  required String message,
  AppToastVariant variant = AppToastVariant.info,
  Duration showDuration = const Duration(seconds: 5),
}) {
  _ToastHost.show(
    material.Overlay.of(context, rootOverlay: true),
    _ToastData(
      message: message,
      variant: variant,
      enter: context.motionDuration(QueryaMotion.standard),
      curve: context.motionCurve(QueryaMotion.enter),
      show: showDuration,
    ),
  );
}

class _ToastData {
  _ToastData({
    required this.message,
    required this.variant,
    required this.enter,
    required this.curve,
    required this.show,
  });

  final String message;
  final AppToastVariant variant;
  final Duration enter;
  final material.Curve curve;
  final Duration show;
}

/// The single overlay entry that lays the live toasts out.
abstract final class _ToastHost {
  static final material.ValueNotifier<List<_ToastData>> _items =
      material.ValueNotifier(const []);
  static material.OverlayEntry? _entry;

  static void show(material.OverlayState overlay, _ToastData toast) {
    // A previous overlay that is gone (window rebuilt, tests) leaves its entry
    // behind: start over instead of adding to a dead one.
    if (_entry != null && !_entry!.mounted) {
      _entry = null;
      _items.value = const [];
    }
    _items.value = [..._items.value, toast];
    if (_entry != null) return;
    _entry = material.OverlayEntry(
      builder: (context) => material.ValueListenableBuilder<List<_ToastData>>(
        valueListenable: _items,
        builder: (context, items, _) => material.Positioned(
          right: 16,
          bottom: 16,
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            crossAxisAlignment: material.CrossAxisAlignment.end,
            children: [
              for (final item in items)
                _ToastView(
                  key: material.ObjectKey(item),
                  data: item,
                  onClosed: () => _remove(item),
                ),
            ],
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  static void _remove(_ToastData toast) {
    final next = _items.value.where((t) => !identical(t, toast)).toList();
    _items.value = next;
    if (next.isEmpty) {
      _entry?.remove();
      _entry = null;
    }
  }
}

class _ToastView extends material.StatefulWidget {
  const _ToastView({super.key, required this.data, required this.onClosed});

  final _ToastData data;
  final material.VoidCallback onClosed;

  @override
  material.State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends material.State<_ToastView>
    with material.SingleTickerProviderStateMixin {
  late final material.AnimationController _controller;
  late final material.Animation<double> _in;
  var _closed = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    // One controller drives the whole life: enter, stay, then done.
    _controller = material.AnimationController(
      vsync: this,
      duration: d.enter + d.show,
    );
    if (d.enter == Duration.zero) {
      _in = const material.AlwaysStoppedAnimation(1);
    } else {
      final total = (d.enter + d.show).inMicroseconds;
      _in = material.CurvedAnimation(
        parent: _controller,
        curve: material.Interval(
          0,
          (d.enter.inMicroseconds / total).clamp(0.0, 1.0).toDouble(),
          curve: d.curve,
        ),
      );
    }
    _controller
      ..addStatusListener((status) {
        if (status == material.AnimationStatus.completed) _close();
      })
      ..forward();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    widget.onClosed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = context.colors;
    final wb = context.workbenchOrDefault;
    final variant = widget.data.variant;
    final isError = variant == AppToastVariant.error;
    final icon = switch (variant) {
      AppToastVariant.info => material.Icons.info_outline_rounded,
      AppToastVariant.success => material.Icons.check_circle_outline_rounded,
      AppToastVariant.error => material.Icons.error_outline_rounded,
    };
    final accent = isError ? cs.destructive : cs.foreground;

    return material.AnimatedBuilder(
      animation: _in,
      builder: (context, child) => material.Opacity(
        opacity: _in.value,
        child: material.Transform.translate(
          offset: material.Offset(0, (1 - _in.value) * 12),
          child: child,
        ),
      ),
      child: material.Padding(
        padding: const material.EdgeInsets.only(top: 8),
        child: material.Semantics(
          liveRegion: true,
          container: true,
          child: material.Material(
            color: material.Colors.transparent,
            child: material.Container(
              constraints: const material.BoxConstraints(
                minWidth: 280,
                maxWidth: 420,
              ),
              padding: const material.EdgeInsets.fromLTRB(14, 8, 6, 8),
              decoration: material.BoxDecoration(
                color: cs.popover,
                borderRadius: material.BorderRadius.circular(
                  QueryaControlSize.md.scaledRadius(context),
                ),
                border: material.Border.all(
                  color: isError
                      ? cs.destructive.withValues(alpha: 0.6)
                      : wb.borderSubtle,
                ),
                boxShadow: const [
                  material.BoxShadow(
                    color: material.Color(0x33000000),
                    blurRadius: 12,
                    offset: material.Offset(0, 4),
                  ),
                ],
              ),
              child: material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  material.Icon(icon, size: 18, color: accent),
                  const material.SizedBox(width: 10),
                  material.Flexible(
                    child: material.Text(
                      widget.data.message,
                      style: material.TextStyle(
                        fontSize: 13,
                        color: cs.foreground,
                      ),
                    ),
                  ),
                  const material.SizedBox(width: 8),
                  QueryaIconButton(
                    icon: const material.Icon(material.Icons.close_rounded),
                    tooltip: 'Dismiss',
                    size: QueryaControlSize.sm,
                    onPressed: _close,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
