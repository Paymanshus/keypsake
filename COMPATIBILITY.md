# Compatibility: macOS and Windows

keypsake ships as two native apps from this repo:

| | macOS | Windows |
|---|---|---|
| Code | `Sources/Keypsake/` (Swift, SwiftUI) | `rust/` (Rust core + Tauri shell + Svelte UI) |
| Build | `./build.sh`, `scripts/release.sh` | `cd rust/app && npm ci && npx tauri build` |
| Release asset | `keypsake-<version>.dmg` | `keypsake-<version>-x64-setup.exe` |

They are separate implementations of **one product**. This file is the contract between them: what must match exactly, what differs on purpose, and where each rule lives in both codebases. The macOS app is the reference. When the two disagree and this file doesn't list it as intentional, the difference is a bug.

## 1. Must match exactly

### Data format

A database written by one app must be readable by the other (given the key).

| | Swift | Rust |
|---|---|---|
| Schema (`sessions`, `snapshots`, `clips`, index) | `Store.init` in `Store.swift` | `SCHEMA` in `rust/crates/core/src/store.rs` |
| Timestamps | `REAL`, seconds since 1970 | same |
| `length` | `String.count` (grapheme clusters) | `text::len` (grapheme clusters) |
| Sealed fields | `window`, `domain`, `body` | same |
| Cipher | AES-256-GCM, CryptoKit `SealedBox.combined` | `Cipher` in `store.rs`: nonce(12) ‖ ciphertext ‖ tag(16) |
| Key | 32 random bytes | same |

Changing the schema means a migration in **both** apps, shipped in the same version.

### Capture behavior

Constants and rules from `TypedCapture` (`Capture.swift`) and `Tracker` (`rust/crates/core/src/capture.rs`):

| Rule | Value |
|---|---|
| Read the box after a keystroke | 80 ms debounce, plus right away on Return/Enter |
| Save after typing stops | 1.5 s |
| Max text kept per box / per copy | 200,000 characters |
| Live text boxes tracked | 30 |
| Decoy input (value never moves while keys go in) | 8 keystrokes, then rebuild from keys |
| Cliff (text lost) | previous ≥ 20 chars and new < previous / 2 → save previous as a cliff |
| Box cleared | < 3 non-space chars after a cliff → next text is a new entry |
| Minimum saved | 3 non-space chars |
| Same version keeps growing | within 5 min, no cliff, common prefix ≥ old length − 20 |
| Versions per box | 60, oldest non-cliff removed first |
| Baseline | text already in the box when typing starts is left out (`region`, `withoutJustTyped`, `clean`) |
| Password fields | never read (AX secure text field / UIA `IsPassword`) |
| Terminals | keystrokes only, not scrollback |
| App switch | saves the box being left |

### What the user sees

| Item | Swift | Rust / UI |
|---|---|---|
| Word diff: tokens, 40,000-token limit, added-phrase joining, removed words in place | `Diff.swift` | `rust/crates/core/src/diff.rs` |
| Diff summary wording | `Diff.summary` | `diff::summary` |
| Default version (longest if latest < half of it) | `TypedPane.defaultVersion` | `view::default_version` |
| Timestamps: `HH:mm` today, `Yest HH:mm`, else `MMM d`; `N chars` | `Stamp` in `Theme.swift` | `rust/app/ui/src/stamp.js` |
| Palette (light/dark): fog, ink, carbon, ghost, amber cliff | `Theme.swift` | `rust/app/ui/src/theme.css` |
| Fonts: Redaction, Martian Grotesk, Martian Mono | `Resources/Fonts` | same files, copied at build by `scripts/copy-fonts.mjs` |
| Layout, sizes, spacing, copy text | `Views.swift`, `Settings.swift` | `rust/app/ui/src/*.svelte` (each file names its SwiftUI counterpart) |
| Retention choices 7d/30d/90d/1y (default 30), copies 25–500 (default 50) | `Settings.swift`, `Prefs` | `prefs.rs`, `Settings.svelte` |
| Search: case-insensitive over text, title, window, app (clips: text, app, domain) | `TypedPane.items`, `CopiedPane.items` | `TypedPane.svelte`, `CopiedPane.svelte` |
| Demo data (`--demo`) | `Demo.swift` | `rust/crates/core/src/demo.json` (same story, Windows app names) |
| Fixed skip / browser / terminal lists | `Source` in `Source.swift` | `source::WINDOWS` in `source.rs` (same categories, Windows exe names) |
| Favicons: apple-touch-icon first, then largest `<link rel=icon>`, then `/favicon.ico`; 7-day miss cache | `Icons.iconLinks` | `favicon.rs`, `app/src-tauri/src/icons.rs` |

