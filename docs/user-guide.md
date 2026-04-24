# Querya Desktop — user guide

## First run

1. Start the app.
2. Create a connection: **Connection → New Database Connection** (or right-click **Servers** in the tree).
3. Pick **PostgreSQL**, **MySQL**, **Redis**, or **MongoDB** and fill in host, port, and credentials.
4. Saved connections appear in the left tree.

## Where data is stored

- **Connection list and settings**: local SQLite (`querya.db` under the app support directory).
- **Passwords / connection strings**: OS secure store (see [security.md](security.md)).

## Driver manager

**Connection → Driver Manager** lists **built-in** Dart drivers. You do **not** need to download a JDBC JAR to connect.

## Linux notes

- **Wayland**: if you see Gdk pointer warnings, try `GDK_BACKEND=x11 flutter run -d linux` or run via `./run_linux.sh` as documented in the README.
- **libsecret**: release builds on Linux link against the system keyring stack; distro packages such as `libsecret-1-dev` are required to **compile** the Linux desktop binary (CI installs these headers).

## Supported capabilities

High-level feature depth varies by database type. PostgreSQL and MySQL include rich object trees and SQL workspaces; Redis and MongoDB focus on data exploration and commands suitable for day-to-day development.

For troubleshooting build/run issues, see the main [README.md](../README.md).
