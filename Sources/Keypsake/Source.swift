import AppKit
import ApplicationServices

// MARK: - Accessibility helpers

enum AX {
    static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
    static func string(_ el: AXUIElement, _ name: String) -> String? { attr(el, name) as? String }
    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = attr(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func app(_ pid: pid_t) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.5) // a hung app must not stall capture
        return el
    }

    private static var enabled = Set<pid_t>()
    /// Electron and Chromium only build their accessibility tree when asked.
    static func wakeUp(_ app: AXUIElement, pid: pid_t) {
        guard !enabled.contains(pid) else { return }
        enabled.insert(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}

// MARK: - Where did this text come from

enum Source {
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary",
        "company.thebrowser.Browser", "company.thebrowser.dia", "com.brave.Browser", "com.microsoft.edgemac",
        "org.mozilla.firefox", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "ai.perplexity.comet",
        "app.zen-browser.zen", "org.chromium.Chromium",
    ]

    /// ponytail: fixed skip lists; a user-editable blocklist comes later.
    static let secrets: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords",
    ]
    static let skipped: Set<String> = secrets.union(["com.keypsake.app"])
    /// Terminals expose the whole scrollback as one text box, so only keystrokes count there.
    static let keysOnly: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm",
    ]

    static func context(app: NSRunningApplication, appEl: AXUIElement, focused: AXUIElement?) -> SourceContext {
        let window = AX.element(appEl, kAXFocusedWindowAttribute).flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        var domain: String?
        if let b = app.bundleIdentifier, browsers.contains(b) {
            domain = pageURL(appEl: appEl, focused: focused)?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        }
        return SourceContext(app: app.localizedName ?? "Unknown app", bundle: app.bundleIdentifier, window: window, domain: domain)
    }

    /// Walk up from the focused element to the web area, which carries the page URL.
    private static func pageURL(appEl: AXUIElement, focused: AXUIElement?) -> URL? {
        var el = focused
        for _ in 0..<60 {
            guard let cur = el else { break }
            if AX.string(cur, kAXRoleAttribute) == "AXWebArea", let u = AX.attr(cur, kAXURLAttribute) {
                if let url = u as? URL { return url }
                if let s = u as? String { return URL(string: s) }
            }
            el = AX.element(cur, kAXParentAttribute)
        }
        if let win = AX.element(appEl, kAXFocusedWindowAttribute), let doc = AX.string(win, kAXDocumentAttribute) {
            return URL(string: doc)
        }
        return nil
    }

    /// Context for whatever app is in front right now (used for clipboard sources).
    static func frontmost() -> SourceContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        guard AXIsProcessTrusted() else {
            return SourceContext(app: app.localizedName ?? "Unknown app", bundle: app.bundleIdentifier, window: "", domain: nil)
        }
        let appEl = AX.app(app.processIdentifier)
        return context(app: app, appEl: appEl, focused: AX.element(appEl, kAXFocusedUIElementAttribute))
    }
}

// MARK: - Real icons: app icons from disk, favicons fetched straight from the site

final class Icons: ObservableObject {
    static let shared = Icons()
    @Published private var favicons: [String: NSImage] = [:]
    private var appIcons: [String: NSImage] = [:]
    private var tried = Set<String>()
    private let dir: URL = {
        let d = Store.supportDir.appendingPathComponent("favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func app(_ bundle: String?) -> NSImage? {
        guard let bundle else { return nil }
        if let i = appIcons[bundle] { return i }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[bundle] = icon
        return icon
    }

    func favicon(_ domain: String?) -> NSImage? {
        guard let domain else { return nil }
        if let i = favicons[domain] { return i }
        if !tried.contains(domain) { tried.insert(domain); load(domain) }
        return nil
    }

    private func load(_ domain: String) {
        let file = dir.appendingPathComponent(domain + ".png")
        let miss = dir.appendingPathComponent(domain + ".miss")
        // Called during view rendering, so publish on the next turn.
        if let img = NSImage(contentsOf: file) { DispatchQueue.main.async { self.favicons[domain] = img }; return }
        if let at = (try? miss.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(at) < 7 * 86400 { return }
        Task.detached(priority: .utility) {
            let img = await Self.fetch(domain)
            await MainActor.run {
                if let img, let png = Self.png(img) {
                    try? png.write(to: file)
                    self.favicons[domain] = img
                } else {
                    try? Data().write(to: miss)
                }
            }
        }
    }

    private static func fetch(_ domain: String) async -> NSImage? {
        guard let home = URL(string: "https://\(domain)/") else { return nil }
        var candidates: [URL] = []
        if let (data, resp) = try? await URLSession.shared.data(from: home), let html = String(data: data.prefix(300_000), encoding: .utf8) {
            candidates = iconLinks(in: html, base: resp.url ?? home)
        }
        candidates.append(home.appendingPathComponent("favicon.ico"))
        for url in candidates {
            if let (data, _) = try? await URLSession.shared.data(from: url), let img = NSImage(data: data),
               img.size.width > 0 { return img }
        }
        return nil
    }

    /// Prefer apple-touch-icon (large), then the biggest declared <link rel=icon>.
    static func iconLinks(in html: String, base: URL) -> [URL] {
        guard let tag = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive) else { return [] }
        func attr(_ name: String, _ s: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']", options: .caseInsensitive),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let r = Range(m.range(at: 1), in: s) else { return nil }
            return String(s[r])
        }
        var found: [(score: Int, url: URL)] = []
        for m in tag.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(m.range, in: html) else { continue }
            let s = String(html[r])
            guard let rel = attr("rel", s)?.lowercased(), rel.contains("icon"), let href = attr("href", s),
                  let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL else { continue }
            let size = attr("sizes", s).flatMap { Int($0.lowercased().split(separator: "x").first ?? "") } ?? 16
            found.append((rel.contains("apple-touch") ? 1000 + size : size, url))
        }
        return found.sorted { $0.score > $1.score }.map(\.url)
    }

    private static func png(_ img: NSImage) -> Data? {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
