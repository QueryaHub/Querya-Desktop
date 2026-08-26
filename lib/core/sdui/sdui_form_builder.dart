import 'package:flutter/material.dart' as material;
import 'package:file_selector/file_selector.dart';
import 'package:querya_desktop/core/sdui/sdui_form_schema.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Renders a connection / settings form from an SDUI JSON schema (Block A).
///
/// Call [collectValues] after the user submits; returns `null` when validation
/// fails. Password fields are included in the map — the host should persist
/// them via `ConnectionSecretsStore`, never via the plugin process disk.
class SduiFormBuilder extends material.StatefulWidget {
  const SduiFormBuilder({
    super.key,
    required this.schema,
    this.initialValues = const {},
    this.onChanged,
    this.filePicker,
    this.keepExistingSecrets = false,
  });

  final SduiFormSchema schema;
  final Map<String, Object?> initialValues;
  final void Function(Map<String, Object?> values)? onChanged;

  /// Injectable file picker for tests. Defaults to `openFile`.
  final Future<String?> Function(SduiFormField field)? filePicker;

  /// When true (edit connection), blank password fields are valid and show
  /// "Leave blank to keep existing" — host merges stored secrets on save.
  final bool keepExistingSecrets;

  @override
  material.State<SduiFormBuilder> createState() => SduiFormBuilderState();
}

