//! SQLite history with every text field sealed by AES-256-GCM.
//! Schema and blob format are identical to the macOS build (see COMPATIBILITY.md).

use crate::text;
use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use anyhow::{Context, Result};
use rand_core::{OsRng, RngCore};
use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use std::path::Path;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

/// Where a piece of text came from. `bundle` is the macOS bundle id or the Windows exe path.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct SourceContext {
    pub app: String,
    pub bundle: Option<String>,
    pub window: String,
    pub domain: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct SessionItem {
    pub id: i64,
    pub created: f64,
    pub updated: f64,
    pub app: String,
    pub bundle: Option<String>,
    pub window: String,
    pub domain: Option<String>,
    /// Latest snapshot.
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Snapshot {
    pub id: i64,
    pub created: f64,
    pub length: i64,
    pub cliff: bool,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Clip {
    pub id: i64,
    pub created: f64,
    pub app: String,
    pub bundle: Option<String>,
    pub domain: Option<String>,
    pub text: String,
}

/// What changed, so the UI knows what to refetch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Change {
    Sessions,
    Clips,
}

pub fn now() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

/// AES-256-GCM, stored as nonce(12) ‖ ciphertext ‖ tag(16): the same bytes as CryptoKit's `SealedBox.combined`.
pub struct Cipher(Aes256Gcm);

impl Cipher {
    pub fn new(key: &[u8; 32]) -> Self {
        Cipher(Aes256Gcm::new(key.into()))
    }

    pub fn seal(&self, s: &str) -> Vec<u8> {
        let mut nonce = [0u8; 12];
        OsRng.fill_bytes(&mut nonce);
        let ct = self.0.encrypt(Nonce::from_slice(&nonce), s.as_bytes()).expect("AES-GCM seal");
        let mut out = nonce.to_vec();
        out.extend(ct);
        out
    }

    pub fn open(&self, d: &[u8]) -> Option<String> {
        if d.len() < 28 {
            return None;
        }
        let plain = self.0.decrypt(Nonce::from_slice(&d[..12]), &d[12..]).ok()?;
        Some(String::from_utf8_lossy(&plain).into_owned())
    }
}

pub fn new_key() -> [u8; 32] {
    let mut k = [0u8; 32];
    OsRng.fill_bytes(&mut k);
    k
}

const SCHEMA: &str = "
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS sessions(id INTEGER PRIMARY KEY, created REAL, updated REAL, app TEXT, bundle TEXT, window BLOB, domain BLOB);
CREATE TABLE IF NOT EXISTS snapshots(id INTEGER PRIMARY KEY, session INTEGER REFERENCES sessions(id) ON DELETE CASCADE, created REAL, length INTEGER, cliff INTEGER, body BLOB);
CREATE INDEX IF NOT EXISTS snapshots_session ON snapshots(session);
CREATE TABLE IF NOT EXISTS clips(id INTEGER PRIMARY KEY, created REAL, app TEXT, bundle TEXT, domain BLOB, body BLOB);
";

/// ponytail: cap of 60 versions per text box; oldest non-cliff versions go first.
pub const MAX_VERSIONS: i64 = 60;

struct Inner {
    db: Connection,
    sessions: Vec<SessionItem>,
    clips: Vec<Clip>,
}

/// Thread-safe: every call takes one lock. Lists are cached in memory (newest first) for the UI.
pub struct Store {
    inner: Mutex<Inner>,
    cipher: Cipher,
    on_change: Box<dyn Fn(Change) + Send + Sync>,
}

impl Store {
    pub fn open(path: &Path, key: &[u8; 32]) -> Result<Store> {
        let db = Connection::open(path).with_context(|| format!("Can't open database at {}", path.display()))?;
        Self::with_connection(db, key)
    }

    pub fn in_memory(key: &[u8; 32]) -> Result<Store> {
        Self::with_connection(Connection::open_in_memory()?, key)
    }

    fn with_connection(db: Connection, key: &[u8; 32]) -> Result<Store> {
        db.execute_batch(SCHEMA)?;
        let store = Store {
            inner: Mutex::new(Inner { db, sessions: vec![], clips: vec![] }),
            cipher: Cipher::new(key),
            on_change: Box::new(|_| {}),
        };
        store.reload();
        Ok(store)
    }

    pub fn set_on_change(&mut self, f: impl Fn(Change) + Send + Sync + 'static) {
        self.on_change = Box::new(f);
    }

    fn seal(&self, s: Option<&str>) -> Option<Vec<u8>> {
        s.map(|s| self.cipher.seal(s))
    }
    fn open_blob(&self, d: Option<Vec<u8>>) -> Option<String> {
        d.and_then(|d| self.cipher.open(&d))
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    // MARK: loading

    pub fn reload(&self) {
        let mut g = self.lock();
        let sessions = self.load_sessions(&g.db).unwrap_or_default();
        let clips = self.load_clips(&g.db).unwrap_or_default();
        g.sessions = sessions;
        g.clips = clips;
        drop(g);
        (self.on_change)(Change::Sessions);
        (self.on_change)(Change::Clips);
    }

    fn load_sessions(&self, db: &Connection) -> rusqlite::Result<Vec<SessionItem>> {
        let mut st = db.prepare(
            "SELECT s.id, s.created, s.updated, s.app, s.bundle, s.window, s.domain, n.body
             FROM sessions s JOIN snapshots n ON n.id = (SELECT max(id) FROM snapshots WHERE session = s.id)
             ORDER BY s.updated DESC",
        )?;
        let rows = st.query_map([], |r| {
            Ok(SessionItem {
                id: r.get(0)?,
                created: r.get(1)?,
                updated: r.get(2)?,
                app: r.get::<_, Option<String>>(3)?.unwrap_or_default(),
                bundle: r.get(4)?,
                window: self.open_blob(r.get(5)?).unwrap_or_default(),
                domain: self.open_blob(r.get(6)?),
                text: self.open_blob(r.get(7)?).unwrap_or_default(),
            })
        })?;
        rows.collect()
    }

    fn load_clips(&self, db: &Connection) -> rusqlite::Result<Vec<Clip>> {
        let mut st = db.prepare("SELECT id, created, app, bundle, domain, body FROM clips ORDER BY id DESC")?;
        let rows = st.query_map([], |r| {
            Ok(Clip {
                id: r.get(0)?,
                created: r.get(1)?,
                app: r.get::<_, Option<String>>(2)?.unwrap_or_default(),
                bundle: r.get(3)?,
                domain: self.open_blob(r.get(4)?),
                text: self.open_blob(r.get(5)?).unwrap_or_default(),
            })
        })?;
        rows.collect()
    }

    pub fn sessions(&self) -> Vec<SessionItem> {
        self.lock().sessions.clone()
    }

    pub fn clips(&self) -> Vec<Clip> {
        self.lock().clips.clone()
    }

    pub fn snapshots(&self, session: i64) -> Vec<Snapshot> {
        let g = self.lock();
        let Ok(mut st) =
            g.db.prepare("SELECT id, created, length, cliff, body FROM snapshots WHERE session = ? ORDER BY id")
        else {
            return vec![];
        };
        let rows = st.query_map([session], |r| {
            Ok(Snapshot {
                id: r.get(0)?,
                created: r.get(1)?,
                length: r.get(2)?,
                cliff: r.get::<_, i64>(3)? != 0,
                text: self.open_blob(r.get(4)?).unwrap_or_default(),
            })
        });
        rows.map(|rows| rows.filter_map(|r| r.ok()).collect()).unwrap_or_default()
    }

    // MARK: typed text writes (called from the capture thread)

    pub fn create_session(&self, ctx: &SourceContext) -> i64 {
        let now = now();
        let g = self.lock();
        let _ = g.db.execute(
            "INSERT INTO sessions(created, updated, app, bundle, window, domain) VALUES(?,?,?,?,?,?)",
            params![now, now, ctx.app, ctx.bundle, self.seal(Some(&ctx.window)), self.seal(ctx.domain.as_deref())],
        );
        g.db.last_insert_rowid()
    }

    pub fn add_snapshot(&self, session: i64, ctx: &SourceContext, text: &str, cliff: bool) -> i64 {
        let now = now();
        let mut g = self.lock();
        let _ = g.db.execute(
            "INSERT INTO snapshots(session, created, length, cliff, body) VALUES(?,?,?,?,?)",
            params![session, now, text::len(text) as i64, cliff, self.cipher.seal(text)],
        );
        let id = g.db.last_insert_rowid();
        Self::touch(&mut g, session, ctx, text, now);
        let _ = g.db.execute(
            "DELETE FROM snapshots WHERE id IN (
               SELECT id FROM snapshots WHERE session = ?1 AND cliff = 0 ORDER BY id
               LIMIT max(0, (SELECT count(*) FROM snapshots WHERE session = ?1) - ?2))",
            params![session, MAX_VERSIONS],
        );
        drop(g);
        (self.on_change)(Change::Sessions);
        id
    }

    pub fn replace_snapshot(&self, id: i64, session: i64, ctx: &SourceContext, text: &str, cliff: bool) {
        let now = now();
        let mut g = self.lock();
        let _ = g.db.execute(
            "UPDATE snapshots SET created = ?, length = ?, cliff = ?, body = ? WHERE id = ?",
            params![now, text::len(text) as i64, cliff, self.cipher.seal(text), id],
        );
        Self::touch(&mut g, session, ctx, text, now);
        drop(g);
        (self.on_change)(Change::Sessions);
    }

    pub fn mark_cliff(&self, id: i64, session: i64) {
        let mut g = self.lock();
        let _ = g.db.execute("UPDATE snapshots SET cliff = 1 WHERE id = ?", [id]);
        if let Some(s) = g.sessions.iter_mut().find(|s| s.id == session) {
            s.updated = now();
        }
        drop(g);
        (self.on_change)(Change::Sessions);
    }

    fn touch(g: &mut Inner, session: i64, ctx: &SourceContext, text: &str, now: f64) {
        let _ = g.db.execute("UPDATE sessions SET updated = ? WHERE id = ?", params![now, session]);
        let mut item = match g.sessions.iter().position(|s| s.id == session) {
            Some(i) => g.sessions.remove(i),
            None => SessionItem {
                id: session,
                created: now,
                updated: now,
                app: ctx.app.clone(),
                bundle: ctx.bundle.clone(),
                window: ctx.window.clone(),
                domain: ctx.domain.clone(),
                text: String::new(),
            },
        };
        item.updated = now;
        item.text = text.to_string();
        g.sessions.insert(0, item);
    }

    // MARK: clipboard writes

    pub fn add_clip(&self, text: &str, ctx: &SourceContext, limit: usize) {
        let now = now();
        let mut g = self.lock();
        // Same text again: move it to the top instead of keeping a duplicate.
        let dupes: Vec<i64> = g.clips.iter().filter(|c| c.text == text).map(|c| c.id).collect();
        for id in &dupes {
            let _ = g.db.execute("DELETE FROM clips WHERE id = ?", [id]);
        }
        let _ = g.db.execute(
            "INSERT INTO clips(created, app, bundle, domain, body) VALUES(?,?,?,?,?)",
            params![now, ctx.app, ctx.bundle, self.seal(ctx.domain.as_deref()), self.cipher.seal(text)],
        );
        let id = g.db.last_insert_rowid();
        let _ = g.db.execute(
            "DELETE FROM clips WHERE id NOT IN (SELECT id FROM clips ORDER BY id DESC LIMIT ?)",
            [limit as i64],
        );
        g.clips.retain(|c| !dupes.contains(&c.id));
        g.clips.insert(
            0,
            Clip {
                id,
                created: now,
                app: ctx.app.clone(),
                bundle: ctx.bundle.clone(),
                domain: ctx.domain.clone(),
                text: text.to_string(),
            },
        );
        g.clips.truncate(limit);
        drop(g);
        (self.on_change)(Change::Clips);
    }

    // MARK: deletion

    pub fn delete_session(&self, id: i64) {
        let mut g = self.lock();
        let _ = g.db.execute("DELETE FROM sessions WHERE id = ?", [id]);
        g.sessions.retain(|s| s.id != id);
        drop(g);
        (self.on_change)(Change::Sessions);
    }

    pub fn delete_clip(&self, id: i64) {
        let mut g = self.lock();
        let _ = g.db.execute("DELETE FROM clips WHERE id = ?", [id]);
        g.clips.retain(|c| c.id != id);
        drop(g);
        (self.on_change)(Change::Clips);
    }

    pub fn delete_all(&self) {
        let mut g = self.lock();
        let _ = g.db.execute_batch("DELETE FROM snapshots; DELETE FROM sessions; DELETE FROM clips; VACUUM;");
        g.sessions.clear();
        g.clips.clear();
        drop(g);
        (self.on_change)(Change::Sessions);
        (self.on_change)(Change::Clips);
    }

    pub fn prune(&self, retention_days: u32, clip_limit: usize) {
        let cutoff = now() - retention_days as f64 * 86400.0;
        {
            let g = self.lock();
            let _ = g.db.execute("DELETE FROM sessions WHERE updated < ?", [cutoff]);
            let _ = g.db.execute("DELETE FROM clips WHERE created < ?", [cutoff]);
            let _ = g.db.execute(
                "DELETE FROM clips WHERE id NOT IN (SELECT id FROM clips ORDER BY id DESC LIMIT ?)",
                [clip_limit as i64],
            );
        }
        self.reload();
    }

    // MARK: demo seeding

    /// Moves a snapshot back in time (demo data only).
    pub fn backdate_snapshot(&self, id: i64, created: f64) {
        let _ = self.lock().db.execute("UPDATE snapshots SET created = ? WHERE id = ?", params![created, id]);
    }

    /// Moves a session or clip back in time (demo data only). Call `reload()` afterwards.
    pub fn backdate_session(&self, id: i64, created: f64, updated: f64) {
        let _ = self
            .lock()
            .db
            .execute("UPDATE sessions SET created = ?, updated = ? WHERE id = ?", params![created, updated, id]);
    }

    pub fn backdate_clip(&self, id: i64, created: f64) {
        let _ = self.lock().db.execute("UPDATE clips SET created = ? WHERE id = ?", params![created, id]);
    }

    pub fn latest_clip_id(&self) -> Option<i64> {
        self.lock().db.query_row("SELECT max(id) FROM clips", [], |r| r.get(0)).optional().ok().flatten().flatten()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ctx() -> SourceContext {
        SourceContext {
            app: "Notepad".into(),
            bundle: Some("C:\\Windows\\notepad.exe".into()),
            window: "notes.txt".into(),
            domain: None,
        }
    }

    #[test]
    fn cipher_round_trip_and_format() {
        let c = Cipher::new(&[7u8; 32]);
        let blob = c.seal("hello");
        assert_eq!(blob.len(), 12 + 5 + 16);
        assert_eq!(c.open(&blob).as_deref(), Some("hello"));
        assert!(Cipher::new(&[8u8; 32]).open(&blob).is_none());
    }

    #[test]
    fn sessions_and_snapshots() {
        let s = Store::in_memory(&[1u8; 32]).unwrap();
        let sid = s.create_session(&ctx());
        let a = s.add_snapshot(sid, &ctx(), "first", false);
        s.replace_snapshot(a, sid, &ctx(), "first draft", false);
        s.add_snapshot(sid, &ctx(), "second", true);
        let snaps = s.snapshots(sid);
        assert_eq!(snaps.len(), 2);
        assert_eq!(snaps[0].text, "first draft");
        assert_eq!(snaps[0].length, 11);
        assert!(snaps[1].cliff);
        assert_eq!(s.sessions()[0].text, "second");
        s.reload();
        assert_eq!(s.sessions()[0].window, "notes.txt");
        assert_eq!(s.sessions()[0].text, "second");
        s.delete_session(sid);
        assert!(s.snapshots(sid).is_empty());
    }

    #[test]
    fn versions_are_capped_keeping_cliffs() {
        let s = Store::in_memory(&[1u8; 32]).unwrap();
        let sid = s.create_session(&ctx());
        s.add_snapshot(sid, &ctx(), "cliff", true);
        for i in 0..70 {
            s.add_snapshot(sid, &ctx(), &format!("v{i}"), false);
        }
        let snaps = s.snapshots(sid);
        assert_eq!(snaps.len(), 60);
        assert_eq!(snaps[0].text, "cliff");
        assert_eq!(snaps.last().unwrap().text, "v69");
    }

    #[test]
    fn clips_dedupe_and_limit() {
        let s = Store::in_memory(&[1u8; 32]).unwrap();
        s.add_clip("a", &ctx(), 3);
        s.add_clip("b", &ctx(), 3);
        s.add_clip("a", &ctx(), 3);
        assert_eq!(s.clips().iter().map(|c| c.text.as_str()).collect::<Vec<_>>(), ["a", "b"]);
        s.add_clip("c", &ctx(), 3);
        s.add_clip("d", &ctx(), 3);
        assert_eq!(s.clips().len(), 3);
        s.reload();
        assert_eq!(s.clips().iter().map(|c| c.text.as_str()).collect::<Vec<_>>(), ["d", "c", "a"]);
    }

    #[test]
    fn prune_drops_old() {
        let s = Store::in_memory(&[1u8; 32]).unwrap();
        let sid = s.create_session(&ctx());
        s.add_snapshot(sid, &ctx(), "old", false);
        s.backdate_session(sid, now() - 40.0 * 86400.0, now() - 40.0 * 86400.0);
        let keep = s.create_session(&ctx());
        s.add_snapshot(keep, &ctx(), "new", false);
        s.prune(30, 50);
        assert_eq!(s.sessions().len(), 1);
        assert_eq!(s.sessions()[0].id, keep);
    }

    #[test]
    fn known_answer_in_combined_layout() {
        // NIST GCM test case 13: zero key, zero nonce, empty plaintext. CryptoKit's `combined` is nonce ‖ ct ‖ tag.
        let mut blob = vec![0u8; 12];
        blob.extend([0x53, 0x0f, 0x8a, 0xfb, 0xc7, 0x45, 0x36, 0xb9, 0xa9, 0x63, 0xb4, 0xf1, 0xc4, 0xcb, 0x73, 0x8b]);
        assert_eq!(Cipher::new(&[0u8; 32]).open(&blob).as_deref(), Some(""));
    }

    #[test]
    fn reads_rows_written_outside_the_store() {
        let key = [3u8; 32];
        let db = Connection::open_in_memory().unwrap();
        db.execute_batch(SCHEMA).unwrap();
        let c = Cipher::new(&key);
        db.execute(
            "INSERT INTO clips(created, app, bundle, domain, body) VALUES(1, 'Safari', 'com.apple.Safari', ?, ?)",
            params![c.seal("github.com"), c.seal("copied")],
        )
        .unwrap();
        let s = Store::with_connection(db, &key).unwrap();
        assert_eq!(s.clips()[0].domain.as_deref(), Some("github.com"));
        assert_eq!(s.clips()[0].text, "copied");
    }
}
