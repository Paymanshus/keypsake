import AppKit
import SwiftUI

// MARK: - Shell

struct MainView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Header()
            Theme.rule.frame(height: 1)
            if state.tab == .typed {
                if !state.trusted { PermissionBanner() }
                TypedPane()
            } else {
                CopiedPane()
            }
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.ground)
        .background(keyboardShortcuts)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("") { state.tab = .typed }.keyboardShortcut("[", modifiers: .command)
            Button("") { state.tab = .copied }.keyboardShortcut("]", modifiers: .command)
            Button("") { state.focusSearch += 1 }.keyboardShortcut("f", modifiers: .command)
            Button("") { state.nav.send(.delete) }.keyboardShortcut(.delete, modifiers: .command)
            Button("") {
                if state.query.isEmpty { NSApp.keyWindow?.orderOut(nil) } else { state.query = "" }
            }.keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}

struct Header: View {
    @EnvironmentObject var state: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("keypsake")
                .font(Theme.display(22))
                .padding(.trailing, 28)
            tab("Typed", .typed)
            tab("Copied", .copied).padding(.leading, 18)
            Spacer(minLength: 16)
            search
            rec.padding(.leading, 14)
            Button { state.openSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
            }
            .buttonStyle(QuietButton(outlined: false))
            .padding(.leading, 4)
            .help("Settings (⌘,)")
        }
        .padding(.leading, 104)
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(WindowDragArea()) // only empty header space moves the window
    }

    private func tab(_ label: String, _ t: AppState.Tab) -> some View {
        let on = state.tab == t
        return Button { state.tab = t } label: {
            Text(label)
                .font(Theme.bodyMedium(12.5))
                .foregroundStyle(on ? Theme.ink : Theme.inkFaint)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) { Rectangle().fill(on ? Theme.carbon : .clear).frame(height: 2) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
    }

    private var search: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
            TextField(state.tab == .typed ? "Search typed text" : "Search copies", text: $state.query)
                .textFieldStyle(.plain)
                .font(Theme.body(12.5))
                .focused($searchFocused)
                .onKeyPress(.upArrow) { state.nav.send(.up); return .handled }
                .onKeyPress(.downArrow) { state.nav.send(.down); return .handled }
                .onKeyPress(.return) { state.nav.send(.enter); return .handled }
            if !state.query.isEmpty {
                Button { state.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 230, height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.wash))
        .onChange(of: state.focusSearch) { searchFocused = true }
    }

    private var rec: some View {
        Button { state.paused.toggle() } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(state.paused ? Color.clear : Theme.carbon)
                    .overlay(Circle().stroke(state.paused ? Theme.inkFaint : Theme.carbon, lineWidth: 1.2))
                    .frame(width: 7, height: 7)
                Text(state.paused ? "paused" : "rec")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(state.paused ? Theme.inkFaint : Theme.inkSoft)
            }
            .frame(minWidth: 48, alignment: .leading)
        }
        .buttonStyle(QuietButton())
        .help(state.paused ? "Resume recording (⌃⌥P)" : "Pause recording (⌃⌥P)")
    }
}

struct PermissionBanner: View {
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Turn on Accessibility to keep what you type").font(Theme.bodyMedium(12.5))
                Text("Clipboard history works without it. Switched on already but still seeing this? Click Fix, then switch keypsake on again.")
                    .font(Theme.body(11.5)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button("Already on? Fix it") { Permissions.reset() }
                .buttonStyle(QuietButton())
                .help("Clears the old entry so this copy of keypsake can be switched on")
            Button("Open Accessibility settings") { Permissions.request() }
                .buttonStyle(Pill(prominent: true))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.carbon.opacity(0.07))
        .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
    }
}

