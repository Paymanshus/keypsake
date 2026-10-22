import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var mods: UInt   // NSEvent.ModifierFlags raw value
    var key: String  // display character

    var display: String {
        let f = NSEvent.ModifierFlags(rawValue: mods)
        return (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "")
            + (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "") + key
    }

    var carbonMods: UInt32 {
        let f = NSEvent.ModifierFlags(rawValue: mods)
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static let openDefault = Shortcut(keyCode: UInt32(kVK_ANSI_K), mods: NSEvent.ModifierFlags([.control, .option]).rawValue, key: "K")
    static let pauseDefault = Shortcut(keyCode: UInt32(kVK_ANSI_P), mods: NSEvent.ModifierFlags([.control, .option]).rawValue, key: "P")
}

enum Prefs {
    static let d = UserDefaults.standard
    static var retentionDays: Int { d.object(forKey: "retentionDays") as? Int ?? 30 }
    static var clipLimit: Int { d.object(forKey: "clipLimit") as? Int ?? 50 }

    static func shortcut(_ name: String, _ fallback: Shortcut) -> Shortcut {
        guard let data = d.data(forKey: name), let s = try? JSONDecoder().decode(Shortcut.self, from: data) else { return fallback }
        return s
    }
    static func setShortcut(_ name: String, _ s: Shortcut) {
        d.set(try? JSONEncoder().encode(s), forKey: name)
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }
}

extension Notification.Name {
    static let shortcutsChanged = Notification.Name("keypsake.shortcutsChanged")
}

/// Global hotkeys through Carbon: no extra permission needed.
final class HotKeys {
    static let shared = HotKeys()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { HotKeys.shared.handlers[id.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(_ id: UInt32, _ s: Shortcut, _ action: @escaping () -> Void) {
        if let old = refs[id] { UnregisterEventHotKey(old) }
        var ref: EventHotKeyRef?
        RegisterEventHotKey(s.keyCode, s.carbonMods, EventHotKeyID(signature: OSType(0x6B707373), id: id),
                            GetApplicationEventTarget(), 0, &ref)
        refs[id] = ref
        handlers[id] = action
    }
}