class SduiFormBuilderState extends material.State<SduiFormBuilder> {
  final _formKey = material.GlobalKey<material.FormState>();
  final Map<String, material.TextEditingController> _textControllers = {};
  final Map<String, bool> _checkboxValues = {};
  final Map<String, String?> _selectValues = {};

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void didUpdateWidget(covariant SduiFormBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schema != widget.schema) {
      _disposeControllers();
      _hydrate();
    }
  }

  void _hydrate() {
    for (final field in widget.schema.fields) {
      final initial = widget.initialValues[field.id] ?? field.defaultValue;
      switch (field.type) {
        case SduiFieldType.checkbox:
          _checkboxValues[field.id] = initial == true || initial == 'true';
        case SduiFieldType.select:
          _selectValues[field.id] = initial?.toString() ??
              (field.options.isNotEmpty ? field.options.first.value : null);
        case SduiFieldType.text:
        case SduiFieldType.number:
        case SduiFieldType.password:
        case SduiFieldType.filePicker:
          _textControllers[field.id] = material.TextEditingController(
            text: initial?.toString() ?? '',
          )..addListener(_notifyChanged);
      }
    }
  }

  void _notifyChanged() {
    widget.onChanged?.call(snapshotValues());
  }

  /// Current values without validating required fields.
  Map<String, Object?> snapshotValues() {
    final out = <String, Object?>{};
    for (final field in widget.schema.fields) {
      switch (field.type) {
        case SduiFieldType.checkbox:
          out[field.id] = _checkboxValues[field.id] ?? false;
        case SduiFieldType.select:
          out[field.id] = _selectValues[field.id];
        case SduiFieldType.number:
          final raw = _textControllers[field.id]?.text.trim() ?? '';
          if (raw.isEmpty) {
            out[field.id] = null;
          } else {
            out[field.id] = num.tryParse(raw) ?? raw;
          }
        case SduiFieldType.text:
        case SduiFieldType.password:
        case SduiFieldType.filePicker:
          final text = _textControllers[field.id]?.text ?? '';
          out[field.id] = text;
      }
    }
    return out;
  }

  /// Validates the form and returns values, or `null` if invalid.
  Map<String, Object?>? collectValues() {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return null;
    return snapshotValues();
  }

  /// Ids of password fields (for secure storage by the host).
  List<String> get passwordFieldIds => widget.schema.fields
      .where((f) => f.type == SduiFieldType.password)
      .map((f) => f.id)
      .toList(growable: false);

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    _textControllers.clear();
    _checkboxValues.clear();
    _selectValues.clear();
  }

  Future<void> _pickFile(SduiFormField field) async {
    final picker = widget.filePicker;
    final path =
        picker != null ? await picker(field) : (await openFile())?.path;
    if (path == null || !mounted) return;
    setState(() {
      _textControllers[field.id]?.text = path;
    });
    _notifyChanged();
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.FocusTraversalGroup(
      policy: material.WidgetOrderTraversalPolicy(),
      child: material.Form(
        key: _formKey,
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          mainAxisSize: material.MainAxisSize.min,
          children: [
            if (widget.schema.title != null) ...[
              Text(widget.schema.title!).large().semiBold(),
              const Gap(12),
            ],
            for (var i = 0; i < widget.schema.fields.length; i++) ...[
              if (i > 0) const Gap(12),
              _buildField(widget.schema.fields[i]),
            ],
          ],
        ),
      ),
    );
  }

  material.Widget _buildField(SduiFormField field) {
    switch (field.type) {
      case SduiFieldType.checkbox:
        // Avoid CheckboxListTile under opaque dialog DecoratedBox (Flutter 3.44+
        // ListTile ink assert — #492).
        final checked = _checkboxValues[field.id] ?? false;
        return material.Material(
          type: material.MaterialType.transparency,
          child: material.MergeSemantics(
            child: material.InkWell(
              onTap: () {
                setState(() => _checkboxValues[field.id] = !checked);
                _notifyChanged();
              },
              borderRadius: material.BorderRadius.circular(6),
              child: material.Row(
                crossAxisAlignment: material.CrossAxisAlignment.center,
                children: [
                  material.SizedBox(
                    width: 24,
                    height: 24,
                    child: material.Checkbox(
                      value: checked,
                      materialTapTargetSize:
                          material.MaterialTapTargetSize.shrinkWrap,
                      visualDensity: material.VisualDensity.compact,
                      onChanged: (v) {
                        setState(() => _checkboxValues[field.id] = v ?? false);
                        _notifyChanged();
                      },
                    ),
                  ),
                  const Gap(12),
                  material.Expanded(child: Text(field.label)),
                ],
              ),
            ),
          ),
        );
      case SduiFieldType.select:
        final options = field.options;
        final current = _selectValues[field.id] ??
            (options.isNotEmpty ? options.first.value : '');
        return material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            Text(field.label).small().semiBold(),
            const Gap(4),
            material.FormField<String>(
              initialValue: current,
              validator: field.required
                  ? (v) => (v == null || v.isEmpty)
                      ? '${field.label} is required'
                      : null
                  : null,
              builder: (state) {
                final value = state.value ?? current;
                return material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: [
                    QueryaDropdown<String>(
                      value: value.isEmpty && options.isNotEmpty
                          ? options.first.value
                          : value,
                      expandToParent: true,
                      items: [
                        for (final opt in options)
                          QueryaDropdownItem<String>(
                            value: opt.value,
                            label: opt.label,
                          ),
                      ],
                      onSelected: (v) {
                        final next = v ?? value;
                        setState(() => _selectValues[field.id] = next);
                        state.didChange(next);
                        _notifyChanged();
                      },
                    ),
                    if (state.hasError) ...[
                      const Gap(4),
                      Text(state.errorText!).xSmall().muted(),
                    ],
                  ],
                );
              },
            ),
          ],
        );
      case SduiFieldType.filePicker:
        final controller = _textControllers[field.id]!;
        return material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            Text(field.label).small().semiBold(),
            const Gap(4),
            material.Row(
              children: [
                material.Expanded(
                  child: material.TextFormField(
                    controller: controller,
                    decoration: material.InputDecoration(
                      hintText: field.placeholder ?? 'Path…',
                    ),
                    validator: _validatorFor(field),
                  ),
                ),
                const Gap(8),
                OutlineButton(
                  onPressed: () => _pickFile(field),
                  child: const Text('Browse'),
                ),
              ],
            ),
          ],
        );
      case SduiFieldType.text:
      case SduiFieldType.number:
      case SduiFieldType.password:
        final controller = _textControllers[field.id]!;
        return material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            Text(field.label).small().semiBold(),
            const Gap(4),
            material.TextFormField(
              controller: controller,
              obscureText: field.type == SduiFieldType.password,
              keyboardType: field.type == SduiFieldType.number
                  ? material.TextInputType.number
                  : material.TextInputType.text,
              decoration: material.InputDecoration(
                hintText: _hintFor(field),
              ),
              validator: _validatorFor(field),
            ),
          ],
        );
    }
  }

  String? _hintFor(SduiFormField field) {
    if (widget.keepExistingSecrets &&
        field.type == SduiFieldType.password) {
      return 'Leave blank to keep existing';
    }
    return field.placeholder;
  }

  material.FormFieldValidator<String>? _validatorFor(SduiFormField field) {
    return (value) {
      final text = value?.trim() ?? '';
      final allowBlankSecret = widget.keepExistingSecrets &&
          field.type == SduiFieldType.password;
      if (field.required && text.isEmpty && !allowBlankSecret) {
        return '${field.label} is required';
      }
      if (field.type == SduiFieldType.number && text.isNotEmpty) {
        if (num.tryParse(text) == null) {
          return '${field.label} must be a number';
        }
      }
      return null;
    };
  }
}
