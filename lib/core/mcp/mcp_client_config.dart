import 'dart:convert';
import 'dart:io';

/// MCP clients Querya can write a configuration snippet for.
enum McpClientKind {
  claudeDesktop('Claude Desktop', 'claude_desktop_config.json'),
  cursor('Cursor', '~/.cursor/mcp.json'),
  vsCode('VS Code', '.vscode/mcp.json'),
  generic('Other (stdio)', 'your client\'s MCP settings');

  const McpClientKind(this.label, this.configLocation);

  final String label;

  /// Where the user pastes the snippet.
  final String configLocation;
}

/// Finds `querya-mcp` and builds client configuration snippets.
abstract final class McpClientConfig {
  static String get executableName =>
      Platform.isWindows ? 'querya-mcp.exe' : 'querya-mcp';

  /// `querya-mcp` next to the running app binary (bundled in Linux and
  /// Windows builds), or `null` when it is not there.
  static String? bundledShimPath({String? appExecutable}) {
    final exe = appExecutable ?? Platform.resolvedExecutable;
    if (exe.isEmpty) return null;
    final dir = File(exe).parent.path;
    final candidate = File('$dir${Platform.pathSeparator}$executableName');
    return candidate.existsSync() ? candidate.path : null;
  }

  /// JSON the user pastes into [kind]'s configuration.
  static String snippet(McpClientKind kind, String shimPath) {
    final Map<String, Object?> json = switch (kind) {
      McpClientKind.vsCode => {
          'servers': {
            'querya': {'type': 'stdio', 'command': shimPath},
          },
        },
      McpClientKind.claudeDesktop ||
      McpClientKind.cursor ||
      McpClientKind.generic =>
        {
          'mcpServers': {
            'querya': {'command': shimPath},
          },
        },
    };
    return const JsonEncoder.withIndent('  ').convert(json);
  }
}
