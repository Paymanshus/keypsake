import AppKit
import CryptoKit

/// `--demo` launches with made-up history in a separate folder and records nothing. Used for README screenshots.
/// `--dark` forces dark appearance.
enum Demo {
    static let on = CommandLine.arguments.contains("--demo")
    static let dark = CommandLine.arguments.contains("--dark")
}

extension Store {
    func seedDemo() {
        struct S { let app, bundle: String; let domain: String?; let window: String; let versions: [(ago: Double, text: String, cliff: Bool)] }
        let sessions: [S] = [
            S(app: "Safari", bundle: "com.apple.Safari", domain: "mail.google.com", window: "Re: Q4 launch plan", versions: [
                (14, "Hi team,\n\nThanks for pulling this together.", false),
                (11, "Hi team,\n\nThanks for pulling this together. A few thoughts before Thursday:\n\n1. Let's move the beta invite to the 14th so support has a full week with the new docs.", false),
                (6, "Hi team,\n\nThanks for pulling this together. A few thoughts before Thursday:\n\n1. Let's move the beta invite to the 14th so support has a full week with the new docs.\n2. The pricing page still says \"unlimited history\". It should say 30 days, adjustable in Settings.\n3. Keep the launch post short: one screenshot, one sentence, one link.\n\nHappy to walk through it tomorrow morning if that's easier.\n\nBest", true),
            ]),
            S(app: "Messages", bundle: "com.apple.MobileSMS", domain: nil, window: "Friday dinner", versions: [
                (31, "running 10 min late, grab us a table by the window?", false),
            ]),
            S(app: "Notes", bundle: "com.apple.Notes", domain: nil, window: "Lisbon, three days", versions: [
                (95, "Tram 28 early, before 9\nPastéis de Belém on a weekday", false),
                (80, "Tram 28 early, before 9\nPastéis de Belém on a weekday, not Sunday\nLX Factory market\nSunset at Miradouro da Senhora do Monte", false),
            ]),
            S(app: "Safari", bundle: "com.apple.Safari", domain: "github.com", window: "Move dev key out of the Keychain · Pull Request #42", versions: [
                (190, "Local builds are self-signed, so every rebuild looked like a new app to the Keychain and asked for a password. Dev builds now keep the key in a file only your account can read. Developer ID builds still use the Keychain.", false),
            ]),
            S(app: "Terminal", bundle: "com.apple.Terminal", domain: nil, window: "keypsake — zsh", versions: [
                (230, "git checkout -b release/0.2\nswift build -c release\n./build.sh", false),
            ]),
            S(app: "Safari", bundle: "com.apple.Safari", domain: "linear.app", window: "KEY-118 Show real icons for copied items", versions: [
                (1500, "Favicons come straight from the site you were on, cached on disk. No third-party icon service.", false),
                (1490, "Favicons come straight from the site you were on, cached on disk for a week. No third-party icon service, so nothing about your browsing leaves the Mac.", false),
            ]),
            S(app: "Code", bundle: "com.microsoft.VSCode", domain: nil, window: "Diff.swift — keypsake", versions: [
                (2900, "// Spaces between two added words are highlighted too, so an added phrase reads as one block.", false),
            ]),
        ]
        let now = Date().timeIntervalSince1970
        for s in sessions {
            let ctx = SourceContext(app: s.app, bundle: s.bundle, window: s.window, domain: s.domain)
            let sid = createSession(ctx)
            for v in s.versions {
                let id = addSnapshot(session: sid, ctx: ctx, text: v.text, cliff: v.cliff)
                db.run("UPDATE snapshots SET created = ? WHERE id = ?", [now - v.ago * 60, id])
            }
            let first = s.versions.first!.ago, last = s.versions.last!.ago
            db.run("UPDATE sessions SET created = ?, updated = ? WHERE id = ?", [now - first * 60, now - last * 60, sid])
        }
        // Smaller bits across the week so keypstats has a rhythm to show.
        let bits = ["on my way", "can we push this to 3?", "sounds good, shipping it after lunch",
                    "Reminder: the beta invite goes out on the 14th, docs first, then the post.",
                    "pick up oat milk, batteries, the good coffee", "lgtm, merge when green",
                    "Quick update: the export bug is fixed and the build is uploading now. Should be live in an hour."]
        let apps: [(String, String, String?)] = [("Messages", "com.apple.MobileSMS", nil), ("Safari", "com.apple.Safari", "mail.google.com"),
                                                 ("Notes", "com.apple.Notes", nil), ("Safari", "com.apple.Safari", "github.com")]
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        for d in 0..<7 {
            for (k, hour) in [9, 10, 11, 11, 14, 16, 21, 23].enumerated() where (d * 3 + k) % 4 != 0 {
                let ago = (now - (today - Double(d) * 86400 + Double(hour) * 3600)) / 60
                guard ago > 5 else { continue }
                let a = apps[(d + k) % apps.count]
                let ctx = SourceContext(app: a.0, bundle: a.1, window: "", domain: a.2)
                let sid = createSession(ctx)
                let id = addSnapshot(session: sid, ctx: ctx, text: bits[(d * 5 + k) % bits.count], cliff: false)
                db.run("UPDATE snapshots SET created = ? WHERE id = ?", [now - ago * 60, id])
                db.run("UPDATE sessions SET created = ?, updated = ? WHERE id = ?", [now - ago * 60, now - ago * 60, sid])
            }
        }

        let clips: [(String, String, String?, String, Double)] = [
            ("Safari", "com.apple.Safari", "github.com", "https://github.com/Paymanshus/keypsake", 3),
            ("Notes", "com.apple.Notes", nil, "Tram 28 early, before 9", 18),
            ("Terminal", "com.apple.Terminal", nil, "swift build -c release", 40),
            ("Mail", "com.apple.mail", nil, "Your order ships Thursday. Tracking: 1Z 999 AA1 01 2345 6784", 75),
            ("Code", "com.microsoft.VSCode", nil, "static func region(_ full: String, baseline: String) -> String", 130),
            ("Safari", "com.apple.Safari", "linear.app", "KEY-118", 200),
            ("Messages", "com.apple.MobileSMS", nil, "See you at 7, table by the window", 300),
            ("Safari", "com.apple.Safari", "github.com", "#3B3FC4", 600),
        ]
        for c in clips.reversed() {
            addClip(text: c.3, ctx: SourceContext(app: c.0, bundle: c.1, window: "", domain: c.2), limit: 50)
            db.run("UPDATE clips SET created = ? WHERE id = (SELECT max(id) FROM clips)", [now - c.4 * 60])
        }
        reload()
    }
}

