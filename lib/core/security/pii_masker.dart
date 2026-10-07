/// Kind of sensitive data a result column is assumed to hold, guessed from its
/// name.
enum PiiKind { secret, email, phone, card }

/// Dots shown instead of a hidden value.
const String kPiiMaskDots = '••••••••';

const _secretTokens = {
  'password', 'passwd', 'pwd', 'pass', 'passcode', 'passphrase', 'token',
  'secret', 'apikey', 'hash', 'salt',
};
const _emailTokens = {'email', 'mail'};
const _phoneTokens = {
  'phone', 'mobile', 'cell', 'tel', 'telephone', 'msisdn', 'fax',
};
const _cardTokens = {'card', 'cc', 'pan', 'iban'};

/// Splits a column name into lower-case words: on non-alphanumerics and on
/// camelCase boundaries (`userEmail` -> `user`, `email`).
List<String> _tokens(String name) {
  final spaced = name
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (m) => '${m[1]} ${m[2]}',
      )
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ');
  return spaced
      .toLowerCase()
      .split(' ')
      .where((t) => t.isNotEmpty)
      .toList();
}

/// What [columnName] probably holds, or null when it does not look sensitive.
///
/// Matching is per word, so `user_email` and `userEmail` match but `hotel` and
/// `email_verified_at` do not trip the phone / email rules by accident.
PiiKind? detectPiiColumn(String columnName) {
  final tokens = _tokens(columnName);
  if (tokens.isEmpty) return null;
  // `api_key`, `private_key`, `access_key` are split into two words.
  final joined = tokens.join('_');
  if (RegExp(r'(^|_)(api|private|access|secret|auth)_key($|_)')
      .hasMatch(joined)) {
    return PiiKind.secret;
  }
  // Timestamps / flags *about* a sensitive field are not the value itself.
  const metaTokens = {'at', 'verified', 'confirmed', 'sent', 'count', 'id'};
  final lastToken = tokens.last;
  if (metaTokens.contains(lastToken) && tokens.length > 1) return null;
  for (final t in tokens) {
    if (_secretTokens.contains(t)) return PiiKind.secret;
    if (_cardTokens.contains(t)) return PiiKind.card;
    if (_emailTokens.contains(t)) return PiiKind.email;
    if (_phoneTokens.contains(t)) return PiiKind.phone;
  }
  return null;
}

/// [detectPiiColumn] for every column.
List<PiiKind?> detectPiiColumns(List<String> columns) =>
    [for (final c in columns) detectPiiColumn(c)];

/// Masks [value] for [kind]. `NULL` and empty values are left alone so the
/// grid still shows which cells are empty.
String maskPiiValue(PiiKind kind, String value) {
  if (value.isEmpty || value == 'NULL') return value;
  switch (kind) {
    case PiiKind.secret:
      return kPiiMaskDots;
    case PiiKind.email:
      final at = value.indexOf('@');
      if (at <= 0 || at == value.length - 1) return kPiiMaskDots;
      final local = value.substring(0, at);
      final domain = value.substring(at + 1);
      final visible = local.length <= 2 ? 1 : 2;
      return '${local.substring(0, visible)}***@$domain';
    case PiiKind.phone:
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8) return kPiiMaskDots;
      return '•••••••${digits.substring(digits.length - 2)}';
    case PiiKind.card:
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 12) return kPiiMaskDots;
      return '•••• •••• •••• ${digits.substring(digits.length - 4)}';
  }
}
