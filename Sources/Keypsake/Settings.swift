import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @AppStorage("retentionDays") private var retention = 30
    @AppStorage("clipLimit") private var clipLimit = 50
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings").font(Theme.display(28)).padding(.bottom, 22)

            section("Recording") {
                row("Record typing and copies") {
                    Toggle("", isOn: Binding(get: { !state.paused }, set: { state.paused = !$0 }))
                        .toggleStyle(.switch).tint(Theme.carbon).labelsHidden()
                }
                row("Open at login", note: loginError) {
                    Toggle("", isOn: $openAtLogin).toggleStyle(.switch).tint(Theme.carbon).labelsHidden()
                        .onChange(of: openAtLogin) { setLogin(openAtLogin) }
                }
                row("Accessibility", note: state.trusted ? nil : "Needed to keep what you type. Already on? Use Fix.") {
                    if state.trusted {
                        Text("On").font(Theme.mono(11)).foregroundStyle(Theme.inkSoft)
                    } else {
                        HStack(spacing: 8) {
                            Button("Fix") { Permissions.reset() }.buttonStyle(QuietButton(height: 30))
                                .help("Already switched on? This clears the old entry so you can switch it on again")
                            Button("Turn on") { Permissions.request() }.buttonStyle(Pill(prominent: true))
                        }
                    }
                }
            }

            section("Keep") {
                row("Typed text for") {
                    Chips(options: [(7, "7d"), (30, "30d"), (90, "90d"), (365, "1y")], value: $retention)
                        .onChange(of: retention) { state.prune() }
                }
                row("Copies to keep") {
                    Chips(options: [(25, "25"), (50, "50"), (100, "100"), (250, "250"), (500, "500")], value: $clipLimit)
                        .onChange(of: clipLimit) { state.prune() }
                }
            }

            section("Shortcuts") {
                row("Open keypsake") { ShortcutRecorder(name: "shortcut.open", fallback: .openDefault) }
                row("Pause or resume recording") { ShortcutRecorder(name: "shortcut.pause", fallback: .pauseDefault) }
            }

            section("Privacy") {
                Text("History is encrypted on this Mac and never leaves it. Password fields and password managers are never recorded. Site icons are fetched from the site itself.")
                    .font(Theme.body(11.5)).foregroundStyle(Theme.inkSoft).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                row("Delete all history") {
                    Button("Delete all") { confirmDelete = true }.buttonStyle(Pill())
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(width: 480)
        .foregroundStyle(Theme.ink)
        .background(Theme.ground)
        .alert("Delete all typed text and copies?", isPresented: $confirmDelete) {
            Button("Delete all", role: .destructive) { store.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription)"
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(Theme.mono(9.5)).tracking(1.2).foregroundStyle(Theme.inkFaint)
                .padding(.bottom, 6)
            content()
        }
        .padding(.bottom, 22)
    }

    private func row<Control: View>(_ label: String, note: String? = nil, @ViewBuilder _ control: () -> Control) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.body(13))
                if let note { Text(note).font(Theme.body(11)).foregroundStyle(Theme.inkFaint) }
            }
            Spacer()
            control()
        }
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) { Theme.rule.opacity(0.6).frame(height: 1) }
    }
}

struct Chips: View {
    let options: [(Int, String)]
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { opt in
                Button { value = opt.0 } label: {
                    Text(opt.1)
                        .font(Theme.monoMedium(10.5))
                        .foregroundStyle(value == opt.0 ? Theme.ground : Theme.inkSoft)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(value == opt.0 ? Theme.carbon : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.wash))
    }
}

struct ShortcutRecorder: View {
    let name: String
    let fallback: Shortcut
    @State private var current: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    init(name: String, fallback: Shortcut) {
        self.name = name
        self.fallback = fallback
        _current = State(initialValue: Prefs.shortcut(name, fallback))
    }

    var body: some View {
        Button { recording ? stop() : start() } label: {
            Text(recording ? "Press keys…" : current.display)
                .font(Theme.monoMedium(11))
                .foregroundStyle(recording ? Theme.carbon : Theme.ink)
                .padding(.horizontal, 10)
                .frame(minWidth: 70, minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(recording ? Theme.carbon.opacity(0.14) : Theme.wash))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil } // Esc cancels
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.subtracting(.shift).isEmpty else { NSSound.beep(); return nil }
            let key = e.keyCode == 49 ? "Space" : (e.charactersIgnoringModifiers ?? "").uppercased()
            guard !key.isEmpty else { NSSound.beep(); return nil }
            let s = Shortcut(keyCode: UInt32(e.keyCode), mods: mods.rawValue, key: key)
            Prefs.setShortcut(name, s)
            current = s
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