## 2. Different on purpose

Follow each platform's own conventions. Add a row here whenever you introduce a difference.

| Topic | macOS | Windows | Why |
|---|---|---|---|
| Reading text boxes | Accessibility (AX) | UI Automation | OS API |
| Global keystrokes | `NSEvent` global monitor | `WH_KEYBOARD_LL` hook | OS API |
| Permission | Accessibility grant, banner + "Fix" | none; banner only if the hook fails | Windows doesn't gate this |
| Delete word | Option-Delete | Ctrl+Backspace | OS convention |
| AltGr | n/a | Ctrl+Alt with a printed char counts as text | European layouts |
| Clipboard | polls `changeCount` every 0.5 s | `WM_CLIPBOARDUPDATE` listener | no event on macOS |
| Private clipboard markers | `org.nspasteboard.*` types | `ExcludeClipboardContentFromMonitorProcessing`, `CanIncludeInClipboardHistory`=0, `Clipboard Viewer Ignore` | each OS's convention |
| Key storage | Keychain (Developer ID) or 0600 file (local builds) | DPAPI-wrapped `key.bin` | OS secret store |
| Data folder | `~/Library/Application Support/keypsake` | `%LOCALAPPDATA%\keypsake` | OS convention |
| Settings storage | `UserDefaults` | `prefs.json` in the data folder | OS convention |
| App identity (`bundle` column) | bundle id | exe path (lists match the lowercase exe name) | OS convention |
| Window titles | as reported | trailing " - App Name" removed | Windows titles repeat the app name |
| Lives in | menu bar + Dock | tray (+ taskbar while open); closing the window hides it | OS convention |
| Window chrome | traffic lights left, header inset 104 pt | caption buttons right, header inset 20 px | OS convention |
| Shortcuts in the window | ⌘[ ⌘] ⌘F ⌘⌫ ⌘1–9 ⌘, | Ctrl+[ Ctrl+] Ctrl+F Ctrl+Delete Ctrl+1–9 Ctrl+, | OS convention |
| Global shortcuts (defaults) | ⌃⌥K open, ⌃⌥P pause | Ctrl+Alt+K, Ctrl+Alt+P | OS convention |
| Opened at login | window shows | starts hidden in the tray (`--hidden`) | Windows norm |
| Icons in the UI | SF Symbols | inline SVG strokes (`Icon.svelte`) | no SF Symbols on Windows |
| Delete-all confirmation | `NSAlert` | in-window dialog | OS / webview |
| Screenshots | `keypsake --demo --snap docs` | `npm run snap` (browser + demo data) → `docs/windows/` | tooling |
| Diff alignment | `CollectionDifference` | `similar` (Myers) | same counts; ties may align differently |
| Arrow keys / Enter | only from the search field | also when nothing has focus | **candidate for macOS** |

## 3. Checklist for any change

1. Does it change behavior a user can see or data on disk? Then it goes in **both** apps, in the same PR when possible. If one side has to wait, open an issue and say so in the PR.
2. Port by meaning, not line by line: a rule in `Capture.swift` usually lands in `capture.rs`, a view in `Views.swift` lands in the matching `.svelte` file.
3. Keep the constants in section 1 identical. If you change one, change it in both places and update this file.
4. A difference that follows platform convention goes in section 2.
5. Tests: Rust core changes get a test in `rust/crates/core`. Swift checks live in `Diff.selfCheck()` (DEBUG builds); mirror new Rust fixtures there when they cover shared logic.
6. One version for both: bump `Resources/Info.plist`, `rust/Cargo.toml`, `rust/app/src-tauri/tauri.conf.json` and `rust/app/package.json` together. `scripts/check-versions.sh` checks this (CI runs it).
7. UI changes: refresh both sets of screenshots (`docs/` from macOS, `docs/windows/` from `npm run snap`).

## 4. What can't be checked from Linux CI

CI builds and tests the Rust side on Linux and Windows. The Swift app has no CI. Capture behavior on real apps (Chrome, Word, Slack, Windows Terminal, password fields) still needs a manual pass on each OS before a release.
