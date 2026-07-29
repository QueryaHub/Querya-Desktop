import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/layout/ui_scale_controller.dart';
import 'package:querya_desktop/core/layout/ui_scale.dart';
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

/// Leading checkbox + title/subtitle for Preferences (no [ListTile]).
///
/// Avoids Flutter 3.44+ asserts when Preferences chrome uses an opaque
/// [DecoratedBox] above Material ink (#491).
class PreferencesCheckboxRow extends StatelessWidget {
  const PreferencesCheckboxRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
  });

  final bool value;
  final material.ValueChanged<bool>? onChanged;
  final material.Widget title;
  final material.Widget? subtitle;

  @override
  material.Widget build(material.BuildContext context) {
    final enabled = onChanged != null;
    void toggle() {
      if (enabled) onChanged!(!value);
    }

    return material.Material(
      type: material.MaterialType.transparency,
      child: material.MergeSemantics(
        child: material.InkWell(
          onTap: enabled ? toggle : null,
          borderRadius: material.BorderRadius.circular(6),
          child: material.Padding(
            padding: const material.EdgeInsets.symmetric(vertical: 4),
            child: material.Row(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                material.SizedBox(
                  width: 24,
                  height: 24,
                  child: material.Checkbox(
                    value: value,
                    onChanged: enabled
                        ? (v) {
                            if (v != null) onChanged!(v);
                          }
                        : null,
                    materialTapTargetSize:
                        material.MaterialTapTargetSize.shrinkWrap,
                    visualDensity: material.VisualDensity.compact,
                  ),
                ),
                const material.SizedBox(width: 12),
                material.Expanded(
                  child: material.Column(
                    crossAxisAlignment: material.CrossAxisAlignment.start,
                    children: [
                      title,
                      if (subtitle != null) ...[
                        const material.SizedBox(height: 2),
                        subtitle!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
            material.Container(
              width: context.scaled(labelWidth),
              constraints: material.BoxConstraints(minHeight: triggerHeight),
              alignment: material.Alignment.centerLeft,
              child: Text(label).small().foreground(),
            ),
            const material.SizedBox(width: 12),
            material.Expanded(child: control),
          ],
        ),
        if (hint != null) ...[
          const material.SizedBox(height: 4),
          material.Padding(
            padding: material.EdgeInsets.only(left: context.scaled(labelWidth) + 12),
            child: PreferencesHint(hint!),
          ),
        ],
      ],
    );
  }
}

/// Interface scale slider: fixed presets by default; hold Shift for 1% fine steps.
///
/// Drag updates the label locally; [UiScaleController.commitScale] runs on release
/// so the rest of the app rebuilds once, not on every slider tick.
class InterfaceScaleSlider extends material.StatefulWidget {
  const InterfaceScaleSlider({super.key, this.scale});

  /// When set (e.g. in tests), overrides [UiScaleController.instance.scale].
  final double? scale;

  @override
  material.State<InterfaceScaleSlider> createState() =>
      _InterfaceScaleSliderState();
}

class _InterfaceScaleSliderState extends material.State<InterfaceScaleSlider> {
  bool _fineControl = false;
  double? _dragScale;

  static int get _fineDivisions =>
      ((kMaxUiScale - kMinUiScale) / kUiScaleStep).round();

  bool get _shiftHeld => HardwareKeyboard.instance.isShiftPressed;

  double get _committedScale =>
      widget.scale ?? UiScaleController.instance.scale;

  double get _displayScale => _dragScale ?? _committedScale;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    if (widget.scale == null) {
      UiScaleController.instance.addListener(_onCommittedScaleChanged);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    if (widget.scale == null) {
      UiScaleController.instance.removeListener(_onCommittedScaleChanged);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(InterfaceScaleSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scale != widget.scale) {
      _dragScale = null;
    }
  }

  void _onCommittedScaleChanged() {
    if (_dragScale != null || !mounted) return;
    setState(() {
      _dragScale = null;
    });
  }

  bool _onKeyEvent(KeyEvent event) {
    final fine = _shiftHeld;
    if (fine != _fineControl) {
      setState(() => _fineControl = fine);
    }
    return false;
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
    final displayScale = _displayScale;
    final pct = (displayScale * 100).round();
    final fine = _fineControl;

    return material.Row(
      children: [
        material.Expanded(
          child: Slider(
            value: SliderValue.single(
              _sliderPosition(displayScale, fine: fine),
            ),
            min: fine ? kMinUiScale : 0,
            max: fine ? kMaxUiScale : (kUiScalePresets.length - 1).toDouble(),
            divisions: fine ? _fineDivisions : kUiScalePresets.length - 1,
            hintValue: const SliderValue.single(kDefaultUiScale),
            onChanged: (value) {
              final next = _scaleFromSlider(
                value.value,
                fine: _shiftHeld,
              );
              setState(() => _dragScale = next);
            },
            onChangeEnd: (value) {
              final next = _scaleFromSlider(
                value.value,
                fine: _shiftHeld,
              );
              setState(() => _dragScale = null);
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
