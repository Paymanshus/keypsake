import AppKit
import Combine
import SwiftUI

final class AppState: ObservableObject {
    enum Tab { case typed, copied }
    enum Nav { case up, down, enter, delete }

    @Published var tab: Tab = .typed
    @Published var query = ""
    @Published var trusted = AXIsProcessTrusted()
    @Published var flash: Int64?
    @Published var focusSearch = 0
    @Published var paused = UserDefaults.standard.bool(forKey: "paused") {
        didSet { UserDefaults.standard.set(paused, forKey: "paused"); onPause?(paused) }
    }
    let nav = PassthroughSubject<Nav, Never>()
    var onPause: ((Bool) -> Void)?
    var copyText: (String) -> Void = { _ in }
    var prune: () -> Void = {}
    var openSettings: () -> Void = {}

    func copy(_ text: String, id: Int64) {
        copyText(text)
        flash = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if self.flash == id { self.flash = nil } }
    }
}

/// Clicks on content never drag the window; the header provides its own drag area.
final class ContentHost<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var store: Store!
    private let state = AppState()
    private var window: NSWindow!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var capture: TypedCapture!
    private var clipboard: ClipboardWatcher!
    private var timers: [Timer] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        #if DEBUG
        Diff.selfCheck()
        #endif
        if Demo.on { try? FileManager.default.removeItem(at: Store.supportDir) }
        if Demo.dark { NSApp.appearance = NSAppearance(named: .darkAqua) }
        do { store = try Store() } catch {
            let alert = NSAlert()
            alert.messageText = "keypsake can't open its encrypted history"
            alert.informativeText = "The encryption key in your Keychain couldn't be read (\(error)). Nothing was recorded or deleted. Allow keychain access and open keypsake again."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        clipboard = ClipboardWatcher(store: store, isPaused: { [unowned self] in state.paused }, limit: { Prefs.clipLimit })
        capture = TypedCapture(store: store, isPaused: { [unowned self] in state.paused })
        state.copyText = { [unowned self] in clipboard.write($0) }
        state.prune = { [unowned self] in store.prune(retentionDays: Prefs.retentionDays, clipLimit: Prefs.clipLimit) }
        state.onPause = { [unowned self] _ in updateStatusIcon() }
        state.openSettings = { [unowned self] in showSettings() }

        buildMainMenu()
        buildStatusItem()
        buildWindow()
        if Demo.on {
            store.seedDemo(); state.trusted = true; showWindow()
            Snapper.run(window: window, settings: { [unowned self] in showSettings(); return settingsWindow }, state: state)
            return
        }
        registerHotkeys()
        NotificationCenter.default.addObserver(forName: .shortcutsChanged, object: nil, queue: .main) { [unowned self] _ in registerHotkeys() }

        clipboard.start()
        state.prune()
        timers.append(Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [unowned self] _ in state.prune() })
        waitForAccessibility()
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Accessibility
    private func waitForAccessibility() {
        if AXIsProcessTrusted() { state.trusted = true; capture.start(); return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [unowned self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            state.trusted = true
            capture.start()
        }
        timers.append(t)
    }

    // MARK: Windows
    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "keypsake"
        window.backgroundColor = Theme.nsGround
        window.minSize = NSSize(width: 680, height: 420)
        window.isMovable = false // header drag area moves it; see WindowDragArea
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = ContentHost(rootView: MainView().environmentObject(store).environmentObject(state))
        window.center()
        window.setFrameAutosaveName("main")
        placeTrafficLights()
    }

    /// Center the traffic lights on the 52pt header. A toolbar would do this but swallows clicks on the header.
    private func placeTrafficLights() {
        guard let close = window.standardWindowButton(.closeButton), let container = close.superview?.superview else { return }
        let height: CGFloat = 52
        container.frame = NSRect(x: container.frame.minX, y: window.frame.height - height,
                                 width: container.frame.width, height: height)
        for (i, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let b = window.standardWindowButton(type) else { continue }
            b.setFrameOrigin(NSPoint(x: 20 + CGFloat(i) * 23, y: (height - b.frame.height) / 2))
        }
    }

    func windowDidResize(_ notification: Notification) { placeTrafficLights() }
    func windowDidExitFullScreen(_ notification: Notification) { placeTrafficLights() }
    func windowDidBecomeKey(_ notification: Notification) { placeTrafficLights() }

    @objc func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func toggleWindow() {
        if window.isKeyWindow && NSApp.isActive {
            window.orderOut(nil)
            NSApp.hide(nil)
        } else {
            showWindow()
            state.focusSearch += 1
        }
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = "Settings"
            w.backgroundColor = Theme.nsGround
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: SettingsView().environmentObject(store).environmentObject(state))
            w.contentView = host
            w.setContentSize(host.fittingSize)
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func togglePause() { state.paused.toggle() }

    // MARK: Hotkeys
    private func registerHotkeys() {
        HotKeys.shared.register(1, Prefs.shortcut("shortcut.open", .openDefault)) { [unowned self] in toggleWindow() }
        HotKeys.shared.register(2, Prefs.shortcut("shortcut.pause", .pauseDefault)) { [unowned self] in state.paused.toggle() }
    }

    // MARK: Menu bar
    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Glyphs.menuBar()
        statusItem.button?.toolTip = "keypsake"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        statusItem?.button?.appearsDisabled = state.paused
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "Open keypsake", action: #selector(showWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let pause = NSMenuItem(title: state.paused ? "Resume recording" : "Pause recording", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        if !state.trusted {
            menu.addItem(.separator())
            let warn = NSMenuItem(title: "Typing isn't recorded: turn on Accessibility", action: #selector(showWindow), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit keypsake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: "About keypsake", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let settings = app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide keypsake", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(.separator())
        app.addItem(withTitle: "Quit keypsake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let winItem = NSMenuItem()
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = win
        main.addItem(winItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
