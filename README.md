<p align="center">
  <img src="docs/keypsake.gif" alt="A long prompt in Claude Code dies to a connection error, then keypsake brings it back" width="640">
</p>

# keypsake

**typed it? keyp it.**

A small macOS app that saves what you type into any text box, in any app. For the 40-minute prompt that hit a connection error. The Teams message that vanished when you went back to fix one word. The YouTube search you swore you'd run after this video. ~~ffs~~ for keyp's sake.

It also keeps your clipboard history, the other place things go to die.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/typed-dark.png">
  <img src="docs/typed.png" alt="Typed tab: an email draft that was cleared, with the version before the loss preselected">
</picture>

## Download

Grab **keypsake-x.y.z.dmg** from [Releases](https://github.com/Paymanshus/keypsake/releases/latest), open it and drag keypsake into Applications. Universal build (Apple Silicon and Intel), macOS 14 or later.

This build is not notarized by Apple yet, so the first launch needs one extra step:

1. Open keypsake. macOS says it can't verify the developer. Click **Done**.
2. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to keypsake.
3. Turn on **Accessibility** for keypsake when asked. That's the only permission it needs.

Updates signed with the same identity keep your Accessibility setting.

## What it does

- **Typed.** One entry per text box you typed into, with the app or website, its real icon and the window title. Only what you typed this time is kept: text that was already in a note or document stays out.
- **Versions, and the moment it all went wrong.** As you write, keypsake keeps versions. If a box suddenly empties or loses most of its text, the version right before is saved and marked in amber ("box was cleared right after this"). That one shows first, because that's the one you want.
- **Changes anyone can read.** Switch a version to *Changes* to see it against the one before: added words highlighted, removed words struck through, plus a plain summary like "40 words added".
- **Copied.** Your last 25 to 500 copies (you choose), with the source app or site. Click or press ⌘1–9 to copy one back.
- **Menu bar and Dock.** Lives in both. ⌃⌥K opens it, ⌃⌥P pauses recording.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/copied-dark.png">
  <img src="docs/copied.png" alt="Copied tab: clipboard history with source icons and ⌘1–9 shortcuts">
</picture>

## Privacy

It's a keylogger you run on purpose, so here's exactly what happens to your stuff.

- History is encrypted (AES-GCM) and stored only on your Mac. Nothing is sent anywhere.
- Password fields, password managers and items marked as concealed on the clipboard are never recorded.
- Terminals record your keystrokes (the commands you typed), not their whole scrollback.
- Site icons are fetched from the site you were on and cached. No third-party icon service.
- Typed text is deleted after 7, 30, 90 or 365 days (your choice). Pause anytime, or delete everything in Settings.

<p align="center"><img src="docs/settings.png" alt="Settings" width="440"></p>

## Install from source

Needs macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not required.

```bash
git clone https://github.com/Paymanshus/keypsake.git
cd keypsake
./scripts/setup-signing.sh   # once: a local signing identity so macOS remembers permissions across rebuilds
./build.sh                   # builds, installs to /Applications and opens it
```

Then turn on **Accessibility** for keypsake when asked (System Settings → Privacy & Security → Accessibility). That is the only permission it needs. Clipboard history works without it.

If keypsake is switched on in that list but still asks, the entry belongs to an older build: click **Already on? Fix it** in the app, then switch it on again.

## How it works

- `Capture.swift`: a global key monitor triggers reads of the focused text box through the Accessibility API. If an app does not expose its text (Google Docs, some Electron apps, terminals), the text is rebuilt from keystrokes. A "cliff" (sudden large drop in length) saves the version before it.
- `Store.swift`: SQLite with every text field sealed by CryptoKit. Developer ID builds keep the key in the Keychain; local self-signed builds keep it in a file only your user can read, because each local build would otherwise trigger a Keychain prompt.
- `Diff.swift`: word-level diff on Swift's `CollectionDifference`.
- `Views.swift`, `Settings.swift`: SwiftUI hosted in AppKit windows.

Design: Redaction (display), Martian Grotesk (UI) and Martian Mono (meta), all SIL OFL and bundled in `Resources/Fonts`. Palette: fog `#ECEEF2`, ink `#1B1C22`, carbon `#3B3FC4`, amber `#D98A2B` reserved for "text was lost here".

Screenshots come from `keypsake --demo --snap docs` (made-up data, nothing recorded). The motion graphic is rendered by `Resources/Video/render_video.swift`: [keypsake.mp4](docs/keypsake.mp4).

## Releasing

`./scripts/release.sh` builds the universal app and `build/keypsake-<version>.dmg` (version from `Resources/Info.plist`). Signing with an Apple Developer ID and notarizing would remove the "Open Anyway" step.

## License

[Apache License 2.0](LICENSE). Use, modify and redistribute freely; keep the [NOTICE](NOTICE) crediting the original project. Bundled fonts are under the SIL Open Font License 1.1.
