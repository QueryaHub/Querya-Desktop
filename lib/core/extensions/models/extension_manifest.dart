import 'extension_type.dart';

class ExtensionManifest {
  final String id;
  final String name;
  final String version;
  final String publisher;
  final ExtensionType type;
  final Map<String, String> engines;
  final String? main;
  final String? icon;
  final String? description;

  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.publisher,
    required this.type,
    required this.engines,
    this.main,
    this.icon,
    this.description,
  });

  factory ExtensionManifest.fromJson(Map<String, dynamic> json) {
    return ExtensionManifest(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      publisher: json['publisher'] as String,
      type: ExtensionType.fromString(json['type'] as String),
      engines: Map<String, String>.from(json['engines'] as Map? ?? {}),
      main: json['main'] as String?,
      icon: json['icon'] as String?,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'publisher': publisher,
      'type': type.value,
      'engines': engines,
      if (main != null) 'main': main,
      if (icon != null) 'icon': icon,
      if (description != null) 'description': description,
    };
  }
}
