/// Capability flags declared by an extension (`capabilities` in manifest.json).
class ExtensionCapabilities {
  const ExtensionCapabilities({
    this.databaseDriver = false,
    this.sduiForms = false,
    this.extra = const {},
  });

  final bool databaseDriver;
  final bool sduiForms;

  /// Additional boolean flags preserved for round-trip.
  final Map<String, bool> extra;

  factory ExtensionCapabilities.fromJson(Map<String, dynamic> json) {
    final known = {'databaseDriver', 'sduiForms'};
    final extra = <String, bool>{};
    for (final entry in json.entries) {
      if (known.contains(entry.key)) continue;
      if (entry.value is bool) {
        extra[entry.key] = entry.value as bool;
      }
    }
    return ExtensionCapabilities(
      databaseDriver: json['databaseDriver'] == true,
      sduiForms: json['sduiForms'] == true,
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() => {
        if (databaseDriver) 'databaseDriver': true,
        if (sduiForms) 'sduiForms': true,
        ...extra,
      };

  bool get isEmpty => !databaseDriver && !sduiForms && extra.isEmpty;
}

/// A single database driver contribution under `contributions.drivers`.
class DriverContribution {
  const DriverContribution({
    required this.driverId,
    required this.displayName,
    this.defaultPort,
    this.connectionFormSchema,
    this.icon,
  });

  final String driverId;
  final String displayName;
  final int? defaultPort;

  /// Relative path to an SDUI connection form JSON (from extension root).
  final String? connectionFormSchema;
  final String? icon;

  factory DriverContribution.fromJson(Map<String, dynamic> json) {
    final portRaw = json['defaultPort'];
    int? port;
    if (portRaw is int) {
      port = portRaw;
    } else if (portRaw is num) {
      port = portRaw.toInt();
    } else if (portRaw != null) {
      port = int.tryParse('$portRaw');
    }
    return DriverContribution(
      driverId: '${json['driverId'] ?? ''}',
      displayName: '${json['displayName'] ?? json['driverId'] ?? ''}',
      defaultPort: port,
      connectionFormSchema: json['connectionFormSchema'] as String?,
      icon: json['icon'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'driverId': driverId,
        'displayName': displayName,
        if (defaultPort != null) 'defaultPort': defaultPort,
        if (connectionFormSchema != null)
          'connectionFormSchema': connectionFormSchema,
        if (icon != null) 'icon': icon,
      };
}

/// A Command Palette action declared under `contributions.commands`
/// or the VS Code-style `contributes.commands` alias.
class CommandContribution {
  const CommandContribution({
    required this.id,
    required this.title,
    this.category,
    this.aliases = const [],
  });

  final String id;
  final String title;
  final String? category;
  final List<String> aliases;

  factory CommandContribution.fromJson(Map<String, dynamic> json) {
    final aliasesRaw = json['aliases'];
    return CommandContribution(
      id: '${json['id'] ?? ''}'.trim(),
      title: '${json['title'] ?? json['id'] ?? ''}'.trim(),
      category: json['category'] as String?,
      aliases: aliasesRaw is List
          ? [for (final a in aliasesRaw) '$a']
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (category != null) 'category': category,
        if (aliases.isNotEmpty) 'aliases': aliases,
      };
}

/// `contributions` / `contributes` block from an extension manifest.
class ExtensionContributions {
  const ExtensionContributions({
    this.drivers = const [],
    this.commands = const [],
  });

  final List<DriverContribution> drivers;
  final List<CommandContribution> commands;

  factory ExtensionContributions.fromJson(Map<String, dynamic> json) {
    final driversRaw = json['drivers'];
    final drivers = <DriverContribution>[];
    if (driversRaw is List) {
      for (final item in driversRaw) {
        if (item is Map<String, dynamic>) {
          drivers.add(DriverContribution.fromJson(item));
        } else if (item is Map) {
          drivers.add(
            DriverContribution.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return ExtensionContributions(
      drivers: drivers,
      commands: parseCommandList(json['commands']),
    );
  }

  static List<CommandContribution> parseCommandList(Object? raw) {
    final commands = <CommandContribution>[];
    if (raw is! List) return commands;
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        commands.add(CommandContribution.fromJson(item));
      } else if (item is Map) {
        commands.add(
          CommandContribution.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    }
    return commands.where((c) => c.id.isNotEmpty && c.title.isNotEmpty).toList();
  }

  static ExtensionContributions merge(
    ExtensionContributions? a,
    ExtensionContributions? b,
  ) {
    if (a == null) return b ?? const ExtensionContributions();
    if (b == null) return a;
    return ExtensionContributions(
      drivers: [...a.drivers, ...b.drivers],
      commands: [...a.commands, ...b.commands],
    );
  }

  Map<String, dynamic> toJson() => {
        if (drivers.isNotEmpty)
          'drivers': drivers.map((d) => d.toJson()).toList(),
        if (commands.isNotEmpty)
          'commands': commands.map((c) => c.toJson()).toList(),
      };

  bool get isEmpty => drivers.isEmpty && commands.isEmpty;
}
