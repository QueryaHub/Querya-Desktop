/// Deep equality for JSON-like trees (maps, lists, primitives).
bool deepCollectionEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!deepCollectionEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepCollectionEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Updates [current] when [next] differs; returns true if changed.
bool replaceIfChanged<T>(T? current, T? next, void Function(T? value) apply) {
  if (deepCollectionEquals(current, next)) return false;
  apply(next);
  return true;
}
