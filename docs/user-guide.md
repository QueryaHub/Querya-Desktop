# Querya Desktop — user guide

## First run

1. Start the app.
2. Create a connection: **Connection → New Database Connection** (or right-click **Servers** in the tree).
3. Pick **PostgreSQL**, **MySQL**, **SQLite**, **Redis**, or **MongoDB**. For SQLite, select the database file; for other databases, fill in host, port, and credentials.
   - **Read-only mode**: You can toggle the **Read-only** option to prevent write operations (a lock icon will appear in the workspace).
4. Saved connections appear in the left tree.

## Connection Actions

The application menu and window title bar provide actions for managing database connections:
- **Connect**: Connect to the selected database connection.
- **Invalidate/Reconnect**: Refresh and re-establish the connection to the database.
- **Disconnect**: Safely close the active session.
- **Read-only**: Toggle read-only mode for the current session.

## Where data is stored

- **Connection list and settings**: local SQLite (`querya.db` under the app support directory).
- **Passwords / connection strings**: OS secure store (see [security.md](security.md)).

## Preferences

Open **Edit → Preferences…** to change options that apply across the app:

- **SQL statement timeouts** (PostgreSQL and MySQL) — **global** defaults for every connection of that type, not per-server. You can still change the timeout from the SQL workspace toolbar; both places stay in sync.
- **Max rows in results** — how many rows are loaded into the grid after running a query (large results may be truncated with a status message).
- **SQL editor font size** — monospace size in the query editor.

Preferences (except secrets) live in the same local SQLite file as connection metadata. A **settings** icon next to the statement timeout in the PostgreSQL/MySQL SQL toolbar opens the same dialog.

## Driver manager

**Connection → Driver Manager** lists **built-in** Dart drivers. You do **not** need to download a JDBC JAR to connect.

## Linux notes

- **Wayland**: if you see Gdk pointer warnings, try `GDK_BACKEND=x11 flutter run -d linux` or run via `./run_linux.sh` as documented in the README.
- **libsecret**: release builds on Linux link against the system keyring stack; distro packages such as `libsecret-1-dev` are required to **compile** the Linux desktop binary (CI installs these headers).

## Supported capabilities

High-level feature depth varies by database type. PostgreSQL, MySQL, and SQLite include rich object trees and SQL workspaces (with SQLite utilizing local `.db` files); Redis and MongoDB focus on data exploration and commands suitable for day-to-day development.

### Result row caps (SQL workspaces)

Preferences → **Max rows in results** caps how many rows the grid loads. For **PostgreSQL** and **SQLite**, ad-hoc `SELECT` / `WITH` / `VALUES` are bounded **before** execution:

- No author `LIMIT` → a `LIMIT` equal to the preference is injected.
- Author `LIMIT` / `LIMIT ALL` / `FETCH FIRST n ROWS ONLY` larger than the preference → clamped down to the preference (OFFSET kept when present).

Queries that already use a smaller `LIMIT`, and non-SELECT statements (`INSERT`, `PRAGMA`, …), are left unchanged. The UI may still truncate the displayed grid as a fallback. **MySQL** SQL workspace streams rows and stops at the cap client-side.

For troubleshooting build/run issues, see the main [README.md](../README.md).
