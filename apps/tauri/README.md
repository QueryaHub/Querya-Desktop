# Querya Desktop (Tauri)

Parallel greenfield client: **Tauri 2 + Vue 3 + Pinia**. Lives next to the Flutter app in this monorepo. UI kit is Querya (Fluid Motion + Liquid Glass) — **not** shadcn.

| | |
|---|---|
| Integration branch | `epic/tauri-migration` |
| Child branches | `issue/<n>-slug` → PR into the epic branch |
| Bundle id | `com.queryahub.querya_tauri` (Flutter stays `com.queryahub.querya_desktop`) |
| CI | [`.github/workflows/tauri-ci.yml`](../../.github/workflows/tauri-ci.yml) (path-filtered on `apps/tauri/**`) |

## Toolchain (pinned / expected)

| Tool | Expect |
|------|--------|
| Node.js | **20+** (CI uses 22) |
| pnpm | **10+** |
| Rust | **stable** via [rustup](https://rustup.rs/) |
| Tauri CLI | via `pnpm` (`@tauri-apps/cli` in this package) |
| Vue / Vite | see `package.json` |

Do not use a global `cargo install tauri-cli` for day-to-day work — prefer `pnpm tauri …` so the CLI matches the lockfile.

## Platform dependencies

Official matrix: [Tauri prerequisites](https://tauri.app/start/prerequisites/).

### Linux (Debian/Ubuntu-like)

```bash
sudo apt update
sudo apt install -y \
  build-essential curl wget file libxdo-dev libssl-dev \
  libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev patchelf
```

Arch: `webkit2gtk-4.1`, `base-devel`, `curl`, `wget`, `file`, `openssl`, `appmenu-gtk-module`, `librsvg`, `xdotool`.

### macOS

- Xcode CLT: `xcode-select --install`
- Optional: `brew install` nothing extra for a basic `tauri dev` on recent macOS

### Windows

- Microsoft C++ Build Tools + WebView2 (Tauri installer docs cover this)
- Use a developer PowerShell / VS Dev environment so `link.exe` is on `PATH`

## First run

```bash
cd apps/tauri
pnpm install
pnpm tauri dev
```

UI-core first: empty hero → **Demo** (offline catalog) or Open SQLite → connection **Overview** → click a table for **Data** grid. SQL is parked on the connection home SQL tab. Live DB commands remain for later slices.

### Scripts

| Script | What |
|--------|------|
| `pnpm dev` | Vite only (webview HMR) |
| `pnpm tauri dev` | Full desktop shell |
| `pnpm build` | `vue-tsc` + Vite production build |
| `pnpm typecheck` | TypeScript / Vue check |
| `pnpm test` | Vitest (query stream accumulator smoke) |
| `pnpm tauri build` | Native bundles |

SQLite fixture: [`fixtures/smoke.db`](./fixtures/smoke.db) — exercised by `cargo test` (`connect_introspect_query_fixture`).

### Rust

```bash
cd apps/tauri/src-tauri
cargo check --locked
cargo test --locked
```

## Layout

```
apps/tauri/
  src/                 # Vue 3 + Pinia
  src/stores/          # Pinia stores
  src-tauri/           # Rust / Tauri 2
  src-tauri/src/       # crate root (lib + bin)
  pnpm-workspace.yaml  # allows esbuild postinstall under pnpm 10+
```

## Troubleshooting

- **`ERR_PNPM_IGNORED_BUILDS` / missing esbuild** — this package lists `esbuild` under `onlyBuiltDependencies` in `pnpm-workspace.yaml`. Re-run `pnpm install`. On older pnpm, `pnpm approve-builds --all` then reinstall.
- **`cargo` cannot find webkit** — install the Linux packages above; wrong webkit major (4.0 vs 4.1) is a common miss.
- **Port 1420 in use** — Vite is fixed to `1420` for Tauri (`vite.config.ts`). Free the port or stop the other process.
- **Flutter analysis noisy after opening this folder** — open `querya-desktop.code-workspace` (or use root `.vscode/settings.json`) so rust-analyzer links only `apps/tauri/src-tauri`.

## GitFlow

1. `git fetch && git checkout epic/tauri-migration && git pull --ff-only`
2. `git checkout -b issue/<n>-short-slug`
3. PR **into `epic/tauri-migration`**, body contains `Closes #<n>`
4. Do **not** target `dev` until the SQLite vertical slice on the epic branch is green
