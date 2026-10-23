import AppKit
import SwiftUI

// MARK: - Numbers

/// keypstats, computed from version times and lengths plus each box's longest version.
/// Words typed at a moment = growth in length since the version before, scaled by that box's words-per-char.
struct Stats {
    enum Kind: Int, CaseIterable {
        case quip, sentence, paragraph, sonnet, passage, essay, chapter, novella

        var name: String { "\(self)" }
        var plural: String { self == .passage ? "passages" : name + "s" }
        var withArticle: String { (self == .essay ? "an " : "a ") + name }

        static func of(_ text: String, words: Int) -> Kind {
            let lines = text.split(separator: "\n").filter { !$0.allSatisfy(\.isWhitespace) }.count
            if lines == 14 && (60...220).contains(words) { return .sonnet }
            switch words {
            case ..<8: return .quip
            case ..<31: return .sentence
            case ..<121: return .paragraph
            case ..<401: return .passage
            case ..<1501: return .essay
            case ..<6001: return .chapter
            default: return .novella
            }
        }
    }

    struct App { let name: String; let bundle: String?; let domain: String?; var words: Double }

    var words = 0.0
    var boxes = 0
    var versions = 0
    var saves = 0
    var streak = 0
    var grid: [[Double]] = []          // rows (1 for today, else Mon…Sun) × 24 hours
    var biggest: (item: SessionItem, text: String, words: Int)?
    var kinds: [Kind: Int] = [:]
    var apps: [App] = []
    var favourite: (word: String, count: Int)?
    var fancyCandidates: [String] = []
    var mostVersioned: (item: SessionItem, count: Int)?

    var peak: (row: Int, hour: Int, words: Double)? {
        var best: (Int, Int, Double)?
        for (r, row) in grid.enumerated() { for (h, v) in row.enumerated() where v > (best?.2 ?? 0) { best = (r, h, v) } }
        return best
    }