struct EmptyNote: View {
    let line: String
    var sub: String?
    var body: some View {
        VStack(spacing: 8) {
            Text(line).font(Theme.display(24))
            if let sub { Text(sub).font(Theme.body(12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Typed

struct TypedPane: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: AppState
    @AppStorage("retentionDays") private var retention = 30
    @State private var selection: Int64?
    @State private var snaps: [Snapshot] = []
    @State private var version: Int64?

    private var items: [SessionItem] {
        let q = state.query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.sessions }
        return store.sessions.filter {
            $0.text.lowercased().contains(q) || $0.title.lowercased().contains(q)
                || $0.window.lowercased().contains(q) || $0.app.lowercased().contains(q)
        }
    }

    var body: some View {
        let list = items
        let current = list.first { $0.id == selection } ?? list.first
        Group {
            if store.sessions.isEmpty {
                EmptyNote(line: "Type anywhere. It shows up here.",
                          sub: "Whatever you type into a text box, in any app, is kept for \(retention) days.")
            } else if list.isEmpty {
                EmptyNote(line: "Nothing matches “\(state.query)”.")
            } else {
                HStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(list) { item in
                                    SessionRow(item: item, selected: item.id == current?.id,
                                               copied: state.flash == item.id) { state.copy(item.text, id: item.id) }
                                        .id(item.id)
                                        .onTapGesture { selection = item.id }
                                        .contextMenu {
                                            Button("Copy latest text") { state.copy(item.text, id: item.id) }
                                            Button("Delete") { store.deleteSession(item.id) }
                                        }
                                }
                            }
                        }
                        .onChange(of: selection) { if let s = selection { proxy.scrollTo(s) } }
                    }
                    .frame(width: 310)
                    Theme.rule.frame(width: 1)
                    if let current {
                        SessionDetail(item: current, snaps: snaps, version: $version,
                                      copied: state.flash == current.id, copy: { copyVersion(current) })
                    }
                }
                .task(id: "\(current?.id ?? 0)-\(current?.updated.timeIntervalSince1970 ?? 0)") { load(current) }
                .onReceive(state.nav) { handle($0, list: list, current: current) }
            }
        }
    }

    private func load(_ item: SessionItem?) {
        guard let item else { snaps = []; return }
        let fresh = store.snapshots(for: item.id)
        if fresh.first?.id != snaps.first?.id || !fresh.contains(where: { $0.id == version }) {
            version = Self.defaultVersion(fresh)
        }
        snaps = fresh
    }

    /// If the latest version is much shorter than the longest, text was probably lost: preselect the longest.
    static func defaultVersion(_ s: [Snapshot]) -> Int64? {
        guard let last = s.last, let longest = s.max(by: { $0.length < $1.length }) else { return nil }
        return last.length < longest.length / 2 ? longest.id : last.id
    }

    private func copyVersion(_ item: SessionItem) {
        let text = snaps.first { $0.id == version }?.text ?? item.text
        state.copy(text, id: item.id)
    }

    private func handle(_ nav: AppState.Nav, list: [SessionItem], current: SessionItem?) {
        guard state.tab == .typed, let current, let i = list.firstIndex(of: current) else { return }
        switch nav {
        case .up: selection = list[max(i - 1, 0)].id
        case .down: selection = list[min(i + 1, list.count - 1)].id
        case .enter: copyVersion(current)
        case .delete: store.deleteSession(current.id)
        }
    }
}

