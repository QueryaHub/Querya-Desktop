import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/extensions/sandbox/embedded/declarative_embedded_engine.dart';
import 'package:querya_desktop/core/extensions/sandbox/embedded/embedded_sandbox_engine.dart';
import 'package:querya_desktop/core/extensions/sandbox/embedded/native_embedded_engines.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_policy.dart';

/// Dispatches Level-1 embedded sandbox invocations (Block E M3).
///
/// Enforces `network: none` / scratch-only policy for embedded engines and
/// prefers the declarative JSONC engine when native QuickJS/WASM are not linked.
class EmbeddedSandboxRuntime {
  EmbeddedSandboxRuntime({
    EmbeddedSandboxEngine? declarative,
    EmbeddedSandboxEngine? quickJs,
    EmbeddedSandboxEngine? wasm,
  })  : _declarative = declarative ?? DeclarativeEmbeddedEngine(),
        _quickJs = quickJs ?? QuickJsEmbeddedEngine(),
        _wasm = wasm ?? WasmEmbeddedEngine();

  final EmbeddedSandboxEngine _declarative;
  final EmbeddedSandboxEngine _quickJs;
  final EmbeddedSandboxEngine _wasm;

  /// Runs [request] under the engine declared by [manifest] (or [engineOverride]).
  Future<EmbeddedInvokeResult> invoke({
    required EmbeddedInvokeRequest request,
    ExtensionManifest? manifest,
    SandboxEngine? engineOverride,
  }) async {
    if (manifest != null) {
      final violations = SandboxPolicy.validate(manifest);
      if (violations.isNotEmpty) {
        return EmbeddedInvokeResult.failure(
          'Sandbox policy violations: ${violations.join(' ')}',
        );
      }
      final sandbox = manifest.sandbox;
      if (sandbox != null &&
          sandbox.network.mode != NetworkPermissionMode.none) {
        return EmbeddedInvokeResult.failure(
          'Embedded runtime forbids network access '
          '(got ${sandbox.network.mode.value}).',
        );
      }
    }

    final engineId = engineOverride ??
        manifest?.sandbox?.engine ??
        SandboxEngine.quickjs;

    if (engineId == SandboxEngine.process) {
      return EmbeddedInvokeResult.failure(
        'Embedded runtime cannot execute OS-process engines; '
        'use SandboxProcessRunner instead.',
      );
    }

    final engine = _resolve(engineId);
    try {
      return await engine.invoke(request);
    } on EmbeddedEngineUnavailableException {
      // Fall back to declarative JSONC modules for Level-1 workloads.
      if (identical(engine, _declarative)) rethrow;
      return _declarative.invoke(request);
    }
  }

  EmbeddedSandboxEngine _resolve(SandboxEngine id) {
    switch (id) {
      case SandboxEngine.wasm:
        return _wasm.isAvailable ? _wasm : _declarative;
      case SandboxEngine.quickjs:
        return _quickJs.isAvailable ? _quickJs : _declarative;
      case SandboxEngine.process:
      case SandboxEngine.unknown:
        return _declarative;
    }
  }

  Future<void> dispose() async {
    await _declarative.dispose();
    await _quickJs.dispose();
    await _wasm.dispose();
  }
}
