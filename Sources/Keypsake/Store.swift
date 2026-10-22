import Foundation
import CryptoKit
import Security
import SQLite3

// MARK: - Models

struct SourceContext {
    var app: String
    var bundle: String?
    var window: String
    var domain: String?
}

struct SessionItem: Identifiable, Equatable {
    let id: Int64
    var created: Date
    var updated: Date
    var app: String
    var bundle: String?
    var window: String
    var domain: String?
    var text: String       // latest snapshot
    var title: String { domain ?? app }
}

struct Snapshot: Identifiable, Equatable {
    let id: Int64
    let created: Date
    let length: Int
    var cliff: Bool
    let text: String
}

struct Clip: Identifiable, Equatable {
    let id: Int64
    let created: Date
    let app: String
    let bundle: String?
    let domain: String?
    let text: String
}

// MARK: - Encryption at rest (AES-GCM, key in the login Keychain)

enum Vault {
    struct KeychainError: Error { let status: OSStatus }

    /// Developer ID builds keep the key in the Keychain: their signature (Team ID) is stable, so no prompts.
    /// Local self-signed builds get a new keychain identity on every build, which would prompt each time,
    /// so they move the key once into a file only this user can read.
    static func loadKey() throws -> SymmetricKey {
        if Demo.on { return SymmetricKey(size: .bits256) } // throwaway: demo data is rebuilt each launch
        guard teamID == nil else { return try keychainKey() }
        let file = Store.supportDir.appendingPathComponent(".local-key")
        if let d = try? Data(contentsOf: file), d.count == 32 { return SymmetricKey(data: d) }
        let key = try keychainKey() // last prompt: picks up the key existing history was encrypted with
        try key.withUnsafeBytes { Data($0) }.write(to: file, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return key
    }

    private static var teamID: String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func keychainKey() throws -> SymmetricKey {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.keypsake.app",
            kSecAttrAccount as String: "database-key",
        ]
        var q = base
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecSuccess, let d = out as? Data, d.count == 32 { return SymmetricKey(data: d) }
        // Any failure other than "not there yet" must stop us: minting a new key would orphan existing data.
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        let key = SymmetricKey(size: .bits256)
        var add = base
        add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        return key
    }
}

// MARK: - SQLite

private let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLite {
    private var db: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw NSError(domain: "sqlite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Can't open database at \(path)"])
        }
    }

    func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }

    @discardableResult
    func run(_ sql: String, _ args: [Any?] = []) -> Int64 {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(st) }
        bind(st, args)
        sqlite3_step(st)
        return sqlite3_last_insert_rowid(db)
    }

    func query(_ sql: String, _ args: [Any?] = [], _ row: (Row) -> Void) {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        bind(st, args)
        while sqlite3_step(st) == SQLITE_ROW { row(Row(st: st)) }
    }

    private func bind(_ st: OpaquePointer?, _ args: [Any?]) {
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case let v as Int64: sqlite3_bind_int64(st, idx, v)
            case let v as Int: sqlite3_bind_int64(st, idx, Int64(v))
            case let v as Bool: sqlite3_bind_int64(st, idx, v ? 1 : 0)
            case let v as Double: sqlite3_bind_double(st, idx, v)
            case let v as String: sqlite3_bind_text(st, idx, v, -1, TRANSIENT)
            case let v as Data: v.withUnsafeBytes { _ = sqlite3_bind_blob(st, idx, $0.baseAddress, Int32(v.count), TRANSIENT) }
            default: sqlite3_bind_null(st, idx)
            }
        }
    }

    struct Row {
        let st: OpaquePointer?
        func int(_ i: Int32) -> Int64 { sqlite3_column_int64(st, i) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(st, i) }
        func string(_ i: Int32) -> String? { sqlite3_column_text(st, i).map { String(cString: $0) } }
        func data(_ i: Int32) -> Data? {
            guard let p = sqlite3_column_blob(st, i) else { return nil }
            return Data(bytes: p, count: Int(sqlite3_column_bytes(st, i)))
        }
    }
}

// MARK: - Store

