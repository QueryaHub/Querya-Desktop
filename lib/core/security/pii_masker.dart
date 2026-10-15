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

bool _isLower(int c) => c >= 0x61 && c <= 0x7A;
bool _isUpper(int c) => c >= 0x41 && c <= 0x5A;
bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// Splits a column name into lower-case words: on non-alphanumerics and on
/// camelCase boundaries (`userEmail` -> `user`, `email`).
///
/// One pass over the code units (no regex, no split / join). A boundary is a
/// lower-case letter or digit followed by an upper-case letter.
List<String> _tokens(String name) {
  final tokens = <String>[];
  var start = -1;
  for (var i = 0; i < name.length; i++) {
    final c = name.codeUnitAt(i);
    final alnum = _isLower(c) || _isUpper(c) || _isDigit(c);
    if (!alnum) {
      if (start >= 0) {
        tokens.add(name.substring(start, i).toLowerCase());
        start = -1;
      }
      continue;
    }
    if (start >= 0 && _isUpper(c)) {
      final prev = name.codeUnitAt(i - 1);
      if (_isLower(prev) || _isDigit(prev)) {
        tokens.add(name.substring(start, i).toLowerCase());
        start = i;
        continue;
      }
    }
    if (start < 0) start = i;
  }
  if (start >= 0) tokens.add(name.substring(start).toLowerCase());
  return tokens;
}

const _keyPrefixTokens = {'api', 'private', 'access', 'secret', 'auth'};

/// Timestamps / flags *about* a sensitive field are not the value itself.
const _metaTokens = {'at', 'verified', 'confirmed', 'sent', 'count', 'id'};

/// Most distinct column names remembered by [detectPiiColumn].
const int _detectCacheLimit = 1024;

/// Column names repeat (`id`, `name`, `created_at`...) from query to query, so
/// the answer per name is kept. Per isolate; cleared when it gets large.
final Map<String, PiiKind?> _detectCache = <String, PiiKind?>{};

PiiKind? _detectUncached(String columnName) {
  final tokens = _tokens(columnName);
  if (tokens.isEmpty) return null;
  // `api_key`, `private_key`, `access_key` are split into two words.
  for (var i = 0; i + 1 < tokens.length; i++) {
    if (tokens[i + 1] == 'key' && _keyPrefixTokens.contains(tokens[i])) {
      return PiiKind.secret;
    }
  }
  final lastToken = tokens.last;
  if (_metaTokens.contains(lastToken) && tokens.length > 1) return null;
  for (final t in tokens) {
    if (_secretTokens.contains(t)) return PiiKind.secret;
    if (_cardTokens.contains(t)) return PiiKind.card;
    if (_emailTokens.contains(t)) return PiiKind.email;
    if (_phoneTokens.contains(t)) return PiiKind.phone;
  }
  return null;
}

/// What [columnName] probably holds, or null when it does not look sensitive.
///
/// Matching is per word, so `user_email` and `userEmail` match but `hotel` and
/// `email_verified_at` do not trip the phone / email rules by accident.
PiiKind? detectPiiColumn(String columnName) {
  if (_detectCache.containsKey(columnName)) return _detectCache[columnName];
  final kind = _detectUncached(columnName);
  if (_detectCache.length >= _detectCacheLimit) _detectCache.clear();
  _detectCache[columnName] = kind;
  return kind;
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
      if (_countDigits(value, 8) < 8) return kPiiMaskDots;
      return '•••••••${_lastDigits(value, 2)}';
    case PiiKind.card:
      if (_countDigits(value, 12) < 12) return kPiiMaskDots;
      return '•••• •••• •••• ${_lastDigits(value, 4)}';
  }
}

/// Number of ASCII digits in [s], counting no further than [limit].
int _countDigits(String s, int limit) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    if (_isDigit(s.codeUnitAt(i))) {
      n++;
      if (n >= limit) return n;
    }
  }
  return n;
}

/// The last [take] ASCII digits of [s], in order. [s] must hold at least
/// [take] digits.
String _lastDigits(String s, int take) {
  final out = List<int>.filled(take, 0x30);
  var k = take;
  for (var i = s.length - 1; i >= 0 && k > 0; i--) {
    final c = s.codeUnitAt(i);
    if (_isDigit(c)) out[--k] = c;
  }
  return String.fromCharCodes(out);
}
