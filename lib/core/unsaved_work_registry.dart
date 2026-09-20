import 'package:flutter/foundation.dart';

/// Process-wide probes for unsaved SQL, staged grid edits, and document editors.
///
/// Used by the in-app updater (and similar quit paths) to warn before
/// discarding work. Owners register a probe and must unregister on dispose.
class UnsavedWorkRegistry {
  UnsavedWorkRegistry._();

  static final UnsavedWorkRegistry instance = UnsavedWorkRegistry._();

  final Map<Object, bool Function()> _probes = {};

  void register(Object owner, bool Function() hasUnsaved) {
    _probes[owner] = hasUnsaved;
  }

  void unregister(Object owner) {
    _probes.remove(owner);
  }

  bool get hasUnsaved {
    for (final probe in _probes.values) {
      if (probe()) return true;
    }
    return false;
  }

  @visibleForTesting
  void resetForTest() => _probes.clear();
}
