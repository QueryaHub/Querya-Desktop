/// Human-readable explanation of a failed staged-changes Save.
///
/// Save runs every statement in one transaction, so a failure always means
/// nothing was written; the raw driver error stays available as [details].
class SaveErrorDescription {
  const SaveErrorDescription({
    required this.title,
    required this.message,
    this.hint,
    required this.details,
  });

  final String title;
  final String message;
  final String? hint;

  /// The original error text, for the collapsible details / copy.
  final String details;
}

/// Maps common SQLite / PostgreSQL / MySQL errors to plain language.
SaveErrorDescription describeSaveError(Object error) {
  final raw = error.toString();
  final text = _innermostMessage(raw);
  final lower = raw.toLowerCase();

  SaveErrorDescription d(String title, String message, [String? hint]) =>
      SaveErrorDescription(
        title: title,
        message: message,
        hint: hint,
        details: raw,
      );

  if (lower.contains('readonly database') ||
      lower.contains('read-only') ||
      lower.contains('read only transaction')) {
    return d(
      'The database is read-only',
      'This connection cannot write to the database.',
      'Turn off "Read only" in the connection settings or check the file / user permissions.',
    );
  }

  if (lower.contains('sqlite is busy') ||
      lower.contains('database is locked') ||
      lower.contains('sqlite_busy') ||
      lower.contains('lock wait timeout')) {
    return d(
      'The database is busy',
      'Another connection is writing to the database right now.',
      'If the SQL editor has an open transaction, commit or roll it back, then save again.',
    );
  }

  final uniqueCol = _firstGroup(text, [
    RegExp(r'UNIQUE constraint failed: ([\w."]+)', caseSensitive: false),
    RegExp(r'violates unique constraint "([^"]+)"', caseSensitive: false),
    RegExp(r"Duplicate entry '[^']*' for key '([^']+)'", caseSensitive: false),
  ]);
  if (uniqueCol != null || lower.contains('unique constraint')) {
    return d(
      'Duplicate value',
      uniqueCol == null
          ? 'A value must be unique, but it already exists.'
          : 'The value for ${_pretty(uniqueCol)} must be unique, but it already exists.',
      'Change the value or remove the other row first.',
    );
  }

  final notNullCol = _firstGroup(text, [
    RegExp(r'NOT NULL constraint failed: ([\w."]+)', caseSensitive: false),
    RegExp(r'null value in column "([^"]+)"', caseSensitive: false),
    RegExp(r"Column '([^']+)' cannot be null", caseSensitive: false),
  ]);
  if (notNullCol != null || lower.contains('not-null constraint')) {
    return d(
      'Missing required value',
      notNullCol == null
          ? 'A required column was left empty.'
          : '${_pretty(notNullCol)} cannot be empty.',
      'Enter a value for this column and save again.',
    );
  }

  if (lower.contains('foreign key')) {
    return d(
      'Related row problem',
      'The change breaks a foreign key: a referenced row is missing, or another row still points to this one.',
      'Check the related table, then save again.',
    );
  }

  if (lower.contains('check constraint')) {
    return d(
      'Value not allowed',
      'A value breaks a CHECK rule on this table.',
    );
  }

  if (lower.contains('datatype mismatch') ||
      lower.contains('invalid input syntax') ||
      lower.contains('incorrect integer value') ||
      lower.contains('incorrect decimal value') ||
      lower.contains('out of range')) {
    return d(
      'Wrong value type',
      'A value does not match the column type.',
      text.isEmpty ? null : text,
    );
  }

  if (lower.contains('matched 0 rows')) {
    return d(
      'The row changed',
      'The row was changed or deleted since it was loaded.',
      'Refresh the table and apply your edit again.',
    );
  }

  if (lower.contains('instead of 1')) {
    return d(
      'Row is not unique',
      'The edit would change several identical rows at once.',
      'The table has duplicate rows or no unique key. Add a primary key to edit such rows.',
    );
  }

  if (lower.contains('not connected') ||
      lower.contains('database_closed') ||
      lower.contains('connection closed') ||
      lower.contains('connection refused') ||
      lower.contains('socket')) {
    return d(
      'Connection lost',
      'The connection to the database was closed.',
      'Refresh to reconnect, then save again.',
    );
  }

  return d(
    'Changes were not saved',
    text.isEmpty ? raw : text,
  );
}

/// Strips wrapper noise such as `Bad state: ` and the sqflite exception prefix.
String _innermostMessage(String raw) {
  var s = raw;
  final sqlite = RegExp(r'SqliteException\(\d+\): (?:while \w+, )?([^,\n]+)')
      .firstMatch(s);
  if (sqlite != null) return sqlite.group(1)!.trim();
  for (final prefix in ['Bad state: ', 'Exception: ', 'StateError: ']) {
    if (s.startsWith(prefix)) s = s.substring(prefix.length);
  }
  final nl = s.indexOf('\n');
  return (nl == -1 ? s : s.substring(0, nl)).trim();
}

String? _firstGroup(String text, List<RegExp> patterns) {
  for (final p in patterns) {
    final m = p.firstMatch(text);
    if (m != null) return m.group(1);
  }
  return null;
}

/// `users.email` → `"email"`; constraint names are shown as-is.
String _pretty(String name) {
  final bare = name.replaceAll('"', '');
  final dot = bare.lastIndexOf('.');
  return '"${dot == -1 ? bare : bare.substring(dot + 1)}"';
}
