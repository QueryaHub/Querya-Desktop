# Planned release 0.4.5 — SQLite Database Connector

**Status:** **Planned** (GitHub milestone [**0.4.5**](https://github.com/QueryaHub/Querya-Desktop/milestones), epic **#194**).  
**Depends on:** **0.4.4** UI motion polish (shipped).

Theme: Add support for local SQLite database file connections. This allows users to select `.db`, `.sqlite`, or `.sqlite3` files from their disk, browse their schema, run arbitrary SQL queries in a dedicated workspace, and view paginated table grids.

## Why

- **Highly Requested**: SQLite is one of the most requested local database connectors by developers who want to inspect local app databases, cache files, or development databases.
- **Zero-Increase Bundle Size**: SQLite support can be fully implemented using the existing `sqflite_common_ffi` package already bundled for `LocalDb`, keeping the binary lightweight and dependency-clean.

## Scope

| ID | Issue | Scope | Summary |
|----|-------|--------|---------|
| **SQL-S1** | #195 | `sqlite`, `core` | **Core Driver** — implement `SqliteConnection` wrapping `sqflite_common_ffi` and `SqliteService` to manage active connection handles to local files. |
| **SQL-S2** | #196 | `sqlite`, `core` | **Schema Resolver** — read tables, views, and indexes metadata via `sqlite_master` catalog tables and column info via `PRAGMA table_info`. |
| **SQL-S3** | #197 | `sqlite`, `ui` | **Connection Form** — create `SqliteConnectionForm` integrating native OS file picker (`file_selector` package) and a "Read-Only" safety toggle. |
| **SQL-S4** | #198 | `sqlite`, `ui` | **Sidebar Integration** — render SQLite connections and their schema nodes in `ConnectionsPanel` connection tree. |
| **SQL-S5** | #199 | `sqlite`, `ui` | **Workspace & Table View** — implement `SqliteWorkspaceHome` (SQL editor) and a paginated `SqliteTableView` database browser. |
| **SQL-S6** | #200 | `sqlite`, `test` | **Test Coverage** — write unit tests for connection driver and widget/integration tests for workspace actions. |

## Suggested PR order

1. SQL-S1 & SQL-S2 — SQLite connection driver and catalog schema parser
2. SQL-S3 — Connection form with file picker dialog
3. SQL-S4 — Sidebar connection tree integration
4. SQL-S5 — SQLite SQL workspace editor and paginated data table
5. SQL-S6 — Tests and verification

## Out of scope for 0.4.5

- **SQLCipher / Encrypted SQLite files** — deferred to **0.4.6+** (requires compiling/linking SQLCipher binary dependencies).
- **In-Memory SQLite Database connections** — deferred.
- **Local DB migration to another engine**.
