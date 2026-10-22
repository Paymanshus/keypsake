import AppKit

/// Word-level comparison between two versions, rendered as plain prose:
/// added words get a carbon highlight, removed words stay in place struck through in amber.
enum Diff {
    struct Result {
        let text: NSAttributedString
        let added: Int
        let removed: Int
    }

    /// Words and the whitespace between them, so the text reassembles exactly.
    static func tokens(_ s: String) -> [Substring] {
        var out: [Substring] = []
        var start = s.startIndex
        var inSpace: Bool?
        for i in s.indices {
            let space = s[i].isWhitespace
            if let cur = inSpace, cur != space {
                out.append(s[start..<i])
                start = i
            }
            inSpace = space
        }
        if start < s.endIndex { out.append(s[start...]) }
        return out
    }

    static func compare(old: String, new: String, base: [NSAttributedString.Key: Any]) -> Result? {
        let a = tokens(old), b = tokens(new)
        guard a.count + b.count < 40_000 else { return nil } // ponytail: diff is O(n·d); skip giant texts
        let diff = b.difference(from: a)
        var removedAt = Set<Int>(), insertedAt = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let o, _, _): removedAt.insert(o)
            case .insert(let o, _, _): insertedAt.insert(o)
            }
        }

        var added = base
        added[.backgroundColor] = Theme.nsCarbon.withAlphaComponent(0.18)
        var removed = base
        removed[.foregroundColor] = Theme.nsCliff
        removed[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        removed[.strikethroughColor] = Theme.nsCliff

        let out = NSMutableAttributedString()
        var i = 0, j = 0, addedWords = 0, removedWords = 0
        while i < a.count || j < b.count {
            if i < a.count, removedAt.contains(i) {
                let t = a[i]
                if !t.allSatisfy(\.isWhitespace) {
                    out.append(NSAttributedString(string: String(t), attributes: removed))
                    out.append(NSAttributedString(string: " ", attributes: base))
                    removedWords += 1
                }
                i += 1
            } else if j < b.count, insertedAt.contains(j) {
                let t = b[j]
                let ws = t.allSatisfy(\.isWhitespace)
                // Spaces between two added words are highlighted too, so an added phrase reads as one block.
                let joined = ws && !t.contains("\n") && insertedAt.contains(j + 1)
                out.append(NSAttributedString(string: String(t), attributes: ws && !joined ? base : added))
                if !ws { addedWords += 1 }
                j += 1
            } else {
                if j < b.count { out.append(NSAttributedString(string: String(b[j]), attributes: base)) }
                i += 1; j += 1
            }
        }
        return Result(text: out, added: addedWords, removed: removedWords)
    }

    static func summary(_ r: Result) -> String {
        func words(_ n: Int) -> String { n == 1 ? "1 word" : "\(n) words" }
        switch (r.added, r.removed) {
        case (0, 0): return "Same words as the version before"
        case (_, 0): return "\(words(r.added)) added"
        case (0, _): return "\(words(r.removed)) removed"
        default: return "\(words(r.added)) added, \(r.removed) removed"
        }
    }

    #if DEBUG
    static func selfCheck() {
        let base: [NSAttributedString.Key: Any] = [:]
        let r = compare(old: "the quick brown fox", new: "the slow brown fox jumps", base: base)!
        assert(r.added == 2 && r.removed == 1, "diff counts")
        assert(TypedCapture.region("hello big world", baseline: "hello world") == "big ", "region middle")
        assert(TypedCapture.region("note\nnew line", baseline: "note\n") == "new line", "region append")
        assert(TypedCapture.region("abc", baseline: "") == "abc", "region empty baseline")
        assert(TypedCapture.clean("\u{FFFC}jp.yaml") == "jp.yaml", "clean placeholder")
    }
    #endif
}