struct SessionRow: View {
    let item: SessionItem
    let selected: Bool
    let copied: Bool
    let copy: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            SourceIcon(bundle: item.bundle, domain: item.domain)
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(Theme.display(16.5))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if hover || copied {
                        Button(action: copy) {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .labelStyle(.titleAndIcon)
                                .font(Theme.mono(10))
                                .foregroundStyle(copied ? Theme.carbon : Theme.inkSoft)
                        }
                        .buttonStyle(QuietButton(height: 20))
                        .help("Copy latest text")
                    } else {
                        Text(Stamp.short(item.updated)).font(Theme.mono(10)).foregroundStyle(Theme.inkFaint)
                    }
                }
                .frame(height: 20)
                if !item.window.isEmpty && item.window != item.title {
                    Text(item.window).font(Theme.body(11)).foregroundStyle(Theme.inkFaint).lineLimit(1)
                }
                Text(preview)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
                    .lineSpacing(2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.wash : Color.clear)
        .overlay(alignment: .leading) { if selected { Theme.carbon.frame(width: 2) } }
        .overlay(alignment: .bottom) { Theme.rule.opacity(0.5).frame(height: 1).padding(.leading, 45) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private var preview: String {
        String(item.text.prefix(400)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

struct SessionDetail: View {
    let item: SessionItem
    let snaps: [Snapshot]
    @Binding var version: Int64?
    let copied: Bool
    let copy: () -> Void
    @AppStorage("showChanges") private var showChanges = true
    @State private var diff: (id: Int64, result: Diff.Result?)?

    private var current: Snapshot? { snaps.first { $0.id == version } ?? snaps.last }
    private var previous: Snapshot? {
        guard let c = current, let i = snaps.firstIndex(of: c), i > 0 else { return nil }
        return snaps[i - 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    SourceIcon(bundle: item.bundle, domain: item.domain).frame(width: 22, height: 22)
                    Text(item.title)
                        .font(Theme.display(26))
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Button(action: copy) {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                            .font(Theme.bodyMedium(12))
                            .foregroundStyle(copied ? Theme.carbon : Theme.ink)
                    }
                    .buttonStyle(QuietButton(height: 28))
                    .help("Copy this version (Return)")
                }
                Text(meta).font(Theme.mono(10.5)).foregroundStyle(Theme.inkFaint).lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Theme.rule.frame(height: 1)
            if previous != nil { changesBar }
            ReadOnlyText(text: shownText)
                .task(id: "\(current?.id ?? 0)-\(previous?.id ?? 0)") { computeDiff() }
            Theme.rule.frame(height: 1)

            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    step(-1, "chevron.left", "Older version")
                    Ribbon(snaps: snaps, selected: current?.id) { version = $0 }
                    step(1, "chevron.right", "Newer version")
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(versionLabel).font(Theme.mono(10.5)).foregroundStyle(Theme.inkSoft)
                    if let cliff = cliffLabel { Text(cliff).font(Theme.mono(10.5)).foregroundStyle(Theme.cliff) }
                }
                Spacer(minLength: 8)
                Button(copied ? "Copied" : "Copy this version", action: copy)
                    .buttonStyle(Pill(prominent: true))
                    .help("Return")
            }
            .padding(.horizontal, 26)
            .frame(height: 68)
        }
    }

    private func step(_ delta: Int, _ icon: String, _ help: String) -> some View {
        let i = current.flatMap { snaps.firstIndex(of: $0) } ?? 0
        let target = i + delta
        let enabled = snaps.indices.contains(target)
        return Button { if enabled { version = snaps[target].id } } label: {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Theme.ink : Theme.inkFaint.opacity(0.5))
        }
        .buttonStyle(QuietButton(outlined: enabled, height: 28))
        .disabled(!enabled)
        .help(help)
    }

    /// "Text" shows the version clean; "Changes" shows it against the version before, in plain words.
    private var changesBar: some View {
        HStack(spacing: 14) {
            Chips(options: [(0, "Text"), (1, "Changes")],
                  value: Binding(get: { showChanges ? 1 : 0 }, set: { showChanges = $0 == 1 }))
            if showChanges, let r = diff?.result {
                Text(Diff.summary(r)).font(Theme.body(11.5)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    Text("added").font(Theme.body(11)).padding(.horizontal, 3).background(Theme.carbon.opacity(0.18))
                    Text("removed").font(Theme.body(11)).strikethrough(color: Theme.cliff).foregroundStyle(Theme.cliff)
                }
            } else if showChanges {
                Text("Too long to compare word by word").font(Theme.body(11.5)).foregroundStyle(Theme.inkFaint)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 26)
        .frame(height: 40)
        .overlay(alignment: .bottom) { Theme.rule.opacity(0.5).frame(height: 1) }
    }

    private var shownText: NSAttributedString {
        if showChanges, previous != nil, let d = diff, d.id == current?.id, let r = d.result { return r.text }
        return ReadOnlyText.plain(current?.text ?? item.text)
    }

    private func computeDiff() {
        guard let c = current, let p = previous else { diff = nil; return }
        diff = (c.id, Diff.compare(old: p.text, new: c.text, base: ReadOnlyText.baseAttributes))
    }

    private var meta: String {
        var parts: [String] = []
        if !item.window.isEmpty && item.window != item.title { parts.append(item.window) }
        if item.domain != nil { parts.append(item.app) }
        parts.append(Stamp.short(current?.created ?? item.updated))
        parts.append(Stamp.count(current?.length ?? item.text.count))
        return parts.joined(separator: "  ·  ")
    }

    private var versionLabel: String {
        guard let c = current, let i = snaps.firstIndex(of: c) else { return "" }
        return snaps.count == 1 ? "1 version" : "version \(i + 1) of \(snaps.count)  ·  \(Stamp.short(c.created))"
    }

    private var cliffLabel: String? {
        guard let c = current, c.cliff, let i = snaps.firstIndex(of: c) else { return nil }
        if i + 1 < snaps.count { return "dropped to \(Stamp.count(snaps[i + 1].length)) right after this" }
        return "box was cleared right after this"
    }
}

