import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';

/// Methods exposed to Level-1 embedded guests (no network / no host FS).
enum EmbeddedInvokeMethod {
  /// Transform a Server-Driven UI JSON document.
  sduiTransform('sdui.transform'),

  /// Pretty-print / normalize SQL text.
  sqlFormat('sql.format'),

  /// Produce editor hint / autocomplete schema fragments.
  hintsGenerate('hints.generate'),

  /// Parse a dialect-specific SQL fragment into a JSON AST-ish structure.
  sqlParse('sql.parse'),

  /// Generic module entry (`main` / custom).
  invoke('invoke');

  const EmbeddedInvokeMethod(this.value);
  final String value;

  static EmbeddedInvokeMethod fromString(String value) {
    return EmbeddedInvokeMethod.values.firstWhere(
      (m) => m.value == value,
      orElse: () => EmbeddedInvokeMethod.invoke,
    );
  }
}

class EmbeddedInvokeRequest {
  const EmbeddedInvokeRequest({
    required this.method,
    this.args = const {},
    this.source,
    this.moduleId,
  });

  final EmbeddedInvokeMethod method;
  final Map<String, Object?> args;

  /// Already-loaded module source (JSON / JS / WASM bytes as base64, etc.).
  final String? source;
  final String? moduleId;
}

class EmbeddedInvokeResult {
  const EmbeddedInvokeResult({
    required this.ok,
    this.value,
    this.error,
  });

  final bool ok;
  final Object? value;
  final String? error;

  factory EmbeddedInvokeResult.success(Object? value) =>
      EmbeddedInvokeResult(ok: true, value: value);

  factory EmbeddedInvokeResult.failure(String error) =>
      EmbeddedInvokeResult(ok: false, error: error);
}

/// In-process Level-1 sandbox engine (WASM / QuickJS / declarative).
abstract class EmbeddedSandboxEngine {
  SandboxEngine get engine;

  /// Whether this build can actually execute guest code.
  bool get isAvailable;

  Future<EmbeddedInvokeResult> invoke(EmbeddedInvokeRequest request);

  Future<void> dispose();
}

class EmbeddedEngineUnavailableException implements Exception {
  EmbeddedEngineUnavailableException(this.message);
  final String message;

  @override
  String toString() => 'EmbeddedEngineUnavailableException: $message';
}
