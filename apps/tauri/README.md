# Querya Desktop (Tauri)

Parallel greenfield client: **Tauri 2 + Vue 3 + Pinia**. Lives next to the Flutter app in this monorepo. UI kit is Querya (Fluid Motion + Liquid Glass) — **not** shadcn.

Integration branch: `epic/tauri-migration`. Child work: `issue/<n>-slug` → PR into that epic branch.

## Prerequisites

- [Node.js](https://nodejs.org/) 20+ and [pnpm](https://pnpm.io/)
- [Rust](https://rustup.rs/) stable + platform Tauri deps  
  See [Tauri prerequisites](https://tauri.app/start/prerequisites/)
- `pnpm` / `cargo` on `PATH`

## First run

```bash
cd apps/tauri
pnpm install
pnpm tauri dev
```

Useful scripts:

| Script | What |
|--------|------|
| `pnpm dev` | Vite only (webview HMR) |
| `pnpm tauri dev` | Full desktop shell |
| `pnpm build` | `vue-tsc` + Vite production build |
| `pnpm typecheck` | TypeScript / Vue check |
| `pnpm tauri build` | Native bundles |

Rust checks:

```bash
cd src-tauri
cargo check
cargo test
```

## Layout

```
apps/tauri/
  src/           # Vue 3 + Pinia
  src-tauri/     # Rust / Tauri 2
```

Identifier: `com.queryahub.querya_tauri` (distinct from Flutter `com.queryahub.querya_desktop`).

## GitFlow note

Do not open PRs from tauri issue branches into `dev` until the SQLite vertical slice on the epic branch is green. Target **`epic/tauri-migration`**.