/// Text length per version over time. Cliff versions (right before text vanished) show in amber.
struct Ribbon: View {
    let snaps: [Snapshot]
    let selected: Int64?
    let pick: (Int64) -> Void

    var body: some View {
        let top = CGFloat(max(snaps.map(\.length).max() ?? 1, 1))
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(snaps.suffix(30)) { s in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(s))
                    .frame(width: 7, height: max(4, 30 * CGFloat(s.length) / top))
                    .frame(width: 11, height: 34, alignment: .bottom)
                    .contentShape(Rectangle())
                    .pointingHand()
                    .onTapGesture { pick(s.id) }
                    .help("\(Stamp.short(s.created))  ·  \(Stamp.count(s.length))")
            }
        }
        .frame(height: 34)
    }

    private func color(_ s: Snapshot) -> Color {
        if s.id == selected { return s.cliff ? Theme.cliff : Theme.ink }
        return s.cliff ? Theme.cliff.opacity(0.55) : Theme.ghost
    }
}

// MARK: - Copied

struct CopiedPane: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: AppState
    @AppStorage("clipLimit") private var clipLimit = 50
    @State private var selection: Int64?

    private var items: [Clip] {
        let q = state.query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.clips }
        return store.clips.filter { $0.text.lowercased().contains(q) || $0.app.lowercased().contains(q) || ($0.domain ?? "").contains(q) }
    }

    var body: some View {
        let list = items
        let current = list.first { $0.id == selection } ?? list.first
        Group {
            if store.clips.isEmpty {
                EmptyNote(line: "Copy anything. It lands here.", sub: "Your last \(clipLimit) copies are kept. Passwords from password managers are skipped.")
            } else if list.isEmpty {
                EmptyNote(line: "Nothing matches “\(state.query)”.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, clip in
                                ClipRow(clip: clip, index: i, selected: clip.id == current?.id, copied: state.flash == clip.id)
                                    .id(clip.id)
                                    .onTapGesture {
                                        selection = clip.id
                                        state.copy(clip.text, id: clip.id)
                                    }
                                    .contextMenu {
                                        Button("Copy") { state.copy(clip.text, id: clip.id) }
                                        Button("Delete") { store.deleteClip(clip.id) }
                                    }
                            }
                        }
                    }
                    .onChange(of: selection) { if let s = selection { proxy.scrollTo(s) } }
                }
                .background(numberShortcuts(list))
                .onReceive(state.nav) { handle($0, list: list, current: current) }
            }
        }
    }

    private func numberShortcuts(_ list: [Clip]) -> some View {
        Group {
            ForEach(0..<min(9, list.count), id: \.self) { i in
                Button("") { state.copy(list[i].text, id: list[i].id); selection = list[i].id }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func handle(_ nav: AppState.Nav, list: [Clip], current: Clip?) {
        guard state.tab == .copied, let current, let i = list.firstIndex(of: current) else { return }
        switch nav {
        case .up: selection = list[max(i - 1, 0)].id
        case .down: selection = list[min(i + 1, list.count - 1)].id
        case .enter: state.copy(current.text, id: current.id)
        case .delete: store.deleteClip(current.id)
        }
    }
}

struct ClipRow: View {
    let clip: Clip
    let index: Int
    let selected: Bool
    let copied: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SourceIcon(bundle: clip.bundle, domain: clip.domain)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(selected ? clip.text : oneLine)
                    .font(Theme.body(13))
                    .lineLimit(selected ? 10 : 1)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(copied ? "Copied" : "\(clip.domain ?? clip.app)  ·  \(Stamp.short(clip.created))  ·  \(Stamp.count(clip.text.count))")
                    .font(Theme.mono(10))
                    .foregroundStyle(copied ? Theme.carbon : Theme.inkFaint)
            }
            if index < 9 {
                Text("⌘\(index + 1)").font(Theme.mono(10)).foregroundStyle(Theme.inkFaint).padding(.top, 2)
            }
        }
        .padding(.vertical, 11)
        .padding(.leading, 20)
        .padding(.trailing, 18)
        .background(copied ? Theme.carbon.opacity(0.12) : selected ? Theme.wash : Color.clear)
        .overlay(alignment: .leading) { if selected { Theme.carbon.frame(width: 2) } }
        .overlay(alignment: .bottom) { Theme.rule.opacity(0.5).frame(height: 1).padding(.leading, 48) }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.18), value: copied)
    }

    private var oneLine: String {
        String(clip.text.prefix(300)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// MARK: - Pieces

struct SourceIcon: View {
    let bundle: String?
    let domain: String?
    @ObservedObject private var icons = Icons.shared

    var body: some View {
        if let fav = icons.favicon(domain) {
            Image(nsImage: fav).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        } else if let app = icons.app(bundle) {
            Image(nsImage: app).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.wash)
        }
    }
}

struct Pill: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyMedium(12))
            .foregroundStyle(prominent ? Theme.ground : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(prominent ? Theme.carbon : Theme.wash))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
            .pointingHand()
    }
}

