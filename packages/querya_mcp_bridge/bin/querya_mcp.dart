// querya-mcp: stdio bridge between an MCP client (Claude Desktop, Cursor,
// VS Code, ...) and a running Querya Desktop. Released as a single static
// executable:
//
//   cd packages/querya_mcp_bridge && dart pub get
//   dart compile exe bin/querya_mcp.dart -o querya-mcp
//
// Client configuration:
//   { "mcpServers": { "querya": { "command": "/path/to/querya-mcp" } } }
import 'dart:io';

import 'package:querya_mcp_bridge/querya_mcp_bridge.dart';

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
