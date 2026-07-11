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

/// `contributions` block from an extension manifest.
class ExtensionContributions {
  const ExtensionContributions({this.drivers = const []});

  final List<DriverContribution> drivers;

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
    return ExtensionContributions(drivers: drivers);
  }

  Map<String, dynamic> toJson() => {
        if (drivers.isNotEmpty)
          'drivers': drivers.map((d) => d.toJson()).toList(),
      };

  bool get isEmpty => drivers.isEmpty;
}
