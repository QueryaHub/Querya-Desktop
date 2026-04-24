# Querya Desktop — user guide

## First run

1. Start the app.
2. Create a connection: **Connection → New Database Connection** (or right-click **Servers** in the tree).
3. Pick **PostgreSQL**, **MySQL**, **Redis**, or **MongoDB** and fill in host, port, and credentials.
4. Saved connections appear in the left tree.

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

High-level feature depth varies by database type. PostgreSQL and MySQL include rich object trees and SQL workspaces; Redis and MongoDB focus on data exploration and commands suitable for day-to-day development.

For troubleshooting build/run issues, see the main [README.md](../README.md).