/// DB calls are synchronous and thread-safe (FULLMUTEX); published state only changes on main.
final class Store: ObservableObject {
    @Published private(set) var sessions: [SessionItem] = []
    @Published private(set) var clips: [Clip] = []

    let db: SQLite
    private let key: SymmetricKey

    static var supportDir: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Demo.on ? "keypsake-demo" : "keypsake", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    init() throws {
        key = try Vault.loadKey()
        let path = Store.supportDir.appendingPathComponent("keypsake.sqlite").path
        db = try SQLite(path: path)
        db.exec("""
        PRAGMA journal_mode=WAL;
        PRAGMA foreign_keys=ON;
        CREATE TABLE IF NOT EXISTS sessions(id INTEGER PRIMARY KEY, created REAL, updated REAL, app TEXT, bundle TEXT, window BLOB, domain BLOB);
        CREATE TABLE IF NOT EXISTS snapshots(id INTEGER PRIMARY KEY, session INTEGER REFERENCES sessions(id) ON DELETE CASCADE, created REAL, length INTEGER, cliff INTEGER, body BLOB);
        CREATE INDEX IF NOT EXISTS snapshots_session ON snapshots(session);
        CREATE TABLE IF NOT EXISTS clips(id INTEGER PRIMARY KEY, created REAL, app TEXT, bundle TEXT, domain BLOB, body BLOB);
        """)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        reload()
    }

    // MARK: crypto helpers
    private func seal(_ s: String?) -> Data? {
        guard let s else { return nil }
        return try? AES.GCM.seal(Data(s.utf8), using: key).combined
    }
    private func open(_ d: Data?) -> String? {
        guard let d, let box = try? AES.GCM.SealedBox(combined: d), let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return String(decoding: plain, as: UTF8.self)
    }

    // MARK: loading
    func reload() {
        var s: [SessionItem] = []
        db.query("""
        SELECT s.id, s.created, s.updated, s.app, s.bundle, s.window, s.domain, n.body
        FROM sessions s JOIN snapshots n ON n.id = (SELECT max(id) FROM snapshots WHERE session = s.id)
        ORDER BY s.updated DESC
        """) { r in
            s.append(SessionItem(id: r.int(0), created: Date(timeIntervalSince1970: r.double(1)),
                                 updated: Date(timeIntervalSince1970: r.double(2)), app: r.string(3) ?? "",
                                 bundle: r.string(4), window: open(r.data(5)) ?? "", domain: open(r.data(6)),
                                 text: open(r.data(7)) ?? ""))
        }
        var c: [Clip] = []
        db.query("SELECT id, created, app, bundle, domain, body FROM clips ORDER BY id DESC") { r in
            c.append(Clip(id: r.int(0), created: Date(timeIntervalSince1970: r.double(1)), app: r.string(2) ?? "",
                          bundle: r.string(3), domain: open(r.data(4)), text: open(r.data(5)) ?? ""))
        }
        onMain { self.sessions = s; self.clips = c }
    }

    func snapshots(for session: Int64) -> [Snapshot] {
        var out: [Snapshot] = []
        db.query("SELECT id, created, length, cliff, body FROM snapshots WHERE session = ? ORDER BY id", [session]) { r in
            out.append(Snapshot(id: r.int(0), created: Date(timeIntervalSince1970: r.double(1)),
                                length: Int(r.int(2)), cliff: r.int(3) != 0, text: open(r.data(4)) ?? ""))
        }
        return out
    }

    // MARK: typed text writes (called from the capture queue)
    func createSession(_ ctx: SourceContext) -> Int64 {
        let now = Date().timeIntervalSince1970
        return db.run("INSERT INTO sessions(created, updated, app, bundle, window, domain) VALUES(?,?,?,?,?,?)",
                      [now, now, ctx.app, ctx.bundle, seal(ctx.window), seal(ctx.domain)])
    }

    func addSnapshot(session: Int64, ctx: SourceContext, text: String, cliff: Bool) -> Int64 {
        let now = Date()
        let id = db.run("INSERT INTO snapshots(session, created, length, cliff, body) VALUES(?,?,?,?,?)",
                        [session, now.timeIntervalSince1970, text.count, cliff, seal(text)])
        touch(session: session, ctx: ctx, text: text, at: now)
        trimSnapshots(session: session)
        return id
    }

