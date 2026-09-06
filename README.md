<div align="center">

# Querya Desktop
### The Modern, High-Performance Database Studio for Engineers & Teams

**Fast, lightweight, and secure database management environment for PostgreSQL, MySQL, MariaDB, SQLite, Redis, and MongoDB.**

[![CI Status](https://github.com/QueryaHub/Querya-Desktop/actions/workflows/ci.yml/badge.svg)](https://github.com/QueryaHub/Querya-Desktop/actions/workflows/ci.yml)
[![Release Status](https://github.com/QueryaHub/Querya-Desktop/actions/workflows/release.yml/badge.svg)](https://github.com/QueryaHub/Querya-Desktop/actions/workflows/release.yml)
[![Latest Release](https://img.shields.io/github/v/release/QueryaHub/Querya-Desktop?color=brightgreen&label=release)](https://github.com/QueryaHub/Querya-Desktop/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Open Source](https://img.shields.io/badge/Open%20Source-100%25-brightgreen.svg)](LICENSE)
[![Flutter Desktop](https://img.shields.io/badge/Built%20with-Flutter%203-02569B?logo=flutter)](https://flutter.dev)
[![Platforms](https://img.shields.io/badge/Platforms-Linux%20%7C%20Windows%20%7C%20macOS-informational?logo=linux&logoColor=white)](#installation)
[![Security: Hardware Encrypted](https://img.shields.io/badge/Security-OS%20Vault%20Encrypted-success)](#security--privacy)
[![Zero Telemetry](https://img.shields.io/badge/Telemetry-Zero%20%28100%25%20Private%29-blueviolet)](#security--privacy)

<p align="center">
  <a href="#overview">Overview</a> •
  <a href="#key-capabilities">Key Capabilities</a> •
  <a href="#supported-engines">Supported Engines</a> •
  <a href="#feature-matrix">Feature Matrix</a> •
  <a href="#installation">Installation</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#security--privacy">Security & Privacy</a> •
  <a href="#documentation">Docs</a>
</p>

</div>

---

## Overview

**Querya Desktop** is a modern, open-source database management studio engineered from the ground up for speed, safety, and developer ergonomics. Built on Flutter and Dart, Querya provides a native, hardware-accelerated desktop experience across **Linux**, **Windows**, and **macOS** with zero JVM overhead and zero external telemetry.

Whether you are navigating multi-million row datasets, authoring complex analytical SQL, inspecting nested NoSQL documents, or managing distributed key-value caches, Querya provides a unified, cohesive, and distraction-free interface.

---

## Key Capabilities

### ⚡ Ultra-Fast 2D Virtualized Data Grid
- **$O(1)$ Viewport Rendering:** Handle large datasets smoothly at 60/120+ Hz with a strictly bounded memory footprint. Only visible cells are rendered to the screen.
- **Adaptive Content-Aware Column Sizing:** Automatically calculates optimal column widths based on sample data rows and header lengths.
- **Header Double-Click Auto-Fit:** Double-click column dividers or trigger auto-fit to resize columns instantly to fit their contents.
- **Background Isolate Sorting & Filtering:** Multi-type column sorting with Schwartzian transforms executed in dedicated background worker isolates, keeping the UI silky smooth.
- **Streaming Exporter:** Stream table data directly to **CSV**, **JSON**, or executable **SQL INSERT** statements.

### ✍️ Interactive In-Place DML Staging Buffer
- **Safe Transactional Editing:** Edit cells directly within the grid with real-time data type validation (integers, floats, booleans, timestamps, UUIDs, and JSON).
- **Atomic DML Generation:** Querya tracks modifications (`UPDATE`, `INSERT`, `DELETE`) in a dedicated staging buffer, generating dialect-accurate SQL statements.
- **Review Before Execution:** Inspect generated SQL diffs with primary-key safety checks, row counts, and single-click commit or rollback.

### 🗂️ Multi-Tab SQL Studio & Independent Sessions
- **Isolated Query Sessions:** Open multiple SQL workspace tabs simultaneously, each maintaining its own query buffers, transactions, and execution state.
- **Cancellable Async Execution:** Run heavy analytical queries without freezing the client, with responsive cancellation and live execution timers.
- **Universal Multi-Dialect Syntax Highlighting:** Real-time token highlighting for keywords, operators, strings, comments, and identifiers across all SQL dialects.
- **Searchable Query History:** Quickly recall, re-run, or inspect past executions with execution durations and status codes.

### 🔍 Deep Schema Explorer & Quick-Search
- **Debounced Instant Object Filter:** Rapidly filter schemas, tables, views, columns, indexes, and stored procedures.
- **Favorites & Pinning (⭐):** Pin mission-critical tables and collections to the top of your connection tree for instant access.
- **Live Connection Telemetry:** View server version, active connections, uptime, memory consumption, and engine statistics.

### 🔬 Rich Cell & Payload Inspector
- **Structured Pretty-Printers:** Inspect complex cell values in dedicated preview panes with automatic formatting and syntax validation for **JSON**, **XML**, and **HTML**.
- **Raw Hex / Binary Viewer:** Inspect BLOBs, binary hashes, and raw payloads with side-by-side hex and ASCII representations.

### 🔒 Security & Privacy by Design
- **Hardware-Backed Credential Vaults:** Connection passwords and keys are never stored in plaintext. Querya integrates directly with native OS credential stores (**Freedesktop Secret Service / Keyring** on Linux, **Apple Keychain** on macOS, and **Windows DPAPI Credential Manager**).
- **In-Memory Secret Scrubbing:** Sensitive credentials are cleansed from memory after connection handshakes.
- **Air-Gapped & Zero Telemetry:** Absolutely zero telemetry, zero analytics, and zero external calls. Your database credentials and queries never leave your local machine.

### 🔌 Native & Pluggable Driver Architecture
- **Pure Native Drivers:** High-performance built-in drivers for PostgreSQL, MySQL/MariaDB, SQLite, Redis, and MongoDB with no external runtime dependencies or JDBC configurations.
- **JSON-RPC 2.0 Driver Sandbox:** Extend Querya with custom community or proprietary database drivers via sandboxed standard I/O RPC bridges.

### 🎨 Desktop Ergonomics & Custom Themes
- **OS File Associations:** Native file handler integration with `.sql`, `.db`, `.sqlite`, and `.sqlite3` files. Double-click any database or SQL script in your file manager to open it immediately.
- **Comprehensive Keymap:** Complete keyboard navigation for executing queries, switching tabs, focusing panels, and searching objects.
- **VS Code Theme Importer:** Import any `.json` VS Code theme or choose from bundled dark/light palettes.

---

## Supported Engines

| Database Engine | Versions Tested | Connection Types | Security / TLS | Status |
|:---|:---|:---|:---|:---:|
| **PostgreSQL** | 12, 13, 14, 15, 16, 17+ | Direct TCP / Unix Socket | SSL / TLS (Verify-Full, CA Certs) | `Production` |
| **MySQL / MariaDB** | MySQL 5.7, 8.0+, MariaDB 10.x+ | Direct TCP / Socket | SSL / TLS, Custom Ciphers | `Production` |
| **SQLite** | SQLite 3.x | Local File / In-Memory | File Permissions / Encryption | `Production` |
| **Redis** | 6.x, 7.x+ | Standalone / Auth | TLS / Sentinel | `Production` |
| **MongoDB** | 5.0, 6.0, 7.0+ | Standalone / Replica Set | TLS / X.509 / SCRAM-SHA-256 | `Production` |
| **Custom Plugins** | Any | JSON-RPC 2.0 stdio Bridge | Host-Managed Sandbox | `Extensible` |

---

## Feature Matrix

| Feature Area | Querya Desktop | Legacy Desktop Clients | Web-Based Portals |
|:---|:---:|:---:|:---:|
| **Runtime Overhead** | **Zero JVM (Native Flutter / Dart)** | Heavy (~1–2 GB JVM/Electron) | Browser Tab Memory Limits |
| **Data Grid Architecture** | **2D Virtualized ($O(1)$ Memory)** | Paginated or Unbounded Heap | DOM Virtualization Limits |
| **In-Place Cell Editing** | **Yes (DML Staging & Preview)** | Often Direct or Unchecked | Read-Only or Manual Forms |
| **Multi-Tab SQL Sessions** | **Yes (Isolated Sessions)** | Varies | Limited by Tab Lifecycles |
| **Local SQLite File Association** | **Native (.db, .sqlite, .sqlite3)** | Partial | Requires Server Upload |
| **Complex Cell Inspector** | **JSON / XML / HTML / Hex-Binary** | Basic String View | Basic Textarea |
| **Credential Storage** | **Hardware OS Vault (Keyring/Keychain/DPAPI)** | Insecure Plaintext XML/JSON | Stored on Remote Server |
| **Telemetry & Privacy** | **Zero Tracking (100% Offline Capable)** | Opt-out Phone Home | Full Cloud Telemetry |
| **Startup Time** | **< 1.0s Instant Cold Start** | 10–30s JVM Warmup | Network Dependent |

---

## Installation

### Linux
Download the latest `.deb`, `.AppImage`, or `.tar.gz` from [Releases](https://github.com/QueryaHub/Querya-Desktop/releases):

```bash
# Debian / Ubuntu (.deb)
sudo dpkg -i querya-desktop-linux-amd64.deb
sudo apt-get install -f

# AppImage (Standalone executable)
chmod +x querya-desktop-*.AppImage
./querya-desktop-*.AppImage
```

> **Note:** Linux builds utilize `libsecret-1` for OS-level credential protection. Ensure `libsecret-1-0` is installed on your system.

### Windows
Download the Windows installer (`.exe`) or portable archive (`.zip`) from [Releases](https://github.com/QueryaHub/Querya-Desktop/releases). Run the setup to automatically register `.sql` and `.sqlite` file associations.

### macOS
Download the universal `.dmg` from [Releases](https://github.com/QueryaHub/Querya-Desktop/releases), mount the disk image, and drag **Querya** into your `Applications` folder.

---

## Building from Source

### Prerequisites
- **[Flutter SDK](https://flutter.dev/docs/get-started/install)** (Version 3.24+ / Dart 3.5+)
- C/C++ compiler toolchain (GCC / Clang on Linux, MSVC on Windows, Xcode on macOS)
- Linux development libraries (Debian/Ubuntu):
  ```bash
  sudo apt-get update
  sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev
  ```

### Build Steps

```bash
# 1. Clone repository
git clone https://github.com/QueryaHub/Querya-Desktop.git
cd Querya-Desktop

# 2. Fetch dependencies
flutter pub get

# 3. Run in development mode
flutter run -d linux       # or: windows / macos

# 4. Build release bundle
flutter build linux --release
# Output: build/linux/x64/release/bundle/
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Querya Desktop Shell                          │
│          (bitsdojo_window, Multi-Tab Workspaces, Command Router)        │
├───────────────────────────────────┬─────────────────────────────────────┤
│        UI & Presentation          │           State & Sessions          │
│ • 2D Virtual Data Grid            │ • Connection Session Pool           │
│ • Interactive In-Place Editor     │ • Isolated Query Workspaces         │
│ • Rich Cell Inspector (JSON/Hex)  │ • DML Staging Buffer & Safety Guard │
│ • Schema Tree & Quick Search      │ • Query Execution & Audit History   │
├───────────────────────────────────┴─────────────────────────────────────┤
│                          Core & Engine Adapters                         │
│ • PostgreSQL (TLS/Pooling)        │ • SQLite FFI (File & Memory)        │
│ • MySQL / MariaDB (Native Wire)   │ • MongoDB BSON Engine               │
│ • Redis (RESP Client)             │ • Extensible JSON-RPC 2.0 Driver    │
├─────────────────────────────────────────────────────────────────────────┤
│                     Platform Abstraction & Security                     │
│ • OS Hardware Vault (Secret Service / Apple Keychain / Windows DPAPI)   │
│ • Desktop File Handlers (.sql, .db, .sqlite, .sqlite3)                  │
│ • Windowing & High-DPI Scaler Engine                                    │
└─────────────────────────────────────────────────────────────────────────┘
```

For detailed component documentation and sequence diagrams, refer to **[Architecture Guide](docs/architecture.md)**.

---

## Security & Privacy
 
Querya is engineered with complete open-source transparency, strict privacy, and air-gapped security by design:

1. **Native OS Credential Stores:** Credentials are never written to disk in plain text or reversible base64. They are delegated to:
   - **Linux:** Freedesktop Secret Service API (`libsecret` / GNOME Keyring / KWallet).
   - **macOS:** Apple Keychain Services.
   - **Windows:** Windows Data Protection API (DPAPI) and Windows Credential Manager.
2. **In-Memory Hygiene:** Sensitive strings are dereferenced and purged from memory immediately following authentication handshakes.
3. **Zero Telemetry & Air-Gapped Ready:** Querya emits no network telemetry, analytics pings, or telemetry metrics. It can be safely deployed within isolated VPCs, financial infrastructure, and defense networks.
4. **Transport Security:** Full support for TLS/SSL certificates, client keys, and certificate authorities across all network-backed drivers.

See **[Security Architecture Documentation](docs/security.md)** for further details.

---

## Documentation

Comprehensive guides and technical documentation are available in the **[`docs/`](docs/README.md)** directory:

- **[Getting Started](docs/getting-started.md)** — Installation, dependencies, and connecting to your first database.
- **[User Guide](docs/user-guide.md)** — Navigation, workspaces, query execution, and preferences.
- **[Architecture](docs/architecture.md)** — Codebase structure, data flow, and module boundaries.
- **[Theme System](docs/theme.md)** & **[Theme Importer](docs/theme-import.md)** — Custom themes and VS Code theme parser.
- **[Security Overview](docs/security.md)** — Local storage, encryption, and credential lifecycle.
- **[Roadmap](docs/roadmap.md)** — Product roadmap and upcoming releases.

---

## Contributing

We welcome contributions from the community. Please review our **[Contributing Guide](CONTRIBUTING.md)** for:
- GitFlow branch model (`issue/<id>-<slug>` ➔ `dev` ➔ `main`)
- Conventional Commits specification
- Automated testing and static analysis requirements (`flutter analyze`, `flutter test`)

---

## License

Querya Desktop is open-source software licensed under the **[MIT License](LICENSE)**. Third-party components and libraries retain their respective licenses.
