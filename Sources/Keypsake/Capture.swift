import AppKit
import ApplicationServices

// MARK: - Typed text

private struct KeyStroke {
    let chars: String?
    let keyCode: UInt16
    let flags: NSEvent.ModifierFlags
    let app: NSRunningApplication
}

/// One text box the user is typing into. Text comes from Accessibility when the app exposes it,
/// otherwise it is rebuilt from keystrokes (terminals, canvas editors like Google Docs).
/// Only what was typed this time is kept: text already in the box (a long note) is the baseline and is left out.
private final class LiveField {
    let element: AXUIElement
    let pid: pid_t
    let ctx: SourceContext
    var baseline = ""
    var sessionID: Int64?
    var text = ""
    var keys = ""
    var useKeys: Bool
    var lastFull: String?
    var keysSinceChange = 0
    var snapID: Int64?
    var snapText = ""
    var snapCliff = false
    var snapAt = Date.distantPast

    init(element: AXUIElement, pid: pid_t, ctx: SourceContext, useKeys: Bool) {
        self.element = element; self.pid = pid; self.ctx = ctx; self.useKeys = useKeys
    }
}

final class TypedCapture {
    private let store: Store
    private let isPaused: () -> Bool
    private let q = DispatchQueue(label: "keypsake.capture", qos: .userInitiated)
    private var monitor: Any?
    private var fields: [LiveField] = []
    private var current: LiveField?
    private var readPending = false
    private var idle: DispatchWorkItem?

    private static let maxLength = 200_000

