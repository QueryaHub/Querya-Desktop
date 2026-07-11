import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/extensions/sandbox/embedded/embedded_sandbox_engine.dart';

/// Placeholder QuickJS FFI backend (Level 1).
///
/// Native `flutter_qjs` / QuickJS linkage lands in a follow-up; until then the
/// [DeclarativeEmbeddedEngine] serves JSONC modules on the QuickJS slot.
class QuickJsEmbeddedEngine implements EmbeddedSandboxEngine {
  @override
  SandboxEngine get engine => SandboxEngine.quickjs;

  @override
  bool get isAvailable => false;

  @override
  Future<void> dispose() async {}

  @override
  Future<EmbeddedInvokeResult> invoke(EmbeddedInvokeRequest request) async {
    throw EmbeddedEngineUnavailableException(
      'QuickJS FFI runtime is not linked in this build. '
      'Use a declarative JSONC module or wait for the native QuickJS backend.',
    );
  }
}

/// Placeholder WASI / wasmtime FFI backend (Level 1).
class WasmEmbeddedEngine implements EmbeddedSandboxEngine {
  @override
  SandboxEngine get engine => SandboxEngine.wasm;

  @override
  bool get isAvailable => false;

  @override
  Future<void> dispose() async {}

  @override
  Future<EmbeddedInvokeResult> invoke(EmbeddedInvokeRequest request) async {
    throw EmbeddedEngineUnavailableException(
      'WASM/WASI runtime (wasmtime) is not linked in this build. '
      'Use a declarative JSONC module or wait for the native WASM backend.',
    );
  }
}
