# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.15] - 2026-09-06

Multi-tab SQL workspace sessions, content-aware adaptive column sizing and auto-fit in data grid, rich cell context menus, desktop file associations (.sql, .sqlite) with CLI open-with handling, categorized Master-Detail preferences with Keymap reference and theme editor modal, server-side column sorting in table views, connection tree quick search and pinning, and comprehensive UI freeze and isolate performance optimizations.

### Added

- **Multi-Tab SQL Workspace (#679, PR #684)** — Full support for multiple independent query sessions per connection with tab strip (`SqlQueryTabBar`), separate editor state, split panel sizing, query history, result grids, and DML staging buffers with `IndexedStack` state preservation and tab shortcuts (`Ctrl+T`, `Ctrl+W`, `Ctrl+Tab`, `Ctrl+Shift+Tab`).
- **Adaptive Content-Aware Column Sizing & Auto-Fit (#676, PR #681)** — Dynamic header-based minimum column widths (56px) without inflating compact columns (`id`, `status`), weighted distribution of excess viewport width in favor of long text fields (`name`, `description`), and double-click (`onDoubleTap`) on column header dividers for instantaneous content-aware auto-fit.
- **Data Grid Cell Context Menu & Non-Destructive Actions (#678, PR #683)** — Native right-click context menu with TSV/JSON/CSV copy formats (`Copy Value`, `Copy with Headers`, `Copy as JSON/CSV`), instant filter bridge (`Filter by this value`, `Filter out this value`), value inspector access (`Ctrl+I`), setting explicit `NULL` (`Alt+N`), and reverting cell changes.
- **Desktop File Associations & Open-With Handlers (#694, PR #695)** — Native file associations and Open-With support for SQL scripts (`.sql`) and SQLite databases (`.db`, `.sqlite`, `.sqlite3`) on Linux (`.desktop`, `%F`), macOS (`Info.plist`), and Windows (Inno Setup / Registry) via `FileLaunchService`.
- **Master-Detail Categorized Preferences Dialog (#686, #687, #688, #689, PR #690, #691, #692, #693)** — Modern two-pane Master-Detail preferences layout with sidebar categories (`General`, `Appearance`, `SQL & Editor`, `Data Grid`, `Extensions`, `Keymap`, `About & Storage`), global search (`Ctrl+F`), deep-linking, unified `PreferencesSwitchRow` toggles, update channel selector (Stable / Beta), interactive Keyboard Shortcuts (Keymap) reference matrix, and a dedicated visual Theme Editor modal window.
- **Connection Tree Quick Search, Filtering & Pinning (#680, PR #685)** — Global quick search in sidebar connections tree (`Ctrl+F` / `Cmd+F`) with auto-expanding matching folders, compact inline `TreeObjectFilterBar` for filtering tables/views/procedures in large schemas, and table/view pinning (⭐) with automatic top-of-list sorting.
- **Interactive Server-Side Column Sorting (#696, PR #697)** — Tri-state interactive server-side sorting (ASC -> DESC -> Natural) in SQLite, PostgreSQL, and MySQL table views with model row index mapping preservation in `VirtualResultGrid`.
- **UI/UX Polishing for Data Grid, Filter Bar & Staging (#700, PR #701)** — Semantic theme color tokens for filter suggestions (`cs.popover`, `cs.popoverForeground`, `cs.border`), disambiguated `Export ▾` menu vs `Save Changes` button, keyboard shortcut tooltips (`Ctrl+Insert`, `Ctrl+Delete`, `Ctrl+Z`, `Ctrl+S`), and quick filter bar close button / `Escape` dismiss handling.

### Changed & Performance

- **Elimination of UI Freezes & Isolate Performance Optimizations (#702, PR #703)** — Adaptive background isolate offloading for large table sorting (`sortResultGridRowsWithIndicesAdaptive`, $N \ge 3000$) with version tokenization, zero-allocation clean reads and caching in `DataGridStagingBuffer.effectiveRows`, caching of groupings tree in `DataGridGroupingsView` outside of `build()`, and 150ms debounced JSON/XML validation in `DataGridValuePanel`.
- **Universal Syntax Highlighting & Flicker-Free Editor (#694, PR #695)** — Enhanced SQL tokenizer and eliminated visual flicker during typing in `QueryaCodeEditor`.

### Fixed

- **Latent Bug Fixes & Stability (#677, #698, PR #682, #699)** — Resolved layout overflows and bottom padding breaks across SQLite forms and database overview screens, fixed MySQL/MariaDB backslash escaping in DML generator, prevented memory leaks on Staging Buffer disposal and debounce timers, validated unclosed string literals in SQL filter AST parser, and sanitized pipe characters and quotes in Markdown and SQL INSERT export formats.

## [0.4.14] - 2026-08-30

Near-instantaneous menubar dropdowns, native macOS PlatformMenuBar integration, destructive query confirmation safety modals, comprehensive memory optimizations (string interning, compact storage), grid keyboard navigation, rich cell inspector, and driver resilience hardening.

### Added

- **Instantaneous Menubar Dropdowns (#672, #673)** — Accelerated dropdown open animation to 60ms with `Curves.easeOutCubic`, eliminated initial pointer-down delay, unhindered titlebar dragging from gesture arena interference, and added toggle-close support.
- **Native macOS PlatformMenuBar Integration (#612, #626)** — Full native macOS top system menu integration with standard application, file, edit, view, and window submenus.
- **Destructive Query Confirmation Modal (#608, #622, #638, #641)** — Safety confirmation dialog for high-risk DDL and DML operations (`DROP`, `TRUNCATE`, bulk `DELETE`/`UPDATE` without `WHERE`) with SQL preview, detected operations list, and explicit acknowledgement check for core and extension workspaces.
- **Full Data Grid Keyboard Navigation (#662, #664)** — Seamless keyboard traversal across virtual grid cells using arrow keys, Tab/Shift+Tab, Enter to commit, and Escape to cancel.
- **Rich Cell Inspector Dialog (#663, #665)** — Dedicated multi-format modal inspector with tabbed views for raw text, JSON, XML/HTML, and binary/hex with word wrap toggle and copy actions.
- **Binary & BLOB Support in DML (#658, #661)** — Added full support for binary BLOB data in cell editing, DML staging buffer, and dialect-specific SQL generation (`X'...'`, `\x...`).
- **Extension Driver Crash Recovery & Restart UI (#667, #669)** — Visual driver crash banner with automatic heartbeat monitoring and one-click manual driver restart button.
- **Interactive Welcome Tour Expansion (#606, #624)** — Expanded onboarding guide with 6 interactive steps, keyboard shortcuts reference matrix, and 1-click sample sandbox setup.
- **Bi-Directional Navigation (#630, #635)** — Quick navigation links between database overview statistics, home view, and active tables.
- **Active Selection Sync to Tree (#633, #637)** — Synchronized active table and view selection in tabs with the connections sidebar tree.
- **Extension Driver SDUI Tree Selection Highlight (#639, #642)** — Visual selection highlighting for SDUI trees rendered by extension drivers.
- **Querya Extension Driver Mutation Standard (#563, #628)** — Formalized mutation standard specification and test suite for extension drivers.

### Changed & Performance

- **String Interning Pool (#604, #625)** — Deduplicated low-cardinality string allocations in query result grids, slashing heap allocations during large dataset exploration.
- **Compact Typed Storage & Lazy Cell Stringification (#605, #627)** — Compact memory representation for primitive column vectors, deferring string conversions until render.
- **Schwartzian Transform Grid Sorting (#602, #615)** — Precomputed sort keys in `sortResultGridRows` to eliminate redundant comparisons during column header sorts.
- **QuickSelect Median Calculation (#603, #616)** — O(N) median computation in `GridSelectionCalcEngine` instead of O(N log N) sorting.
- **Background Selection Calculation Offloading (#652, #655)** — Offloaded massive cell selection statistics calculations to background compute workers to keep the UI at 60 FPS.
- **DataGrid Filter Bar Debouncing (#651, #654)** — Debounced keystroke evaluation in the filter bar to avoid stutter during rapid filter typing.
- **ResultsTab Filtering Memoization (#650, #653)** — Cached filtered row indices when filter predicates and dataset rows remain unchanged across rebuilds.
- **Modularized Shared SQL Editor & Workbench (#646, #649)** — Clean modular decoupling of SQL editor tabs, query runners, and workbench state.
- **Inverted Core Imports Cleanup (#644, #647)** — Eliminated circular/inverted core-to-feature dependencies and cleanly extracted connection models to core.
- **App Lifecycle & Dispose Resource Cleanup (#670, #671)** — Hardened teardown of timer subscriptions, workers, and active sockets upon window closure.
- **Connection Pool Delay Tuning (#597, #601)** — Reduced idle connection disposal delay to 4 seconds for rapid tab switching.

### Fixed

- **In-Memory Secret Scrubbing (#607, #623)** — Zeroed in-memory buffers for database passwords and sensitive connection parameters immediately after authentication.
- **Redis Safe Disconnect & Socket Resilience (#657, #660)** — Protected Redis clients against unhandled socket close exceptions and connection teardown race conditions.
- **SQLite WAL Mode & Busy Timeout (#611, #617, #656, #659)** — Enabled Write-Ahead Logging (WAL) and 5000ms busy timeout in LocalDb and SQLite workspaces to eliminate database lock errors.
- **LocalDb Single-Flight Initialization (#645, #648)** — Guarded `LocalDb._open` against concurrent re-initialization race conditions.
- **Plugin JSON-RPC Bridge Resilience (#666, #668)** — Added heartbeat ping-pong, buffered message queues, and graceful restart on extension pipe drops.
- **SQL History Monotonic Ordering & Pruning (#629)** — Guaranteed monotonic ordering by auto-incrementing ID in query history queries and batch prune operations.
- **Literal 'NULL' vs Database NULL Differentiation (#595, #599)** — Fixed DML preview and staging buffer improperly treating the literal text `'NULL'` as SQL `NULL`.
- **DML Leading Zeroes Preservation (#594, #598)** — Prevented numeric string values (such as postal codes or phone numbers with leading zeroes) from being coerced to integers in generated DML.
- **Missing Primary Key Warning in DML (#596, #600)** — Displayed explicit duplicate key warnings in the DML preview modal for tables lacking primary keys.
- **Motion Wobble Harmonization (#631, #634)** — Harmonized workspace transition curves to eliminate dual-axis wobble during connection switching.
- **MongoDB & Redis Breadcrumbs (#632, #636)** — Preserved persistent breadcrumbs and smooth transitions during NoSQL key and collection navigation.
- **Focus Traversal in Connection Forms (#610, #621)** — Configured explicit `FocusTraversalGroup`s across multi-field connection dialogs.
- **Light Theme Accent Contrast (#609, #619)** — Enhanced light theme accent and ring contrast ratios for WCAG compliance.
- **Monospace Font Stack (#613, #618)** — Added Cascadia Code and Consolas to default monospace font fallback list.
- **Linux GDK Log Spam (#614, #620)** — Suppressed benign synthetic pointer and cursor theme GDK warnings in Linux console logs.


## [0.4.13] - 2026-08-25

Production-ready UI polish, complete interactive Data Grid editing suite, advanced query filtering, fluid collapsible navigation, and platform hardening.

### Added

- **In-Place Cell Editing & Staging Engine (#560, #561, #564, #565)** — Double-click cell to edit in-place with type-aware inline editors, dirty state indicators, staging buffer for staged mutations (inserts/updates/deletions), and keyboard navigation (Tab/Shift+Tab, Enter, Escape).
- **Atomic DML Preview & Multi-Dialect Generation (#562, #566)** — Visual DML confirmation modal displaying compiled atomic `UPDATE`, `INSERT`, and `DELETE` statements with primary key resolution before committing to SQLite, PostgreSQL, and MySQL.
- **In-Cell Validation & Safety Guardrails (#567)** — Real-time cell validation for integer, float, boolean, UUID, JSON, date, and timestamp data types with visual error cues.
- **Advanced Query Filter Engine (#568, #569, #570)** — Compound predicate filter bar with `AND`, `OR`, `NOT`, parentheses, `LIKE`, `ILIKE`, `IN`, `IS NULL`, `BETWEEN`, escaped quotes, and intelligent popup autocomplete suggestions.
- **Syntax Highlighting & Value Inspector (#571, #572)** — Dedicated inspector panel with syntax highlighting for JSON, XML, YAML, and automated XML/HTML formatting and validation.
- **Selection Statistics & Quick Calc (#573)** — Extended selection calculations in the status bar (Count, Distinct, Sum, Avg, Min, Max, Median, Standard Deviation) with one-click clipboard summary export.
- **Multi-Column Grouping & Pivot View (#574, #575, #576)** — Hierarchical multi-level grouping, custom aggregations (SUM, AVG, MIN, MAX, COUNT), sorting, and CSV export for grouped summaries.
- **Column Drag-Resizing & 3-Phase Sorting (#548, #549)** — Interactive column width drag-resizing with divider handles and 3-phase client-side sorting (`natural` -> `asc` -> `desc`).
- **Multi-Cell Range Selection & Clipboard (#550)** — Rectangular multi-cell selection (Shift+Click) with TSV/CSV clipboard copy for Excel/Google Sheets.
- **Fluid Collapsible Sidebar (#557, #559)** — Physics-driven animated sidebar toggle with `QueryaSpring`, global `Cmd+B` / `Ctrl+B` hotkey, titlebar toggle button, and width persistence.
- **Rich Object Context Menus (#551)** — Right-click native context menus for database tables, views, procedures, and connections (*«Select TOP 100»*, *«Copy SELECT statement»*, *«Copy name»*, *«Open in SQL»*).
- **Tree Keyboard Navigation (#552)** — Full arrow-key navigation (Left/Right to expand/collapse, Up/Down, Enter/Space) across database trees.
- **Interactive Welcome Tour & 1-Click Playground (#558)** — Built-in onboarding tour and 1-click SQLite demo database playground.
- **Global Shortcuts & Focus Polish (#579)** — Added global shortcuts (`Ctrl+F` for filter bar, `Ctrl+S` for staging commit, `Ctrl+G` for groupings panel) and enhanced focus accessibility.

### Fixed

- **Connection Dialogs Inline Validation (#553)** — Real-time URI parser and validation with dynamic database driver and host badges.
- **Toolbar Layout Responsive Scroll (#577)** — Wrapped data grid action bars in horizontal scroll to eliminate overflow on compact viewports.
- **macOS SPM Path (#555)** — Corrected relative path to `refresh_rate` plugin source in `Package.swift` for Swift Package Manager builds.
- **macOS App Sandbox Entitlements (#556)** — Added `network.client` and `files.user-selected.read-write` entitlements for outbound TCP connections and local file access.

## [0.4.11-c] - 2026-07-29

Flutter SDK & dependency compatibility update, image downsampling memory optimization, and UI polish.

### Added

- **Dependencies & SDK Constraints** — Updated Flutter/Dart SDK constraints and major library dependencies.

### Performance

- **Image Downsampling (#539)** — Reduced image memory consumption using `cacheWidth` and `cacheHeight` constraints on network and asset images.
- **Isolate Offloading (#538 / #522)** — Offloaded heavy JSON parsing and large SQL result set decoding to background isolates.
- **SQL History & Grid Optimization (#524 / #525)** — Optimized VirtualResultGrid visible column window calculation with binary search and batched SQL history pruning.

### UI & Polish

- **Connection Management (#510 / #520)** — Edit existing connection details from the sidebar context menu and migrated connection forms to QueryaDialogCard.
- **Tree & Sidebar Hierarchy (#472 / #498)** — Unified tree indentation and leaf styling across SQLite, Redis, and Mongo database trees.
- **Motion & Shell Polish (#478 / #488 / #494)** — Fluid motion transitions for workspace tab switches, connection switches, and extension manager.

### Fixed

- **Sandbox Watchdog (#526)** — Prevented false-positive SIGKILL in SandboxWatchdog during heavy RPC execution.
- **Flutter Compatibility** — Maintained backward compatibility for Flutter SDKs.

## [0.4.11-b] - 2026-07-27

Post-0.4.11 patch that **ships** security + Linux distro packaging (intended for 0.4.11-a), plus performance bounds (#414), UI reliability (#445), and code-review correctness (#463).

> Note: GitHub tag `0.4.11-a` was mistakenly placed on the same commit as `0.4.11`, so those binaries did not include the 0.4.11-a changelog. Treat **0.4.11-b** as the first patch after **0.4.11**.

### Added

- **Linux distro packaging (#386)** — `.rpm`, Flatpak (`.flatpak` bundle + manifest), and AUR PKGBUILD; Release CI publishes rpm + Flatpak alongside existing `.deb` / AppImage — see [packaging.md](docs/packaging.md).

### Security

- **Theme remote install localhost (#399)** — `ThemeRemoteInstallService` defaults `allowLocalhostInDebug` to `kDebugMode`.
- **Archive path guard (#401)** — zip extraction uses `p.isWithin()` bounds checks (`archive_path_guard.dart`).
- **Marketplace SHA256 (#396)** — `HttpMarketplaceRepository` requires manifest checksum before install.
- **Marketplace download URLs (#397)** — HTTPS allowlist / SSRF policy (`MarketplaceDownloadPolicy`).
- **Safe zip extraction (#398)** — shared zip-bomb limits via `SafeZipExtractor` (extensions, updater, themes).
- **Remote theme SHA256 (#400)** — remote theme install requires checksum when provided by metadata.
- **Sandbox OS consent (#395)** — fail-closed unsandboxed driver launch without OS wrapper (bubblewrap / consent dialog).
- **Sideload integrity UX (#402)** — local `.zip`/`.qext` install dialog with security notice and optional SHA256.

### Performance

- **SQL result caps (#415 / #416)** — SQLite injects `LIMIT` before materializing rows; Postgres clamps oversized `LIMIT` / `FETCH`.
- **Streaming I/O (#417 / #418)** — export writes stream to disk; marketplace SHA256 + zip extract avoid dual full-buffer copies.
- **RPC / SDUI bounds (#419 / #420)** — NDJSON line size caps; virtualized `SduiTreeBuilder`.
- **Hot-path yielding (#421 / #422)** — result cell string conversion and MySQL table browse yield to the UI isolate.
- **Editor / Redis / sandbox / storage (#424–#428)** — syntax-highlight threshold, Redis TYPE/TTL pipeline, bounded stderr, SQL history index/prune, incremental theme mtime scan.
- **VirtualResultGrid (#423)** — 2D column virtualization for wide result sets.

### Fixed

- **UI reliability (#445 / #446–#457)** — Escape on `showAppDialog`; DDL overlay always pops; stats/table loading clears on early exit; tree error + Retry; empty table state; scrollable toolbars; SQL open/save toasts; title-bar scale; Redis/Mongo empty banners; mounted guards; ResultsTab invariants.
- **Correctness follow-ups (#463 / #464–#468)** — `injectSqlLimit` skips string/dollar quotes; delete partial export files on failure; PG tree clears stale children on error; theme watcher queues in-flight refresh; Redis keys error banner clears on success.

## [0.4.11-a] - 2026-07-27

Prepared changelog for security (#395–#402) + Linux rpm/Flatpak/AUR (#386). **Tag/binaries were mistargeted** (same commit as `0.4.11`); content ships in **0.4.11-b**.

## [0.4.11] - 2026-07-27

Universal UI standard for drivers/extensions, shell UX hardening, Fluid QueryaMotion morphing, virtual grid/pool reliability, performance follow-ups, and dual-channel packaging (portable + installable).

### Added

- **SDUI / extension RPC expand (#323)** — `getCapabilities`, `getServerStats`, `getObjectMetadata`, and `cancelQuery` on the plugin bridge for richer driver UIs.
- **ExtensionTableView (#324)** — table toolbar, custom SQL filter, and async row-count for sandboxed drivers.
- **Universal data export (#326)** — CSV, JSON, Markdown, and SQL dump from ResultsTab / table toolbars.
- **MySQL / SQLite UI parity (#325)** — align workspace chrome and flows with the Obsidian UI standard.
- **Shell UX (#339)** — semantic palette, shared toast, keyboard-operable tab strip, empty-workspace hero + recent connections, resizable connections sidebar, shared dialogs/widgets.
- **Fluid QueryaMotion (#342)** — spring primitives, workspace empty↔connected morph, sliding tab indicator, hero/recent stagger, ResultsTab mode morph, dialog/dropdown fade-slide, theme morph gated by motion level, split drag-end settle + motion guardrails.
- **Perf follow-ups (#356 / #357–#366)** — isolate tab-strip rebuilds; SwitchingBody/CrossFade `RepaintBoundary` + `TickerMode`; static dialog blur; vertical-split paint isolation; ticker-gated stats polling; badge pulse lifecycle; ResultsTab morph paint scope; document theme morph cost, stagger/badge duration constants, and Linux query-only refresh_rate.
- **Portable + installable packaging (#379–#385)** — portable zip channel documented on Releases; Linux AppImage and `.deb`; Windows Inno Setup (`*-windows-setup.exe`); `QUERYA_PORTABLE` / `QueryaData/` portable profile root; one-shot migration from legacy `com.example.*` support paths; updater prefers release asset matching install context (zip vs AppImage vs setup).

### Fixed

- **Virtual result grid (#331)** — synchronize column width recalculation in `VirtualResultGrid`.
- **Connection pools (#332)** — eviction and exception wrapping in SQLite and MySQL pools.
- **Query timeout (#333)** — force-close connection on `TimeoutException`.
- **Large result mapping (#334)** — optimize SQL result set mapping and DDL rendering; RPC parse on compute isolate where applicable.
- **Sidebar width persist (#354)** — keyboard/semantics resize + dispose flush; dropdown exit delay for fade-slide.
- **Linux build (#394)** — silence Clang `-Wdeprecated-literal-operator` from `flutter_secure_storage_linux` 9.x.
- **Tests** — skip legacy profile migration during `flutter test` runs (isolated temp dirs).

### Changed

- **Bundle / application IDs (#385)** — `com.queryahub.querya_desktop` (Linux), `com.queryahub.queryaDesktop` (macOS), `QueryaHub` / `Querya Desktop` (Windows).
- **Dialog sizing (#394)** — larger connection forms, database picker, and Preferences dialog via `WindowLayout` constants.
- **CI / release hygiene** — merge `main` into `dev` (#346); Release workflow publishes portable zips plus installable AppImage, `.deb`, and Windows setup; `SHA256SUMS.txt` covers all artifacts — see [packaging.md](docs/packaging.md) and [tags-and-releases.md](docs/tags-and-releases.md).

## [0.4.10] - 2026-07-11

Sandboxed extension runtime, SDUI, and first end-to-end external database drivers (Registration + Activation), plus in-app updates and connection reliability fixes.

### Added

- **Extension sandbox runtime (Block E, #300–#305)** — parse `sandbox` capabilities from manifests; launch plugins via `SandboxProcessRunner` (bwrap / sandbox-exec / Windows soft-start); Zero-Trust `system.injectCredentials` over Stdio; watchdog + auto-recovery; stderr sanitization, rotating logs, and security audit; Level-1 embedded runtime stubs and lifted preview gate for policy-compliant `process` drivers.
- **Plugin RPC bridge (Block C, #312)** — `PluginRpcBridge` over NDJSON JSON-RPC (`system.handshake` / `ping` / `shutdown`, `db.connect`).
- **SDUI builders (#314)** — `SduiFormBuilder` and `SduiTreeBuilder` render connection forms and schema trees from extension JSON schemas (`key` / `boolean` aliases supported).
- **Local extension install (#316)** — install `.zip` / `.qext` packages from Preferences and Extension Manager with the same SandboxPolicy checks as the Marketplace.
- **Driver Registration + Activation (#318 / #319)** — parse `contributions.drivers` / `capabilities`; list installed drivers in New Connection and Driver Manager; SDUI connection form; `ExtensionDriverSession` for connect + schema tree; SQL workspace / table view for sandboxed drivers; Docker ClickHouse service for local testing.
- **In-app updates (#280–#282)** — updater service, Check for Updates UI / badge / startup settings, and platform installer helpers.
- **SSL certificate pickers for MySQL, MongoDB, and Redis (#278)** — optional client certificate paths on those connection forms.
- **SQLite in Driver Manager (#270)** — built-in SQLite listed alongside other Dart drivers.

### Fixed

- **Secrets / shutdown / reliability** — atomic LocalDb + secure-store updates (#276); disconnect SQLite on app shutdown (#271); log remaining silent catches in database drivers (#272); harden MySQL custom SELECT validation (#274); stream large CSV exports on an isolate (#277).
- **UI / menus** — disabled Run (F5) when no SQL-capable connection (#266); coming-soon placeholders for unfinished workspace tabs (#267); global File → New/Open/Save SQL for active SQL editors (#268).
- **Marketplace** — database drivers without a valid process sandbox stay preview-only listings (#269).
- **Sandbox launch** — mark driver binaries executable after zip install; fall back when bubblewrap user namespaces are unavailable.

## [0.4.9] - 2026-07-10

PostgreSQL connection reliability and TLS improvements, plus menu and URI import polish.

### Added

- **Connection → New Connection from URL (#228)** — create a connection by pasting a database URI for PostgreSQL, MySQL, MongoDB, Redis, or SQLite. The URL is parsed, validated, and saved to `LocalDb`.
- **Help → About & Documentation (#229)** — added an About dialog showing the app version, MIT license, and repository link; the Documentation menu item opens the project docs in the browser.
- **PostgreSQL SSL certificate file pickers (#260)** — added optional file pickers for `sslrootcert`, `sslcert`, and `sslkey` in the PostgreSQL connection form. Paths are merged into the connection URI or used to generate a URI when in host/port mode.

### Fixed

- **PostgreSQL URL parser / SSL (#249, #253, #254, #257, #258)** — validate `sslmode` (reject `prefer` and unknown values), correctly map `useSSL` for `disable`/`require`/`verify-ca`/`verify-full`, use driver default ports when omitted, and preserve display host/port for URI-only connections.
- **PostgreSQL connection error reporting (#250, #251, #252)** — `testConnection` now returns the underlying error message, the form shows the real failure reason, and the connection tree displays the full exception text instead of a generic "Error" label.
- **PostgreSQL connection error typing (#256, #259)** — `connect()` throws `PostgresConnectionException` with the original cause and stack trace; the pool wraps unexpected factory errors in the same typed exception.

## [0.4.8] - 2026-07-08

### Fixed

- **SQLite / RETURNING clause support (#243)** — support RETURNING clauses for INSERT, UPDATE, and DELETE DML queries in the SQLite database driver, returning the resulting rows to the client.
- **Security / MySQL Injection Fix (#241)** — replaced manual escaping and string concatenation in schema introspection methods (`listViews`, `listColumnNames`, `listTables`) in the MySQL database driver with parameterized queries using parameter binding.

## [0.4.7-a] - 2026-06-22

### Added

- **Connection Invalidate/Reconnect** — added Invalidate/Reconnect action in the application menu and window title bar.
- **Connection Read-only Mode** — added Read-only mode for PostgreSQL and SQLite database connections to prevent write operations (displays a lock icon in the workspace).
- **Connection Lifecycle Management** — added Connect and Disconnect menu items and corresponding title bar controls.

### Documentation

- Added comprehensive setup guides for SQLite, Read-only connection mode, and connection lifecycle controls in the English user guide and Obsidian Russian notes.

## [0.4.7] - 2026-06-21

Local extension discovery and manifest foundation release. Git tag **`0.4.7`**.

### Added

- **Extension models (EXT-1)** — data models `ExtensionManifest` and `ExtensionType` to parse `manifest.json`.
- **Local scanner (EXT-2)** — `LocalExtensionRegistry` scans `~/.querya/extensions/` to find and load extension manifests.
- **Theme migration (EXT-3)** — migrated legacy custom themes to the new unified extension package format.
- **Unit tests (EXT-4)** — unit tests for manifest parsing, directory scanning, and registry cache logic.

### Fixed

- **Theme importing security** — resolved concurrent import TOCTOU filesystem races and theme ID collisions during migration, and cleaned up deprecated legacy import code.
- **Appearance Settings test** — resolved the preferences appearance section widget test failure by mocking the extensions directory.

## [0.4.6-a] - 2026-06-18

### Changed

- **UI / Sidebar** — implemented collapsible dropdown tree nodes for tables and views in SQLite and MySQL connections.

## [0.4.6] - 2026-06-18

SQLite database connector release. Git tag **`0.4.6`**.

### Added

- **SQLite connection driver (SQL-S1)** — support local SQLite database files opening, closing, and queries via FFI.
- **Catalog schema resolver (SQL-S2)** — automatic tables, views, indexes, and column schema detection.
- **Connection dialog (SQL-S3)** — SQLite connection form with native file-picking (`file_selector`) and read-only toggle.
- **Connections sidebar (SQL-S4)** — integrated SQLite nodes with expand/collapse hierarchy under Connections.
- **SQL Workspace editor & Paginated table (SQL-S5)** — SQLite query workspace supporting history lookups, statement executions, and paginated data grid browser.
- **Docker test database** — added `sqlite-seed` container to `docker-compose.yml` to automatically generate a local `querya.db` file with mock data alongside other test databases.

### Fixed

- **UI / Accessibility** — fixed text clipping in workspace toolbars and settings when increasing the interface scale (e.g., 150%). Replaced hardcoded heights with `minHeight` constraints and dynamically scaled label widths.
- **UI / Stability** — resolved `A RenderAnimatedSize was mutated in its own performLayout implementation` crash during split pane dragging by removing redundant `LayoutBuilder` wrappers.
- **Linting** — resolved `flutter analyze` warnings for deprecated Shadcn legacy colors and flow control structures.

## [0.4.4] - 2026-06-16

UI motion polish, high refresh rate, performance fixes, and security improvements release. Git tag **`0.4.4`**.

### Added

- **Motion tokens core (UI-A1)** — `QueryaMotion` core durations and curves, providing a single source of truth for all animations.
- **Token adoption (UI-A2)** — replace magic/scattered duration and curve literals with standardized tokens.
- **Smoother transitions (UI-A3)** — menu/dropdown enter fade+scale, dialog blur/scale retune, tree height animation (`QueryaAnimatedExpand`), and workspace tab content cross-fade (`QueryaCrossFadeStack`).
- **High refresh rate (UI-A4)** — unlock native ProMotion on macOS 14+, active Hz logging at startup, and FPS/Hz debug overlay.
- **Reduced motion setting (UI-A5)** — Preferences toggle (`Full` / `Reduced` / `Off`) and automatic OS reduced-motion configuration matching.
- **Docs & performance checks (UI-A6)** — per-OS measured refresh-rate verification table, DevTools performance checklists, and release QA items.
- **SQLite Database Support Plan (0.4.5)** — design and implementation roadmap for local SQLite file connector support.

### Fixed

- **Memory: SQL Result Capping (Issue #184)** — PostgreSQL and MySQL query execution now limits client memory usage by applying query LIMITs database-side and streaming rows using `rowsStream` (breaking early).
- **Performance: MongoDB Client-side Pagination (Issue #185)** — uses `SelectorBuilder` skip/limit operators on the server instead of client-side stream buffering.
- **Performance: N+1 secure storage lookups (Issue #186)** — parallelizes connection secrets hydration on startup.
- **Performance: Redis Key Scanning round-trips (Issue #187)** — runs type and TTL lookups concurrently for key batches.
- **Security: Theme Remote Installation SSRF (Issue #183)** — parses and filters IPv6 and private/loopback/multicast/mapped hosts using `InternetAddress.tryParse`.
- **UX: Focus leak on QueryaCrossFadeStack** — wraps inactive children in `ExcludeFocus` and `ExcludeSemantics` to prevent tab-indexing into off-screen tabs.

## [0.4.3] - 2026-06-15

Theme follow-ups release (TP-F1–TP-F4, GitHub issues **#159–#163**). Git tag **`0.4.3`**.

### Added

- **Theme folder watcher (TP-F1)** — debounced `Directory.watch` on `{appSupport}/themes/` auto-refreshes the registry when files are added, removed, or renamed.
- **Marketplace metadata (TP-F2)** — optional manifest fields (`homepage`, `license`, `preview`, `tags`); theme picker shows author/tags; `ExtensionManifest` stub in `lib/core/market/` for future Explore UI.
- **Visual theme editor (TP-F3)** — Preferences section to tweak workbench colors with live preview and export `querya.theme.v1` JSON.
- **Remote theme install (TP-F4)** — **Install from URL…** (HTTPS-only, public hosts, optional SHA-256); `ThemeRemoteInstallService` with checksum verify before import.
- **Docs / QA** — remote install section in [theme-import.md](docs/theme-import.md); 0.4.3 items in [release-checklist.md](docs/release-checklist.md).
- **Tests** — file watcher, remote install policy/service, theme editor and metadata coverage.

## [0.4.2] - 2026-06-14

Custom theme registry release (parser epic TP-01–TP-30, GitHub issues **#96–#125**). Git tag **`0.4.2`**.

### Added

- **Custom theme registry** — scan `{appSupport}/themes/` for `querya.theme.v1` and VS Code JSON/JSONC; **Theme** picker with search, hover preview, **Refresh themes**, and **Open themes folder** (Preferences → Appearance).
- **Built-in bundled themes** — **Querya Cyberpunk Neon** from `assets/themes/` (no manual install).
- **Theme import** — **Import theme…** copies into the user themes directory with content-hash and id deduplication; selection persists across restarts.
- **Startup safety** — missing or broken selected theme falls back to Querya Dark with a Preferences error; saved theme id is kept until the user picks another theme.
- **Window chrome** — title bar and window controls follow active `QueryaThemeScope` workbench tokens.
- **Docs / QA** — [theme-custom-json.md](docs/theme-custom-json.md), updated [theme-import.md](docs/theme-import.md), custom-theme section in [release-checklist.md](docs/release-checklist.md).
- **Tests** — registry/parser/controller coverage, 60-theme picker performance guard, end-to-end import flow (`theme_import_flow_test.dart`).

## [0.4.1] - 2026-06-13

Performance and UX release ([#93](https://github.com/QueryaHub/Querya-Desktop/issues/93)). Git tag **`0.4.1`**.

### Added

- **MySQL server stats** — full dashboard (connections, queries, network, databases table) via `SHOW GLOBAL STATUS` / `information_schema`.
- **Virtual SQL result grid** — `VirtualResultGrid` with fixed column widths, cell copy, and `RepaintBoundary` instead of a materialized `Table`.
- **Lazy connection tree** — `lazyConnectionTreeList` / `ListView.builder` for large PostgreSQL and MySQL object lists; `ValueKey` on leaf rows.
- **Vertical split pane** — `ValueNotifier`-driven splitter drag without rebuilding entire workspace panels.
- **Docker dev stack** — `docker/` compose with PostgreSQL, MySQL, MongoDB, Redis and seed data for local testing.
- **`deep_collection_equals`** — shared snapshot diff helper for stats polling.

### Changed

- **UI scale preview** — decoupled from app-wide theme rebuilds; scale commits only on slider release.
- **Syntax highlighting** — debounced updates, worker isolate for all buffer sizes, highlighter pair cache by theme key.
- **Stats dashboards** — Redis, MongoDB, and PostgreSQL skip `setState` when polled data is unchanged; Redis/Mongo layouts redesigned; MySQL replaces version-only stub.
- **Connection forms** — `FormValidityNotifier` narrows rebuild scope to action buttons.
- **SQL workspace settings** — `SqlWorkspaceSettingsRevision` so theme/scale changes do not reload SQL tabs.
- **Connections panel** — rebuilds only when selected connection id changes.
- **MySQL results** — row string conversion moved to a worker isolate (`mysql_result_utils`).
- **Redis key editor** — virtualized hash/list/set/zset member lists.
- **Mongo documents** — lazy pretty-JSON cache; document cards without hover `setState`.
- **Explorer list rows** — Redis/Mongo database/key/collection rows use `InkWell` hover instead of hover `setState`.
- **QueryaDropdown** — caches menu children; ellipsizes trigger label in fixed-width layouts.

### Fixed

- **Connection menu** — new connection form opens after picking type from the menu ([#93](https://github.com/QueryaHub/Querya-Desktop/issues/93) follow-up).
- **Stats UI overflow** — Redis, MongoDB, and PostgreSQL stats cards no longer overflow in debug/profile layouts.
- **Redis TTL dialog** — disposes `TextEditingController` on close.

## [0.4.0] - 2026-05-28

Theme system milestone (epic #37). Git tag **`0.4.0`** — use this release for binaries; earlier tag `0.3.0` was a pre-PR snapshot.

### Added

- **Theme system** — runtime dark/light/system modes, **Querya Light** preset, optional **Animate theme changes** in Preferences.
- **VS Code themes** — import `.json` / `.jsonc` (`colors` + `tokenColors`); user color overrides; persisted imported theme.
- **Syntax highlighting** — SQL and JSON in `QueryaCodeEditor` via `syntax_highlight`; `tokenColors` mapped to TextMate scopes; isolate highlight for large buffers.
- **Editor** — `QueryaCodeEditor` abstraction, `SqlEditorChrome` from theme tokens, `QueryaThemeScope` for workbench/editor tokens.
- **Samples** — `themes/samples/cyberpunk-neon.json` (+ JSONC) for manual import testing.
- **Docs** — [docs/theme.md](docs/theme.md), [docs/theme-import.md](docs/theme-import.md), [docs/archive/editor-spike-report.md](docs/archive/editor-spike-report.md), [docs/archive/code-forge-evaluation.md](docs/archive/code-forge-evaluation.md).

### Changed

- **Workbench UI** — P0 surfaces (sidebar, SQL chrome, empty hero, main shell) use design tokens instead of hardcoded `QueryaColors`.
- **Preferences** — Appearance section (theme mode, preset, import, animation); Material `DropdownMenu` for stable menus in scrollable dialogs.
- **Imported themes** — `mutedForeground` clamped for readable helper text when VS Code sidebar colors are low-contrast.

### Fixed

- **Preferences (dark / imported themes)** — readable labels and dropdown text via `materialTheme` + `popoverForeground` hints.
- **Preferences dropdown** — Color preset menu no longer stretches full screen (`expandedInsets` instead of `width: infinity`).
- **Dialogs / SQL editor** — `QueryaThemeScope` on `ShadcnApp.builder` so overlays (Preferences, SQL editor) resolve theme tokens.

## [0.2.0] - 2026-04-24

### Added

- **SQL result export** — from the PostgreSQL / MySQL **Data Output** grid: **Copy as CSV**, **Save as CSV…**, **Copy as JSON**, **Save as JSON…** (native save dialog via **`file_selector`** on Linux, macOS, and Windows).
- **SQL query history** — successful statements are stored in local **SQLite** (per saved connection and database bucket); **History** in the SQL toolbar opens a recall dialog; **Edit → Preferences** adds **Query history limit** (25–500 entries, oldest trimmed automatically).
- **PostgreSQL** — `postgres_object_workspace.dart` builds object views from the sidebar tree (logic moved out of `workspace_panel` for clarity).
- **Documentation** — contributing notes, product **roadmap**, macOS signing track; README structure refresh.
- **Tests** — MySQL SQL workspace home, driver manager, and preferences dialog widget coverage; storage tests for query history and export encoding.

### Changed

- **Connections sidebar** — `connections_panel` split into **part libraries** for easier maintenance (behavior preserved).
- **CI / release** — Flutter toolchain pinned to **3.41.6** for analyze, tests, and release builds.
- **PostgreSQL — workspace** — a selected table, view, or other object opens **full width**; **Server** / **SQL** tabs show only when no object is selected for that connection. **Open in SQL** still seeds the editor from the current browse context; the SQL toolbar **DB:** line follows the tree catalog when a seed is applied.
- **PostgreSQL** — shared browse query helper (`postgresBrowseSelectSql`) and default page size (`kPostgresBrowseDefaultRowLimit`) align the data grid with the SQL editor template.
- **MySQL** — comparing the table browse query to the mini-editor SQL ignores trailing semicolons and normalizes whitespace; hint text clarifies that **Run** reloads from the server even when rows look unchanged.

### Fixed

- **PostgreSQL — Open in SQL** — the context menu seeds the editor from the **row you right-clicked** (database, schema, table/view/matview name). Previously the app used only the last **left-click** selection, so the query could target the wrong table.

## [0.1.3] - 2026-04-25

### Added

- **Performance** — narrower workspace rebuilds via `ValueNotifier` / `ValueListenableBuilder` on the main screen; `RepaintBoundary` around connections and workspace; folder expansion uses local state so the whole sidebar does not rebuild on every toggle.
- **Lists** — virtualized long lists for MongoDB documents/collections, Redis keys, and PostgreSQL browser views (indexes, triggers, types, extensions, foreign data).
- **Tests** — `MainScreenWorkspaceState`, `showAppDialog`, `RedisKeysView` (with `RedisConnectionTestFake`), and expanded connections panel folder collapse/expand coverage.
- **Docs** — `docs/perf-baseline.md` (Flutter DevTools checklist for regression comparison).

### Changed

- **Dialogs** — slightly shorter transition and lower blur sigma in `showAppDialog` to reduce GPU load on modest hardware.
- **Connections tree** — slightly shorter chevron rotation animation.

### Fixed

- **PostgreSQL server dashboard** — removed fixed-height cards and chip layout that caused vertical overflow (yellow/black debug stripes) on the stats view.

## [0.1.2] - 2026-04-24

### Changed

- **Releases** — tag push no longer fails when git tag and `pubspec` semver differ after auto version-bump on `main` (warning only; artifact names follow `pubspec`).

## [0.1.1] - 2026-04-24

### Changed

- **Releases** — pushing a version **git tag** matching `pubspec` (e.g. `0.1.1` after `version: 0.1.1+1`) runs the **Release** workflow: Windows/Linux zips, `SHA256SUMS.txt`, and a GitHub Release (no `v` prefix in tag or artifact names). Manual **Actions → Release** still works.

## [0.1.0] - 2026-04-24

### Added

- **Preferences** — **Edit → Preferences** dialog: global SQL statement timeout (shared dropdown), max result rows presets, editor font size, and `AppSettingsRevision` so open SQL workspaces refresh when settings change.
- **Security** — connection passwords and sensitive connection material stored via **`flutter_secure_storage`** (OS keychain/credential store); local SQLite schema migration for non-secret fields only (see `docs/security.md`).
- **MIT LICENSE** at repository root.
- **Documentation** — `docs/security.md`, `docs/user-guide.md`, `docs/release-checklist.md`; release/tag process updates in `docs/tags-and-releases.md`.
- **Linux** — `run_linux.sh` checks for `libsecret` via `pkg-config` before `flutter run`.
- **UI** — empty-workspace hints (menu path to new connection and docs); **Connection → New Database Connection** wired in the menu.
- **Tests** — coverage for `AppSettingsRevision`, `SqlStatementTimeoutDropdown`, and `QueryEditorTab` font size behavior.

### Changed

- **Connections / drivers** — removed JDBC driver download UI and related storage/URL helpers; MySQL/Postgres use Dart clients only.
- **CI / release** — Linux runners install **`libsecret-1-dev`**; release workflow aligned with version tags from `pubspec`.
- **Linux build** — CMake install prefix forced so the Flutter bundle installs under **`build/`** instead of system paths such as `/usr/local`.

### Fixed

- Linux desktop build/install layout no longer targets `/usr/local` when building the app bundle.

[0.2.0]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.3...0.2.0
[0.1.3]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.2...0.1.3
[0.1.2]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/QueryaHub/Querya-Desktop/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/QueryaHub/Querya-Desktop/compare/0.0.1...0.1.0
