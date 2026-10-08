// querya-mcp: stdio bridge between an MCP client (Claude Desktop, Cursor,
// VS Code, ...) and a running Querya Desktop. Released as a standalone
// executable built with `dart compile exe bin/querya_mcp.dart`.
//
// Client configuration:
//   { "mcpServers": { "querya": { "command": "/path/to/querya-mcp" } } }
import 'dart:io';

import 'package:querya_desktop/core/mcp/mcp_shim.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('Usage: querya-mcp\n\n'
        'Connects an MCP client over stdio to the MCP server of a running\n'
        'Querya Desktop (Settings > MCP). Takes no arguments; the endpoint\n'
        'file can be overridden with QUERYA_MCP_ENDPOINT.');
    return;
  }
  final code = await runMcpShim(input: stdin, output: stdout, errors: stderr);
  exit(code);
}