    init(store: Store, isPaused: @escaping () -> Bool) {
        self.store = store
        self.isPaused = isPaused
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e) }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.q.async { self.switchTo(nil) }
        }
    }

    // main thread
    private func key(_ e: NSEvent) {
        guard !isPaused(), let app = NSWorkspace.shared.frontmostApplication,
              !Source.skipped.contains(app.bundleIdentifier ?? "") else { return }
        let k = KeyStroke(chars: e.characters, keyCode: e.keyCode,
                          flags: e.modifierFlags.intersection(.deviceIndependentFlagsMask), app: app)
        q.async { self.handle(k) }
    }

    // capture queue from here down
    private func handle(_ k: KeyStroke) {
        let pid = k.app.processIdentifier
        let appEl = AX.app(pid)
        AX.wakeUp(appEl, pid: pid)
        let focused = AX.element(appEl, kAXFocusedUIElementAttribute)
        if let focused, AX.string(focused, kAXSubroleAttribute) == (kAXSecureTextFieldSubrole as String) { return }
        // No readable focus (some Electron/Java apps): track keystrokes per app instead.
        let el = focused ?? appEl

        let field = fields.first { $0.pid == pid && CFEqual($0.element, el) } ?? {
            let keysOnly = focused == nil || Source.keysOnly.contains(k.app.bundleIdentifier ?? "")
            let f = LiveField(element: el, pid: pid, ctx: Source.context(app: k.app, appEl: appEl, focused: focused),
                              useKeys: keysOnly)
            if !keysOnly, let v = AX.attr(el, kAXValueAttribute) as? String {
                f.baseline = Self.clean(Self.withoutJustTyped(String(v.prefix(Self.maxLength)), k, el))
                f.lastFull = f.baseline
            }
            fields.append(f)
            if fields.count > 30 { fields.removeFirst() }
            return f
        }()
        switchTo(field)
        apply(k, to: field)

        if k.keyCode == 36 || k.keyCode == 76 { read(field) } // Return often clears the box: read right away too
        if !readPending {
            readPending = true
            q.asyncAfter(deadline: .now() + 0.08) {
                self.readPending = false
                if let f = self.current { self.read(f) }
            }
        }
    }

    /// The baseline is read right after the first keystroke, which may already be in the box. Take it back out.
    private static func withoutJustTyped(_ v: String, _ k: KeyStroke, _ el: AXUIElement) -> String {
        guard let c = k.chars?.utf16, c.count == 1, let typed = c.first, typed >= 0x20,
              let raw = AX.attr(el, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return v }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return v }
        var u = Array(v.utf16)
        let i = range.location - 1
        guard i >= 0, i < u.count, u[i] == typed else { return v }
        u.remove(at: i)
        return String(decoding: u, as: UTF16.self)
    }

    /// Drops invisible placeholders apps embed in text values (U+FFFC attachments, private-use icon glyphs).
    static func clean(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { $0.value == 0xFFFC || $0.properties.generalCategory == .privateUse }) else { return s }
        return String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.value != 0xFFFC && $0.properties.generalCategory != .privateUse }))
    }

    /// The part of `full` that differs from `baseline`: everything between the common start and common end.
    static func region(_ full: String, baseline: String) -> String {
        if baseline.isEmpty { return full }
        let x = Array(full.utf16), y = Array(baseline.utf16)
        let m = min(x.count, y.count)
        var p = 0
        while p < m && x[p] == y[p] { p += 1 }
        var s = 0
        while s < m - p && x[x.count - 1 - s] == y[y.count - 1 - s] { s += 1 }
        var lo = p, hi = x.count - s
        if lo > 0, lo < x.count, UTF16.isTrailSurrogate(x[lo]) { lo -= 1 }
        if hi > 0, hi < x.count, UTF16.isTrailSurrogate(x[hi]) { hi += 1 }
        return lo < hi ? String(decoding: x[lo..<hi], as: UTF16.self) : ""
    }

    private func switchTo(_ f: LiveField?) {
        guard current !== f else { return }
        if let old = current { idle?.cancel(); persist(old, old.text, cliff: false) }
        current = f
    }

    private func read(_ f: LiveField) {
        if !f.useKeys {
            if let v = AX.attr(f.element, kAXValueAttribute) as? String {
                let full = Self.clean(String(v.prefix(Self.maxLength)))
                if full != f.lastFull {
                    f.lastFull = full
                    f.keysSinceChange = 0
                    observe(f, Self.region(full, baseline: f.baseline))
                    return
                }
                // Value never moves while keys go in: a decoy input (Google Docs, xterm.js). Rebuild from keys.
                if f.keysSinceChange < 8 { return }
            }
            f.useKeys = true
        }
        observe(f, f.keys)
    }

    private func apply(_ k: KeyStroke, to f: LiveField) {
        if k.flags.contains(.command) || k.flags.contains(.control) { return }
        switch k.keyCode {
        case 51: // delete
            if k.flags.contains(.option) {
                f.keys = f.keys.replacingOccurrences(of: "\\S*\\s*$", with: "", options: .regularExpression)
            } else if !f.keys.isEmpty { f.keys.removeLast() }
        case 36, 76: f.keys += "\n"
        case 48: f.keys += "\t"
        case 53, 115, 116, 117, 119, 121, 123, 124, 125, 126: return // esc, nav keys, fwd delete, arrows
        default:
            guard let c = k.chars, !c.isEmpty,
                  c.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value) })
            else { return }
            f.keys += c
            f.keysSinceChange += 1
        }
        if f.keys.count > Self.maxLength { f.keys = String(f.keys.suffix(Self.maxLength)) }
    }

    /// Big drops are the moment text gets lost, so the version before the drop is saved as a "cliff".
    private func observe(_ f: LiveField, _ v: String) {
        guard v != f.text else { return }
        let prev = f.text
        if prev.count >= 20 && v.count < prev.count / 2 {
            idle?.cancel()
            persist(f, prev, cliff: true)
            if v.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
                // Box was cleared (sent, submitted or lost): next text here is a new entry.
                fields.removeAll { $0 === f }
                if current === f { current = nil }
                return
            }
        }
        f.text = v
        idle?.cancel()
        let work = DispatchWorkItem { [weak self, weak f] in
            guard let self, let f else { return }
            self.persist(f, f.text, cliff: false)
        }
        idle = work
        q.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func persist(_ f: LiveField, _ t: String, cliff: Bool) {
        guard t.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else { return }
        if t == f.snapText {
            if cliff, !f.snapCliff, let id = f.snapID, let s = f.sessionID {
                store.markCliff(id, session: s)
                f.snapCliff = true
            }
            return
        }
        let sid = f.sessionID ?? store.createSession(f.ctx)
        f.sessionID = sid
        // Keep growing the same version while only the tail changes; start a new one every 5 min or on real edits.
        if let id = f.snapID, !f.snapCliff, Date().timeIntervalSince(f.snapAt) < 300,
           t.commonPrefix(with: f.snapText).count >= f.snapText.count - 20 {
            store.replaceSnapshot(id, session: sid, ctx: f.ctx, text: t, cliff: cliff)
        } else {
            f.snapID = store.addSnapshot(session: sid, ctx: f.ctx, text: t, cliff: cliff)
            f.snapAt = Date()
        }
        f.snapText = t
        f.snapCliff = cliff
    }
}

// MARK: - Clipboard

final class ClipboardWatcher {
    private let store: Store
    private let isPaused: () -> Bool
    private let limit: () -> Int
    private var lastCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    init(store: Store, isPaused: @escaping () -> Bool, limit: @escaping () -> Int) {
        self.store = store; self.isPaused = isPaused; self.limit = limit
    }

    func start() {
        // macOS has no pasteboard-changed notification; polling changeCount is the standard approach.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// Copy from inside keypsake without re-recording it.
    func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastCount = pb.changeCount
    }

    private func tick() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        guard !isPaused() else { return }
        let types = Set(pb.types?.map(\.rawValue) ?? [])
        // nspasteboard.org markers: password managers flag secrets as concealed/transient.
        if !types.isDisjoint(with: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                                    "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"]) { return }
        guard let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let ctx = Source.frontmost() ?? SourceContext(app: "Unknown app", bundle: nil, window: "", domain: nil)
        if let b = ctx.bundle, Source.secrets.contains(b) { return }
        store.addClip(text: String(text.prefix(200_000)), ctx: ctx, limit: limit())
    }
}