/// Quiet control: hairline outline at rest, light fill on hover, pointing-hand cursor. Reads as clickable without shouting.
struct QuietButton: ButtonStyle {
    var outlined = true
    var height: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View { QuietBody(configuration: configuration, outlined: outlined, height: height) }

    private struct QuietBody: View {
        let configuration: Configuration
        let outlined: Bool
        let height: CGFloat
        @State private var hover = false
        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .frame(minWidth: height, minHeight: height)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Theme.ghost.opacity(0.45) : hover ? Theme.wash : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(outlined ? Theme.rule : Color.clear, lineWidth: 1))
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .pointingHand()
        }
    }
}

extension View {
    func pointingHand() -> some View {
        onHover { inside in (inside ? NSCursor.pointingHand : NSCursor.arrow).set() }
    }
}

/// Empty header space drags the window (double-click zooms). Everything else in the window stays put.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        // The window itself is not movable (so tabs and buttons never drag it); this view moves it by hand.
        override func mouseDown(with event: NSEvent) {
            guard let w = window else { return }
            if event.clickCount == 2 { w.performZoom(nil); return }
            let start = NSEvent.mouseLocation, origin = w.frame.origin
            while let e = w.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), e.type == .leftMouseDragged {
                let now = NSEvent.mouseLocation
                w.setFrameOrigin(NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y))
            }
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Accessibility permission. macOS ties a grant to the app's exact signature; a stale entry can show "on" yet not apply.
enum Permissions {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func request() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(settingsURL)
    }

    /// Removes keypsake's old entry so the running copy registers fresh, then reopens the prompt.
    static func reset() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.keypsake.app"]
        try? p.run()
        p.waitUntilExit()
        request()
    }
}

/// Read-only, selectable, fast for long text.
struct ReadOnlyText: NSViewRepresentable {
    let text: NSAttributedString

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 5
        return [.font: Theme.nsBody(14), .foregroundColor: Theme.nsInk, .paragraphStyle: para]
    }
    static func plain(_ s: String) -> NSAttributedString { NSAttributedString(string: s, attributes: baseAttributes) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 22, height: 20)
        tv.selectedTextAttributes = [.backgroundColor: Theme.nsCarbon.withAlphaComponent(0.22)]
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        guard let storage = tv.textStorage, !storage.isEqual(to: text) else { return }
        let sameString = storage.string == text.string
        storage.setAttributedString(text)
        if !sameString { tv.scrollToBeginningOfDocument(nil) }
    }
}

enum Glyphs {
    /// Menu bar mark: a keycap (outline skirt, solid top surface) with a "k" legend cut out, like the app icon.
    static func menuBar() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            let skirt = NSBezierPath(roundedRect: NSRect(x: 1.6, y: 1.6, width: 14.8, height: 14.8), xRadius: 3.6, yRadius: 3.6)
            skirt.lineWidth = 1.2
            skirt.stroke()
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 3.6, y: 3, width: 10.8, height: 10), xRadius: 2.6, yRadius: 2.6).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let font = NSFont(name: "Redaction-Regular", size: 10.5) ?? .systemFont(ofSize: 9.5, weight: .semibold)
            let k = NSAttributedString(string: "k", attributes: [.font: font, .foregroundColor: NSColor.black])
            let size = k.size()
            k.draw(at: NSPoint(x: 9 - size.width / 2, y: 8 - size.height / 2 - 0.4))
            return true
        }
        img.isTemplate = true
        return img
    }
}
