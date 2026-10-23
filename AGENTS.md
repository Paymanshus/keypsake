# Working on keypsake

keypsake is one product shipped as two native apps from this repo:

- **macOS**: Swift/SwiftUI at the repo root (`Package.swift`, `Sources/Keypsake/`, `Resources/`, `build.sh`, `scripts/release.sh`). This is the reference implementation.
- **Windows**: Rust in `rust/`: `crates/core` (platform-free logic, encrypted store, diff), `crates/platform-windows` (keyboard hook, UI Automation, clipboard, DPAPI), `app/src-tauri` (Tauri shell: windows, tray, shortcuts, commands) and `app/ui` (Svelte UI).

## The rule: every change goes to both apps

Unless the task is explicitly about one platform, a change to behavior, UI, copy, data or settings must be made in **both** the Swift app and the Rust app, in the same change.

Before you finish:

1. Read [COMPATIBILITY.md](COMPATIBILITY.md). It maps each rule, constant and screen to its file in both codebases and lists the intentional differences.
2. Make the change on both sides. Port by meaning, following each platform's conventions (see COMPATIBILITY.md §2).
3. If you change a shared constant, the schema, the encryption format or visible copy, update both sides and COMPATIBILITY.md.
4. If one side truly can't be done now, say so explicitly in your summary and the PR description, and why.
5. Bumping the version? Bump all four files listed in COMPATIBILITY.md §3. `scripts/check-versions.sh` must pass.

## Checks

Rust (from `rust/`):

```bash
cargo fmt --all --check
cargo clippy -p keypsake-core --all-targets -- -D warnings
cargo test -p keypsake-core
# Windows-only crates, from Linux with MinGW (apt install gcc-mingw-w64-x86-64):
cargo clippy --workspace --all-targets --target x86_64-pc-windows-gnu -- -D warnings
```

UI (from `rust/app/`): `npm ci && npm run build`. `npm run snap` renders screenshots with demo data in a browser (needs Playwright); compare them with `docs/*.png` from the Mac app.

Swift: `swift build` on macOS. There is no Swift CI and no Linux toolchain for it, so if you can't build Swift, say so and keep the Swift change small and obviously correct.

## Conventions

- Match the surrounding code: short doc comments that say *why*, small files, no frameworks beyond what's there.
- Privacy is the product: nothing leaves the machine except favicon fetches to the site itself. Never add telemetry, remote logging or third-party services.
- Password fields, password managers and private clipboard items are never recorded, on either platform.
