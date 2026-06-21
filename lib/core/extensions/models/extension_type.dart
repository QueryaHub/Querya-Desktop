enum ExtensionType {
  databaseDriver('database_driver'),
  theme('theme'),
  unknown('unknown');

  final String value;
  const ExtensionType(this.value);

  static ExtensionType fromString(String value) {
    return ExtensionType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ExtensionType.unknown,
    );
  }
}
