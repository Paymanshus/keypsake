<p align="center">
  <img src="docs/keypsake.gif" alt="keypsake: typed text gets cleared, keypsake keeps it" width="640">
</p>

# keypsake

Everything you type, kept. A small app for macOS and Windows that quietly saves what you type into any text box, in any app, so a crashed tab, a stray click or a cleared form never costs you a long piece of writing again. It also keeps a short clipboard history.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/typed-dark.png">
  <img src="docs/typed.png" alt="Typed tab: an email draft that was cleared, with the version before the loss preselected">
</picture>

## Download

### macOS

Grab **keypsake-x.y.z.dmg** from [Releases](https://github.com/Paymanshus/keypsake/releases/latest), open it and drag keypsake into Applications. Universal build (Apple Silicon and Intel), macOS 14 or later.

This build is not notarized by Apple yet, so the first launch needs one extra step:

1. Open keypsake. macOS says it can't verify the developer. Click **Done**.
2. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to keypsake.
3. Turn on **Accessibility** for keypsake when asked. That's the only permission it needs.

Updates signed with the same identity keep your Accessibility setting.

### Windows

Grab **keypsake-x.y.z-x64-setup.exe** from [Releases](https://github.com/Paymanshus/keypsake/releases/latest) and run it. It installs for your user only (no admin needed). Windows 10 or 11, 64-bit.

The installer isn't code-signed yet, so SmartScreen may say "Windows protected your PC": click **More info**, then **Run anyway**. Windows needs no extra permission for keypsake to see what you type. It lives in the tray; closing the window keeps it running.

Some antivirus tools flag any app that watches the keyboard. keypsake keeps everything on your PC and never connects anywhere except to fetch a site's own icon.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/windows/typed-dark.png">
  <img src="docs/windows/typed.png" alt="keypsake on Windows: the same Typed tab, with Windows window buttons">
</picture>

## What it does

- **Typed.** One entry per text box you typed into, with the app or website, its real icon and the window title. Only what you typed this time is kept: text that was already in a note or document stays out.
- **Versions, and the moment text was lost.** As you write, keypsake keeps versions. If a box suddenly empties or loses most of its text, the version just before is saved and marked in amber ("box was cleared right after this"), and it is the one shown first.
- **Changes anyone can read.** Switch a version to *Changes* to see it against the one before: added words highlighted, removed words struck through, plus a plain summary like "40 words added".
- **Copied.** Your last 25 to 500 copies (you choose), with the source app or site. Click or press ⌘1–9 (Ctrl+1–9) to copy one back.
- **Menu bar and Dock** on macOS, **tray** on Windows. ⌃⌥K (Ctrl+Alt+K) opens it, ⌃⌥P (Ctrl+Alt+P) pauses recording.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/copied-dark.png">
  <img src="docs/copied.png" alt="Copied tab: clipboard history with source icons and ⌘1–9 shortcuts">
</picture>

## Privacy

- History is encrypted (AES-GCM) and stored only on your computer. Nothing is sent anywhere.
- Password fields, password managers and items marked as concealed on the clipboard are never recorded.
- Terminals record your keystrokes (the commands you typed), not their whole scrollback.
- Site icons are fetched from the site you were on and cached. No third-party icon service.
- Typed text is deleted after 7, 30, 90 or 365 days (your choice). Pause anytime, or delete everything in Settings.

<p align="center"><img src="docs/settings.png" alt="Settings" width="440"></p>

## Install from source

### macOS

Needs macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not required.

```bash
git clone https://github.com/Paymanshus/keypsake.git
cd keypsake
./scripts/setup-signing.sh   # once: a local signing identity so macOS remembers permissions across rebuilds
./build.sh                   # builds, installs to /Applications and opens it
```

Then turn on **Accessibility** for keypsake when asked (System Settings → Privacy & Security → Accessibility). That is the only permission it needs. Clipboard history works without it.

If keypsake is switched on in that list but still asks, the entry belongs to an older build: click **Already on? Fix it** in the app, then switch it on again.

### Windows

Needs [Rust](https://rustup.rs), [Node.js](https://nodejs.org) 20+ and the Visual Studio C++ Build Tools (WebView2 ships with Windows 10/11).

```powershell
git clone https://github.com/Paymanshus/keypsake.git
cd keypsake\rust\app
npm ci
npx tauri dev        # run it
npx tauri build      # installer in rust\target\release\bundle\nsis
```

`npx tauri dev -- -- --demo` starts with made-up history and records nothing.

## How it works

- `Capture.swift`: a global key monitor triggers reads of the focused text box through the Accessibility API. If an app does not expose its text (Google Docs, some Electron apps, terminals), the text is rebuilt from keystrokes. A "cliff" (sudden large drop in length) saves the version before it.
- `Store.swift`: SQLite with every text field sealed by CryptoKit. Developer ID builds keep the key in the Keychain; local self-signed builds keep it in a file only your user can read, because each local build would otherwise trigger a Keychain prompt.
- `Diff.swift`: word-level diff on Swift's `CollectionDifference`.
- `Views.swift`, `Settings.swift`: SwiftUI hosted in AppKit windows.

On Windows the same logic is in Rust under `rust/`: `crates/core` (capture rules, encrypted store, diff; tested on any OS), `crates/platform-windows` (a low-level keyboard hook and UI Automation instead of AX, a clipboard listener, DPAPI instead of the Keychain) and a Tauri app whose Svelte UI mirrors the SwiftUI views. The two apps share the database format, fonts and palette. [COMPATIBILITY.md](COMPATIBILITY.md) lists what must match and what differs on purpose.

Design: Redaction (display), Martian Grotesk (UI) and Martian Mono (meta), all SIL OFL and bundled in `Resources/Fonts`. Palette: fog `#ECEEF2`, ink `#1B1C22`, carbon `#3B3FC4`, amber `#D98A2B` reserved for "text was lost here".

Screenshots come from `keypsake --demo --snap docs` (made-up data, nothing recorded); the Windows ones from `npm run snap` in `rust/app`. The motion graphic is rendered by `Resources/Video/render_video.swift`: [keypsake.mp4](docs/keypsake.mp4).

## Releasing

Both apps share one version number: bump `Resources/Info.plist`, `rust/Cargo.toml`, `rust/app/src-tauri/tauri.conf.json` and `rust/app/package.json` together (`scripts/check-versions.sh` checks).

- macOS: `./scripts/release.sh` builds the universal app and `build/keypsake-<version>.dmg`. Signing with an Apple Developer ID and notarizing would remove the "Open Anyway" step.
- Windows: pushing a `v<version>` tag runs `.github/workflows/release-windows.yml`, which builds `keypsake-<version>-x64-setup.exe` and attaches it to that release (as a draft if the release doesn't exist yet). Code signing would remove the SmartScreen step.

## License

[Apache License 2.0](LICENSE). Use, modify and redistribute freely; keep the [NOTICE](NOTICE) crediting the original project. Bundled fonts are under the SIL Open Font License 1.1.
