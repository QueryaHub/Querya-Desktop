# MCP server

Querya Desktop can act as an [MCP](https://modelcontextprotocol.io) server. Any
MCP client (Claude Desktop, Claude Code, Cursor, VS Code, Gemini CLI, Continue,
...) and whatever model it runs can then read the schema of the connections you
share and run **read-only** SQL through Querya. Querya has no chat of its own
and needs no AI provider keys: the client brings the model.

Supported: **PostgreSQL, MySQL, SQLite**. MongoDB, Redis and extension drivers
are not exposed yet.

## How it works

```
MCP client ──stdio──▶ querya-mcp ──127.0.0.1 + token──▶ Querya Desktop (running)
                                                         └─ connections, SSH tunnels, keyring
```

- The server runs **inside the running app**, so it uses your saved
  connections, SSH tunnels and passwords from the OS keyring. The model only
  sees each connection's id, name, type, environment tag and database name.
- The client starts `querya-mcp`, a small bridge that forwards the MCP session
  to the app over a loopback socket. If Querya is not running (or the server is
  off), every request gets the error *"Querya Desktop is not running or its MCP
  server is off"*.

## Enable it

1. **Preferences → MCP Server → Enable MCP server.** The status line shows the
   port and the number of connected clients.
2. Under **Shared connections**, switch on the connections the model may read.
   Nothing is shared by default. Connections tagged *Production* show a `PROD`
   badge: the model can read everything the connection's database user can.
3. Under **Connect a client**, press **Copy … config** for your client and paste
   it where the client keeps MCP servers (see below).

## `querya-mcp`

| Build | Where it is |
|---|---|
| Linux zip / AppImage / `.deb` / `.rpm` | next to the app binary, e.g. `/opt/querya-desktop/querya-mcp` |
| Windows zip / setup | next to `querya_desktop.exe` in the install folder |
| macOS, Flatpak | not bundled yet: download `querya-mcp-v<version>-<platform>` from the GitHub release |

The copy buttons insert the bundled path automatically; otherwise replace
`/path/to/querya-mcp` with where you put the downloaded binary.

## Client configuration

**Claude Desktop** (`claude_desktop_config.json`), **Cursor** (`~/.cursor/mcp.json`)
and most stdio clients:

```json
{
  "mcpServers": {
    "querya": { "command": "/opt/querya-desktop/querya-mcp" }
  }
}
```

**VS Code** (`.vscode/mcp.json` or user settings):

```json
{
  "servers": {
    "querya": { "type": "stdio", "command": "/opt/querya-desktop/querya-mcp" }
  }
}
```

**Claude Code:** `claude mcp add querya -- /opt/querya-desktop/querya-mcp`

**Gemini CLI** (`~/.gemini/settings.json`): the same `mcpServers` block as above.

## Tools

| Tool | Arguments | Returns |
|---|---|---|
| `list_connections` | — | shared connections: `id`, `name`, `type`, `environment`, `database` |
| `list_tables` | `connection_id` | tables with their column count |
| `describe_table` | `connection_id`, `table` | columns, types, primary key, foreign key targets, indexes |
| `sample_rows` | `connection_id`, `table`, `rows` (1-100, default 20) | first rows of the table |
| `run_query` | `connection_id`, `sql` | `columns`, `rows`, `row_count`, `truncated` |
| `explain_query` | `connection_id`, `sql` (without `EXPLAIN`) | the execution plan, without running the query |

Resource: `schema://<connection_id>` — all tables with columns and keys, for
clients that load context up front.

SQL errors come back as tool errors with the database's message, so the model
can fix its query and retry.

## Limits

- **Read-only.** One statement per call; only `SELECT`, `WITH` without
  data-modifying parts, `EXPLAIN` (without `ANALYZE`), `SHOW`, `DESCRIBE`,
  `VALUES`, and schema `PRAGMA`s on SQLite. See [security.md](security.md#mcp-server).
- **Rows:** at most 1000 per `run_query` (`truncated: true` when cut), 100 per
  `sample_rows`. **Cells** longer than 4 KB are cut with a marker.
- **Time:** 15 s per statement.
- **Tables:** base tables of the current schema / database; views are not
  listed yet.

## Activity log

**Preferences → MCP Server → Recent calls** lists the last calls (time, client,
tool, connection, SQL, rows and duration, or the error). The app keeps the last
200 in its local database; **Clear** empties it.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Querya Desktop is not running or its MCP server is off" | Start Querya and switch on **Enable MCP server**. |
| `list_connections` is empty | Share at least one PostgreSQL / MySQL / SQLite connection. |
| "Connection N is not available" | The connection was unshared or deleted; call `list_connections` again. |
| "Invalid Querya MCP token" | The token was regenerated or the app restarted with a new one: restart the MCP client. |
| Client cannot find `querya-mcp` | Use the absolute path; on macOS / Flatpak download the release binary and `chmod +x` it. |
| Several Querya instances | Set `QUERYA_MCP_ENDPOINT` to a different file for each instance and for its `querya-mcp`. |

The endpoint file (port and token) is `$XDG_RUNTIME_DIR/querya/mcp-endpoint.json`
on Linux (fallback `~/.cache/querya`), `~/Library/Caches/Querya/` on macOS and
`%LOCALAPPDATA%\Querya\` on Windows.

## For contributors

- Query core: `lib/core/mcp/mcp_query_service.dart`, guard `mcp_sql_guard.dart`,
  error redaction `mcp_redaction.dart`, read-only delegates `mcp_sql_delegates.dart`.
- Server and transport: `querya_mcp_server.dart` (`dart_mcp`),
  `mcp_socket_host.dart`, `mcp_server_controller.dart`.
- Bridge: `packages/querya_mcp_bridge` — a dependency-free package so
  `dart compile exe` produces one static binary (the app package has build
  hooks that `dart compile exe` refuses).
- Settings UI: `lib/features/settings/preferences_mcp_section.dart`.
- Tests: `test/core/mcp/` (security suite: `mcp_security_test.dart`).
- Epic: [#1133](https://github.com/QueryaHub/Querya-Desktop/issues/1133).
