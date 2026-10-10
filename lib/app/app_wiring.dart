import 'package:querya_desktop/app/mcp_sql_delegates.dart';
import 'package:querya_desktop/app/querya_core_commands.dart';
import 'package:querya_desktop/core/actions/querya_command_registry.dart';
import 'package:querya_desktop/core/extensions/extension_command_sync.dart';
import 'package:querya_desktop/core/mcp/mcp_server_controller.dart';
import 'package:querya_desktop/features/extensions/extension_connection_picker_dialog.dart';

/// Hands `core/` the pieces that live in `features/`: `core/` must not import
/// `features/` (see `docs/architecture.md`), so the app installs them here.
///
/// Call before the first frame and before the MCP server starts. Idempotent.
void installAppWiring() {
  QueryaCommandRegistry.instance.coreCommands = queryaCoreCommands;
  ExtensionCommandSync.instance.connectionPicker =
      showExtensionConnectionPickerDialog;
  McpServerController.delegateFactory = createReadOnlyMcpDelegate;
}
