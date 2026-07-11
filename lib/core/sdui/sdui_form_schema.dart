/// Field kinds supported by [SduiFormBuilder] (Block A §2.1).
enum SduiFieldType {
  text('text'),
  number('number'),
  password('password'),
  checkbox('checkbox'),
  select('select'),
  filePicker('file_picker');

  const SduiFieldType(this.value);
  final String value;

  static SduiFieldType fromString(String? value) {
    if (value == 'boolean') return SduiFieldType.checkbox;
    return SduiFieldType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => SduiFieldType.text,
    );
  }
}

class SduiSelectOption {
  const SduiSelectOption({required this.value, required this.label});

  final String value;
  final String label;

  factory SduiSelectOption.fromJson(Map<String, dynamic> json) {
    return SduiSelectOption(
      value: '${json['value'] ?? ''}',
      label: '${json['label'] ?? json['value'] ?? ''}',
    );
  }
}

class SduiFormField {
  const SduiFormField({
    required this.id,
    required this.type,
    required this.label,
    this.required = false,
    this.placeholder,
    this.defaultValue,
    this.options = const [],
  });

  final String id;
  final SduiFieldType type;
  final String label;
  final bool required;
  final String? placeholder;
  final Object? defaultValue;
  final List<SduiSelectOption> options;

  factory SduiFormField.fromJson(Map<String, dynamic> json) {
    final optionsRaw = json['options'];
    final options = <SduiSelectOption>[];
    if (optionsRaw is List) {
      for (final item in optionsRaw) {
        if (item is Map<String, dynamic>) {
          options.add(SduiSelectOption.fromJson(item));
        } else if (item is Map) {
          options.add(SduiSelectOption.fromJson(Map<String, dynamic>.from(item)));
        } else if (item != null) {
          options.add(SduiSelectOption(value: '$item', label: '$item'));
        }
      }
    }

    final fieldId = '${json['id'] ?? json['key'] ?? json['name'] ?? ''}';
    return SduiFormField(
      id: fieldId,
      type: SduiFieldType.fromString(json['type'] as String?),
      label: '${json['label'] ?? fieldId}',
      required: json['required'] == true,
      placeholder: json['placeholder'] as String?,
      defaultValue: json['default'] ?? json['defaultValue'],
      options: options,
    );
  }
}

/// Schema returned by `extension.getConnectionForm`.
class SduiFormSchema {
  const SduiFormSchema({
    this.title,
    this.fields = const [],
  });

  final String? title;
  final List<SduiFormField> fields;

  factory SduiFormSchema.fromJson(Map<String, dynamic> json) {
    final fieldsRaw = json['fields'];
    final fields = <SduiFormField>[];
    if (fieldsRaw is List) {
      for (final item in fieldsRaw) {
        if (item is Map<String, dynamic>) {
          fields.add(SduiFormField.fromJson(item));
        } else if (item is Map) {
          fields.add(SduiFormField.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return SduiFormSchema(
      title: json['title'] as String?,
      fields: fields,
    );
  }
}