    func replaceSnapshot(_ id: Int64, session: Int64, ctx: SourceContext, text: String, cliff: Bool) {
        let now = Date()
        db.run("UPDATE snapshots SET created = ?, length = ?, cliff = ?, body = ? WHERE id = ?",
               [now.timeIntervalSince1970, text.count, cliff, seal(text), id])
        touch(session: session, ctx: ctx, text: text, at: now)
    }

    func markCliff(_ id: Int64, session: Int64) {
        db.run("UPDATE snapshots SET cliff = 1 WHERE id = ?", [id])
        onMain { if let i = self.sessions.firstIndex(where: { $0.id == session }) { self.sessions[i].updated = Date() } }
    }

    private func touch(session: Int64, ctx: SourceContext, text: String, at now: Date) {
        db.run("UPDATE sessions SET updated = ? WHERE id = ?", [now.timeIntervalSince1970, session])
        onMain {
            var item = self.sessions.first(where: { $0.id == session })
                ?? SessionItem(id: session, created: now, updated: now, app: ctx.app, bundle: ctx.bundle,
                               window: ctx.window, domain: ctx.domain, text: text)
            item.updated = now
            item.text = text
            self.sessions.removeAll { $0.id == session }
            self.sessions.insert(item, at: 0)
        }
    }

    /// ponytail: cap of 60 versions per text box; oldest non-cliff versions go first.
    private func trimSnapshots(session: Int64) {
        db.run("""
        DELETE FROM snapshots WHERE id IN (
          SELECT id FROM snapshots WHERE session = ? AND cliff = 0 ORDER BY id
          LIMIT max(0, (SELECT count(*) FROM snapshots WHERE session = ?) - 60))
        """, [session, session])
    }

    // MARK: clipboard writes
    func addClip(text: String, ctx: SourceContext, limit: Int) {
        let now = Date()
        // Same text again: move it to the top instead of keeping a duplicate.
        let dupes = clips.filter { $0.text == text }.map(\.id)
        for id in dupes { db.run("DELETE FROM clips WHERE id = ?", [id]) }
        let id = db.run("INSERT INTO clips(created, app, bundle, domain, body) VALUES(?,?,?,?,?)",
                        [now.timeIntervalSince1970, ctx.app, ctx.bundle, seal(ctx.domain), seal(text)])
        db.run("DELETE FROM clips WHERE id NOT IN (SELECT id FROM clips ORDER BY id DESC LIMIT ?)", [limit])
        let clip = Clip(id: id, created: now, app: ctx.app, bundle: ctx.bundle, domain: ctx.domain, text: text)
        onMain {
            self.clips.removeAll { dupes.contains($0.id) }
            self.clips.insert(clip, at: 0)
            if self.clips.count > limit { self.clips.removeLast(self.clips.count - limit) }
        }
    }

    // MARK: deletion
    func deleteSession(_ id: Int64) {
        db.run("DELETE FROM sessions WHERE id = ?", [id])
        onMain { self.sessions.removeAll { $0.id == id } }
    }

    func deleteClip(_ id: Int64) {
        db.run("DELETE FROM clips WHERE id = ?", [id])
        onMain { self.clips.removeAll { $0.id == id } }
    }

    func deleteAll() {
        db.exec("DELETE FROM snapshots; DELETE FROM sessions; DELETE FROM clips; VACUUM;")
        onMain { self.sessions = []; self.clips = [] }
    }

    func prune(retentionDays: Int, clipLimit: Int) {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400).timeIntervalSince1970
        db.run("DELETE FROM sessions WHERE updated < ?", [cutoff])
        db.run("DELETE FROM clips WHERE created < ?", [cutoff])
        db.run("DELETE FROM clips WHERE id NOT IN (SELECT id FROM clips ORDER BY id DESC LIMIT ?)", [clipLimit])
        reload()
    }

    private func onMain(_ f: @escaping () -> Void) {
        Thread.isMainThread ? f() : DispatchQueue.main.async(execute: f)
    }
}