    static func start(of period: Int, now: Date) -> Date {
        guard period > 0 else { return .distantPast }
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1 - period, to: cal.startOfDay(for: now))!
    }

    static func words(_ text: String) -> [Substring] {
        text.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }
    }

    static func compute(sessions: [SessionItem], marks: [(session: Int64, at: Date, length: Int, cliff: Bool)],
                        longest: [Int64: String], period: Int, now: Date = Date()) -> Stats {
        let cal = Calendar.current
        let start = start(of: period, now: now)
        let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var s = Stats()
        s.grid = Array(repeating: Array(repeating: 0, count: 24), count: period == 1 ? 1 : 7)
        var apps: [String: App] = [:]
        var counts: [String: Int] = [:]
        var days = Set<Date>()

        var i = 0
        while i < marks.count {
            let sid = marks[i].session
            var j = i
            while j < marks.count && marks[j].session == sid { j += 1 }
            let group = marks[i..<j]
            i = j
            days.formUnion(group.map { cal.startOfDay(for: $0.at) })
            guard let item = byID[sid] else { continue }
            let text = longest[sid] ?? item.text
            let tokens = words(text)
            let ratio = Double(tokens.count) / Double(max(group.map(\.length).max() ?? 1, 1))
            var prev = 0, typed = 0.0, inPeriod = false
            for m in group {
                let delta = max(0, m.length - prev)
                prev = m.length
                guard m.at >= start else { continue }
                inPeriod = true
                typed += Double(delta) * ratio
                s.versions += 1
                if m.cliff { s.saves += 1 }
                let row = period == 1 ? 0 : (cal.component(.weekday, from: m.at) + 5) % 7 // Monday first
                s.grid[row][cal.component(.hour, from: m.at)] += Double(delta) * ratio
            }
            guard inPeriod else { continue }
            s.boxes += 1
            s.words += typed
            s.kinds[Kind.of(text, words: tokens.count), default: 0] += 1
            if tokens.count > s.biggest?.words ?? 0 { s.biggest = (item, text, tokens.count) }
            if group.count >= 3 && group.count > s.mostVersioned?.count ?? 0 { s.mostVersioned = (item, group.count) }
            apps[item.title, default: App(name: item.title, bundle: item.bundle, domain: item.domain, words: 0)].words += typed
            for t in tokens { counts[t.lowercased().replacingOccurrences(of: "’", with: "'"), default: 0] += 1 }
        }

        s.apps = apps.values.filter { $0.words >= 1 }.sorted { $0.words > $1.words }
        let plain = counts.filter { $0.key.count >= 3 && $0.key.allSatisfy(\.isLetter) }
        s.favourite = plain.filter { !stopwords.contains($0.key) && $0.value >= 2 }
            .max { ($0.value, $1.key) < ($1.value, $0.key) }
            .map { ($0.key, $0.value) }
        // ponytail: "fanciest" = longest real (spell-checked) word, no frequency list. A word-rarity table would make this "rarest".
        s.fancyCandidates = plain.keys.filter { $0.count >= 7 }.sorted { ($0.count, $1) > ($1.count, $0) }.prefix(40).map { $0 }

        var day = cal.startOfDay(for: now)
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! } // today not over yet
        while days.contains(day) { s.streak += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return s
    }

    /// Main thread: NSSpellChecker isn't thread-safe.
    static func fanciest(_ candidates: [String]) -> String? {
        candidates.first { NSSpellChecker.shared.checkSpelling(of: $0, startingAt: 0).location == NSNotFound }
    }

    static let stopwords: Set<String> = Set("""
    the and for are but not you all any can had her was one our out has him his how its may new now old see two who
    did get let put say she too use that with have this will your from they know want been good much some time very
    when come here just like long make many more only over such take than them well were what into also back then
    there their these those which would could should about after again being below between both down during each
    few further other same through under until while where why because before above off once own most yes yeah okay
    ok i'm it's don't can't i've i'll i'd you're that's there's let's didn't doesn't isn't won't wasn't we're they're
    just really still even thing things think going gonna got way something anything nothing every though thanks
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    #if DEBUG
    static func selfCheck() {
        let now = Date()
        let item = SessionItem(id: 1, created: now, updated: now, app: "Notes", bundle: nil, window: "", domain: nil,
                               text: "")
        let text = "ship it ship it now please ship"
        let marks: [(session: Int64, at: Date, length: Int, cliff: Bool)] = [
            (1, now.addingTimeInterval(-60), text.count / 2, false), (1, now, text.count, true), (9, now, 5, false),
        ]
        let s = compute(sessions: [item], marks: marks, longest: [1: text], period: 1, now: now)
        assert(s.boxes == 1 && s.versions == 2 && s.saves == 1, "stats counts")
        assert(abs(s.words - 7) < 0.01, "stats words: growth scaled to word count")
        assert(s.favourite?.word == "ship" && s.favourite?.count == 3, "stats favourite word")
        assert(s.kinds[.quip] == 1 && s.streak == 1, "stats kind and streak")
        assert(Kind.of(Array(repeating: "a line of verse here", count: 14).joined(separator: "\n"), words: 70) == .sonnet, "sonnet")
    }
    #endif
}

// MARK: - Page

struct StatsPane: View {
    @EnvironmentObject var store: Store
    @AppStorage("statsPeriod") private var period = 7
    @AppStorage("retentionDays") private var retention = 30
    @State private var stats: Stats?
    @State private var fancy: String?
    @State private var ribbon: [Snapshot] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Chips(options: [(1, "Today"), (7, "7 days"), (30, "30 days"), (0, "All")], value: $period)
                Spacer()
                if period == 0 || period > retention {
                    Text("keypsake keeps \(retention) days").font(Theme.mono(10.5)).foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            if let s = stats, s.boxes > 0 {
                ScrollView { page(s).padding(.horizontal, 32).padding(.top, 6).padding(.bottom, 40) }
            } else if stats != nil {
                EmptyNote(line: period == 1 ? "Nothing typed today. Yet." : "Nothing typed here yet.",
                          sub: "Type anywhere and your stats fill in.")
            } else {
                Spacer()
            }
        }
        .task(id: "\(period)-\(store.sessions.count)") { await load() }
    }

    private func load() async {
        let store = store, sessions = store.sessions, period = period
        let s = await Task.detached(priority: .userInitiated) {
            let rows = store.statsRows()
            return Stats.compute(sessions: sessions, marks: rows.marks, longest: rows.longest, period: period)
        }.value
        fancy = Stats.fanciest(s.fancyCandidates)
        ribbon = s.mostVersioned.map { store.snapshots(for: $0.item.id) } ?? []
        stats = s
    }

    private var when: String { [1: "today", 7: "this week", 30: "this month"][period] ?? "lately" }

    @ViewBuilder
    private func page(_ s: Stats) -> some View {
        VStack(alignment: .leading, spacing: 44) {
            hero(s)
            if let p = s.peak { rhythm(s, p) }
            HStack(alignment: .top, spacing: 40) {
                if let b = s.biggest { biggest(b).frame(maxWidth: .infinity, alignment: .leading) }
                if let top = s.apps.first { favouriteApp(top, s).frame(maxWidth: .infinity, alignment: .leading) }
            }
            kinds(s)
            HStack(alignment: .top, spacing: 40) {
                if let f = s.favourite {
                    bigWord("Favourite word", f.word, f.count == 1 ? "once" : "\(f.count.formatted()) times")
                }
                if let fancy { bigWord("Fanciest word", fancy, "\(fancy.count) letters. look at you.") }
            }
            if let v = s.mostVersioned { versioned(v) }
            saves(s)
        }
    }

    // MARK: sections

    private func hero(_ s: Stats) -> some View {
        let pages = Int((s.words / 300).rounded())
        return HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                label("Words typed " + when, on: true)
                Text(Int(s.words).formatted())
                    .font(Theme.display(104))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .padding(.top, 6)
                Text(pages >= 1 ? "about \(pages.formatted()) \(pages == 1 ? "page" : "pages"). keyp going." : "every word counts. keyp going.")
                    .font(Theme.body(13)).opacity(0.8)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 12) {
                tally(s.boxes, "text boxes")
                tally(s.versions, "versions kept")
                tally(s.streak, s.streak == 1 ? "day streak" : "days in a row")
            }
        }
        .foregroundStyle(Theme.ground)
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.carbon))
    }

    private func tally(_ n: Int, _ what: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(n.formatted()).font(Theme.display(28))
            Text(what).font(Theme.mono(10)).opacity(0.75)
        }
    }

    private func rhythm(_ s: Stats, _ p: (row: Int, hour: Int, words: Double)) -> some View {
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let part = Self.partOfDay(p.hour)
        let slot: String = {
            if s.grid.count == 1 { return "in the \(part), \(Self.hour(p.hour))" }
            return "on \(days[p.row]) \(part)\(period == 7 ? "" : "s"), \(Self.hour(p.hour))"
        }()
        let top = s.grid.flatMap { $0 }.max() ?? 1
        return VStack(alignment: .leading, spacing: 18) {
            label("When you type")
            (Text("You were most key-krazy ") + Text(slot).foregroundColor(Theme.carbon)
                + Text(" \(when), with ") + Text("\(Int(p.words).formatted()) words").foregroundColor(Theme.carbon) + Text(" typed."))
                .font(Theme.display(30))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 4) {
                ForEach(s.grid.indices, id: \.self) { r in
                    HStack(spacing: 4) {
                        if s.grid.count > 1 {
                            Text(days[r].prefix(3)).font(Theme.mono(9.5)).foregroundStyle(Theme.inkFaint).frame(width: 30, alignment: .leading)
                        }
                        ForEach(0..<24, id: \.self) { h in
                            let v = s.grid[r][h]
                            RoundedRectangle(cornerRadius: s.grid.count == 1 ? 5 : 3.5, style: .continuous)
                                .fill(v < 1 ? Theme.wash : Theme.carbon.opacity(0.14 + 0.86 * v / top))
                                .frame(height: s.grid.count == 1 ? 64 : 18)
                                .help("\(s.grid.count > 1 ? days[r] + " " : "")\(Self.hour(h))  ·  \(Int(v).formatted()) words")
                        }
                    }
                }
                HStack(spacing: 4) {
                    if s.grid.count > 1 { Color.clear.frame(width: 30, height: 1) }
                    ForEach(0..<24, id: \.self) { h in
                        Text(h % 6 == 0 ? Self.hour(h, short: true) : "")
                            .font(Theme.mono(9.5)).foregroundStyle(Theme.inkFaint)
                            .fixedSize()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func biggest(_ b: (item: SessionItem, text: String, words: Int)) -> some View {
        let kind = Stats.Kind.of(b.text, words: b.words)
        let excerpt = String(b.text.prefix(240)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return VStack(alignment: .leading, spacing: 10) {
            label("Biggest thing you typed")
            Text(kind.withArticle.prefix(1).uppercased() + kind.withArticle.dropFirst() + ".")
                .font(Theme.display(48)).lineLimit(1).minimumScaleFactor(0.6)
            Text("\(b.words.formatted()) words  ·  \(b.item.title)  ·  \(Stamp.short(b.item.updated))")
                .font(Theme.mono(10.5)).foregroundStyle(Theme.inkFaint).lineLimit(1)
            Text(excerpt).font(Theme.body(12.5)).foregroundStyle(Theme.inkSoft).lineSpacing(3).lineLimit(3)
        }
    }

    private func favouriteApp(_ top: Stats.App, _ s: Stats) -> some View {
        let share = { (a: Stats.App) in "\(Int((a.words / max(s.words, 1) * 100).rounded()))%" }
        return VStack(alignment: .leading, spacing: 10) {
            label("Favourite app")
            Text("Your life (and words) is on").font(Theme.body(13)).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 12) {
                SourceIcon(bundle: top.bundle, domain: top.domain).frame(width: 38, height: 38)
                Text(top.name).font(Theme.display(40)).lineLimit(1).minimumScaleFactor(0.5)
            }
            Text("\(share(top)) of your words").font(Theme.mono(10.5)).foregroundStyle(Theme.inkFaint)
            if s.apps.count > 1 {
                HStack(spacing: 14) {
                    ForEach(s.apps.dropFirst().prefix(4), id: \.name) { a in
                        HStack(spacing: 5) {
                            SourceIcon(bundle: a.bundle, domain: a.domain).frame(width: 14, height: 14)
                            Text(share(a)).font(Theme.mono(10)).foregroundStyle(Theme.inkSoft)
                        }
                        .help(a.name)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func kinds(_ s: Stats) -> some View {
        let rows = Stats.Kind.allCases.compactMap { k in s.kinds[k].map { (k, $0) } }
        let top = rows.max { $0.1 < $1.1 }
        let most = rows.map(\.1).max() ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            label("What you type")
            if let top { Text("Mostly \(top.0.plural).").font(Theme.display(34)) }
            VStack(spacing: 7) {
                ForEach(rows, id: \.0) { k, n in
                    HStack(spacing: 14) {
                        Text(k.plural).font(Theme.body(12.5)).fixedSize().frame(width: 104, alignment: .leading)
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(k == top?.0 ? Theme.carbon : Theme.ghost)
                                .frame(width: max(6, g.size.width * CGFloat(n) / CGFloat(most)))
                        }
                        .frame(height: 20)
                        Text(n.formatted()).font(Theme.mono(10.5)).foregroundStyle(Theme.inkSoft).frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func bigWord(_ title: String, _ word: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label(title)
            Text("“\(word)”").font(Theme.display(44)).lineLimit(1).minimumScaleFactor(0.5)
            Text(sub).font(Theme.mono(10.5)).foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func versioned(_ v: (item: SessionItem, count: Int)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Most versioned")
            HStack(spacing: 10) {
                SourceIcon(bundle: v.item.bundle, domain: v.item.domain).frame(width: 24, height: 24)
                Text(v.item.window.isEmpty ? v.item.title : v.item.window).font(Theme.display(30)).lineLimit(1)
            }
            Text("You really went back to this one a lot, huh.").font(Theme.body(13)).foregroundStyle(Theme.inkSoft)
            HStack(alignment: .bottom, spacing: 16) {
                Ribbon(snaps: ribbon, selected: ribbon.last?.id) { _ in }
                Text("\(v.count) versions  ·  \(v.item.title)").font(Theme.mono(10.5)).foregroundStyle(Theme.inkFaint)
            }
            .padding(.top, 4)
        }
    }

    private func saves(_ s: Stats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Saves", color: Theme.cliff)
            (Text("ffs").strikethrough() + Text(" for keyp's sake")).font(Theme.display(44)).foregroundStyle(Theme.cliff)
            Text(s.saves == 0 ? "No close calls \(when). Nice."
                 : "\(s.saves == 1 ? "Once" : "\(s.saves) times"), a box got wiped \(when). keypsake had the version before.")
                .font(Theme.body(13)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cliff.opacity(0.12)))
    }

    private func label(_ s: String, on: Bool = false, color: Color = Theme.inkFaint) -> some View {
        Text(s.uppercased()).font(Theme.mono(9.5)).tracking(1.2)
            .foregroundStyle(on ? AnyShapeStyle(Theme.ground.opacity(0.75)) : AnyShapeStyle(color))
    }

    static func hour(_ h: Int, short: Bool = false) -> String {
        let n = h % 12 == 0 ? 12 : h % 12
        return short ? "\(n)\(h < 12 ? "a" : "p")" : "\(n) \(h < 12 ? "AM" : "PM")"
    }

    static func partOfDay(_ h: Int) -> String {
        switch h {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
    }
}
