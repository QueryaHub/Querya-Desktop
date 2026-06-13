import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/layout/ui_scale_controller.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/shared/widgets/querya_dropdown.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Helper / hint copy in Preferences — readable on imported themes.
class PreferencesHint extends StatelessWidget {
  const PreferencesHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.35,
        color: cs.popoverForeground.withValues(alpha: 0.72),
      ),
    );
  }
}

/// Label + full-width control row for Preferences (uniform dropdown width).
class PreferencesFieldRow extends StatelessWidget {
  const PreferencesFieldRow({
    super.key,
    required this.label,
    required this.control,
    this.hint,
    this.labelWidth = kPreferencesLabelWidth,
  });

  final String label;
  final material.Widget control;
  final String? hint;
  final double labelWidth;

  @override
  material.Widget build(material.BuildContext context) {
    final triggerHeight = QueryaDropdownTokens.scaledTriggerHeight(context);

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Row(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            material.SizedBox(
              width: labelWidth,
              height: triggerHeight,
              child: material.Align(
                alignment: material.Alignment.centerLeft,
                child: Text(label).small().foreground(),
              ),
            ),
            const material.SizedBox(width: 12),
            material.Expanded(child: control),
          ],
        ),
        if (hint != null) ...[
          const material.SizedBox(height: 4),
          material.Padding(
            padding: material.EdgeInsets.only(left: labelWidth + 12),
            child: PreferencesHint(hint!),
          ),
        ],
      ],
    );
  }
}

/// Interface scale slider: fixed presets by default; hold Shift for 1% fine steps.
class InterfaceScaleSlider extends material.StatefulWidget {
  const InterfaceScaleSlider({super.key, required this.scale});

  final double scale;

  @override
  material.State<InterfaceScaleSlider> createState() =>
      _InterfaceScaleSliderState();
}

class _InterfaceScaleSliderState extends material.State<InterfaceScaleSlider> {
  bool _fineControl = false;

  static int get _fineDivisions =>
      ((kMaxUiScale - kMinUiScale) / kUiScaleStep).round();

  bool get _shiftHeld => HardwareKeyboard.instance.isShiftPressed;

  void _syncModifierKeys() {
    final fine = _shiftHeld;
    if (fine != _fineControl) {
      setState(() => _fineControl = fine);
    }
  }

  double _sliderPosition(double scale, {required bool fine}) {
    if (fine) return scale;
    return nearestUiScalePresetIndex(scale).toDouble();
  }

  double _scaleFromSlider(double position, {required bool fine}) {
    if (fine) return position;
    final index = position.round().clamp(0, kUiScalePresets.length - 1);
    return kUiScalePresets[index];
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (widget.scale * 100).round();
    final fine = _fineControl;

    return material.Listener(
        onPointerDown: (_) => _syncModifierKeys(),
        onPointerMove: (_) => _syncModifierKeys(),
        child: material.Row(
          children: [
            material.Expanded(
              child: Slider(
                value: SliderValue.single(
                  _sliderPosition(widget.scale, fine: fine),
                ),
                min: fine ? kMinUiScale : 0,
                max: fine
                    ? kMaxUiScale
                    : (kUiScalePresets.length - 1).toDouble(),
                divisions: fine ? _fineDivisions : kUiScalePresets.length - 1,
                hintValue: const SliderValue.single(kDefaultUiScale),
                onChanged: (value) {
                  _syncModifierKeys();
                  final next = _scaleFromSlider(
                    value.value,
                    fine: _shiftHeld,
                  );
                  UiScaleController.instance.setScalePreview(
                    next,
                    fine: _shiftHeld,
                  );
                },
                onChangeEnd: (value) {
                  final next = _scaleFromSlider(
                    value.value,
                    fine: _shiftHeld,
                  );
                  unawaited(
                    UiScaleController.instance.commitScale(
                      next,
                      fine: _shiftHeld,
                    ),
                  );
                },
              ),
            ),
            const material.SizedBox(width: 8),
            material.SizedBox(
              width: 44,
              child: material.Text(
                '$pct%',
                textAlign: material.TextAlign.right,
                style: material.TextStyle(
                  fontSize: 13,
                  fontWeight: material.FontWeight.w600,
                  color: cs.popoverForeground,
                ),
              ),
            ),
          ],
        ),
      );
  }
}

/// Preferences dropdown backed by [QueryaDropdown] ([MenuAnchor]).
class PreferencesDropdownMenu<T> extends StatelessWidget {
  const PreferencesDropdownMenu({
    super.key,
    required this.value,
    required this.entries,
    required this.onSelected,
    this.width,
    this.expandToParent = true,
    this.enabled = true,
  });

  final T value;
  final List<material.DropdownMenuEntry<T>> entries;
  final material.ValueChanged<T?> onSelected;

  /// Fixed width when [expandToParent] is false.
  final double? width;

  /// Fill parent — use inside [PreferencesFieldRow].
  final bool expandToParent;
  final bool enabled;

  @override
  material.Widget build(material.BuildContext context) {
    final items = [
      for (final entry in entries)
        QueryaDropdownItem<T>(
          value: entry.value,
          label: entry.label,
          enabled: entry.enabled,
        ),
    ];

    return QueryaDropdown<T>(
      value: value,
      items: items,
      enabled: enabled,
      width: width,
      expandToParent: expandToParent,
      onSelected: onSelected,
    );
  }
}