/// `--demo --snap DIR`: renders the main window (Typed, Copied, keypstats) and Settings to PNGs in DIR at 2x, then quits.
enum Snapper {
    static var dir: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "--snap"), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func run(window: NSWindow, settings: @escaping () -> NSWindow?, state: AppState) {
        guard let dir else { return }
        let suffix = Demo.dark ? "-dark" : ""
        window.setContentSize(NSSize(width: 1080, height: 700))
        window.center()
        let steps: [(Double, () -> Void)] = [
            (2.5, { save(window, "\(dir)/typed\(suffix).png") }),
            (0.2, { state.tab = .copied }),
            (0.8, { save(window, "\(dir)/copied\(suffix).png"); state.tab = .stats }),
            (1.2, { save(window, "\(dir)/stats\(suffix).png"); state.tab = .typed }),
            (0.2, { if let s = settings() { save(s, "\(dir)/settings\(suffix).png") } }),
            (0.8, { if let s = settings() { save(s, "\(dir)/settings\(suffix).png") }; NSApp.terminate(nil) }),
        ]
        var t = 0.0
        for (delay, f) in steps { t += delay; DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }
    }

    private static func save(_ w: NSWindow, _ path: String) {
        guard let view = w.contentView?.superview else { return } // frame view: includes traffic lights
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
