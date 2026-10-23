//! Typed-text capture: a port of `TypedCapture` in Capture.swift. The OS layer feeds it keystrokes and
//! answers "what is focused and what does it say"; this decides what gets saved and when.
//!
//! One text box the user is typing into is a `LiveField`. Text comes from the accessibility API when the app
//! exposes it, otherwise it is rebuilt from keystrokes (terminals, canvas editors like Google Docs).
//! Only what was typed this time is kept: text already in the box (a long note) is the baseline and is left out.

use crate::source::{AppRef, Lists};
use crate::store::{SourceContext, Store};
use crate::text::{self, MAX_LENGTH};
use std::time::{Duration, Instant};

/// A keystroke, already mapped from OS key codes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Key {
    /// Printable text the key produced.
    Char(String),
    Backspace,
    /// Option-Delete on macOS, Ctrl+Backspace on Windows.
    DeleteWord,
    Enter,
    Tab,
    /// Esc, arrows, navigation and everything else that doesn't change text.
    Other,
}

#[derive(Debug, Clone)]
pub struct KeyStroke {
    pub app: AppRef,
    pub key: Key,
    /// A shortcut modifier was held (⌘/⌃ on macOS, Ctrl or Win on Windows, but not AltGr).
    pub shortcut: bool,
}

/// A focused text element, as the OS accessibility API sees it.
pub trait Field {
    /// Stable identity while the element lives (UIA RuntimeId on Windows).
    fn id(&self) -> Vec<i32>;
    /// The box's whole text. None if the app doesn't expose it.
    fn value(&self) -> Option<String>;
    /// Insertion point in characters.
    fn caret(&self) -> Option<usize>;
}

pub enum Focus {
    /// A password field: nothing is recorded.
    Secure,
    /// Nothing readable is focused (some Electron/Java apps): track keystrokes per app instead.
    Unreadable,
    Field(Box<dyn Field>),
}

/// What capture needs from the OS.
pub trait Accessibility {
    fn focused(&mut self, app: &AppRef) -> Focus;
    fn context(&mut self, app: &AppRef, focused: Option<&dyn Field>) -> SourceContext;
}

/// Where versions go. `Store` implements it; tests use a recorder.
pub trait Sink {
    fn create_session(&self, ctx: &SourceContext) -> i64;
    fn add_snapshot(&self, session: i64, ctx: &SourceContext, text: &str, cliff: bool) -> i64;
    fn replace_snapshot(&self, id: i64, session: i64, ctx: &SourceContext, text: &str, cliff: bool);
    fn mark_cliff(&self, id: i64, session: i64);
}

impl Sink for Store {
    fn create_session(&self, ctx: &SourceContext) -> i64 {
        Store::create_session(self, ctx)
    }
    fn add_snapshot(&self, session: i64, ctx: &SourceContext, text: &str, cliff: bool) -> i64 {
        Store::add_snapshot(self, session, ctx, text, cliff)
    }
    fn replace_snapshot(&self, id: i64, session: i64, ctx: &SourceContext, text: &str, cliff: bool) {
        Store::replace_snapshot(self, id, session, ctx, text, cliff)
    }
    fn mark_cliff(&self, id: i64, session: i64) {
        Store::mark_cliff(self, id, session)
    }
}

impl<T: Sink + ?Sized> Sink for std::sync::Arc<T> {
    fn create_session(&self, ctx: &SourceContext) -> i64 {
        (**self).create_session(ctx)
    }
    fn add_snapshot(&self, session: i64, ctx: &SourceContext, text: &str, cliff: bool) -> i64 {
        (**self).add_snapshot(session, ctx, text, cliff)
    }
    fn replace_snapshot(&self, id: i64, session: i64, ctx: &SourceContext, text: &str, cliff: bool) {
        (**self).replace_snapshot(id, session, ctx, text, cliff)
    }
    fn mark_cliff(&self, id: i64, session: i64) {
        (**self).mark_cliff(id, session)
    }
}

/// Timings and limits. Keep in step with Capture.swift (see COMPATIBILITY.md).
pub const READ_DELAY: Duration = Duration::from_millis(80);
pub const IDLE_SAVE: Duration = Duration::from_millis(1500);
pub const NEW_VERSION_AFTER: Duration = Duration::from_secs(300);
pub const MAX_FIELDS: usize = 30;
/// Keystrokes with no change in the box's value before it is treated as a decoy input.
pub const DECOY_KEYS: usize = 8;

struct LiveField {
    uid: u64,
    element: Option<Box<dyn Field>>,
    element_id: Vec<i32>,
    pid: u32,
    ctx: SourceContext,
    baseline: String,
    session_id: Option<i64>,
    text: String,
    keys: String,
    use_keys: bool,
    last_full: Option<String>,
    keys_since_change: usize,
    snap_id: Option<i64>,
    snap_text: String,
    snap_cliff: bool,
    snap_at: Option<Instant>,
}

pub struct Tracker<S: Sink> {
    sink: S,
    lists: &'static Lists,
    fields: Vec<LiveField>,
    current: Option<u64>,
    next_uid: u64,
    read_due: Option<Instant>,
    idle_due: Option<(Instant, u64)>,
}

impl<S: Sink> Tracker<S> {
    pub fn new(sink: S, lists: &'static Lists) -> Self {
        Tracker { sink, lists, fields: vec![], current: None, next_uid: 1, read_due: None, idle_due: None }
    }

    pub fn sink(&self) -> &S {
        &self.sink
    }

    /// When `poll` next has work to do.
    pub fn next_deadline(&self) -> Option<Instant> {
        match (self.read_due, self.idle_due.map(|d| d.0)) {
            (Some(a), Some(b)) => Some(a.min(b)),
            (a, b) => a.or(b),
        }
    }

    /// Runs whatever timers are due.
    pub fn poll(&mut self, now: Instant) {
        if self.read_due.is_some_and(|t| t <= now) {
            self.read_due = None;
            if let Some(uid) = self.current {
                self.read(uid, now);
            }
        }
        if let Some((t, uid)) = self.idle_due {
            if t <= now {
                self.idle_due = None;
                if let Some(f) = self.field(uid) {
                    let t = f.text.clone();
                    self.persist(uid, &t, false, now);
                }
            }
        }
    }

    /// Another app came to the front: save the box being left.
    pub fn app_switched(&mut self, now: Instant) {
        self.switch_to(None, now);
    }

    pub fn key(&mut self, k: KeyStroke, ax: &mut dyn Accessibility, now: Instant) {
        if self.lists.is_skipped(&k.app.id) {
            return;
        }
        let pid = k.app.pid;
        let focused = match ax.focused(&k.app) {
            Focus::Secure => return,
            Focus::Unreadable => None,
            Focus::Field(f) => Some(f),
        };
        let element_id = focused.as_ref().map(|f| f.id()).unwrap_or_default();

        let uid = match self.fields.iter().find(|f| f.pid == pid && f.element_id == element_id) {
            Some(f) => f.uid,
            None => {
                let keys_only = focused.is_none() || self.lists.is_keys_only(&k.app.id);
                let ctx = ax.context(&k.app, focused.as_deref());
                let mut f = LiveField {
                    uid: self.next_uid,
                    element: None,
                    element_id,
                    pid,
                    ctx,
                    baseline: String::new(),
                    session_id: None,
                    text: String::new(),
                    keys: String::new(),
                    use_keys: keys_only,
                    last_full: None,
                    keys_since_change: 0,
                    snap_id: None,
                    snap_text: String::new(),
                    snap_cliff: false,
                    snap_at: None,
                };
                self.next_uid += 1;
                if !keys_only {
                    if let Some(v) = focused.as_ref().and_then(|e| e.value()) {
                        let typed = match &k.key {
                            Key::Char(c) => Some(c.as_str()),
                            _ => None,
                        };
                        let caret = focused.as_ref().and_then(|e| e.caret());
                        f.baseline = text::clean(&text::without_just_typed(text::prefix(&v, MAX_LENGTH), typed, caret));
                        f.last_full = Some(f.baseline.clone());
                    }
                }
                f.element = focused;
                let uid = f.uid;
                self.fields.push(f);
                uid
            }
        };
        self.switch_to(Some(uid), now);
        if self.fields.len() > MAX_FIELDS {
            self.fields.remove(0);
        }
        self.apply(&k, uid);

        if k.key == Key::Enter {
            self.read(uid, now); // Return often clears the box: read right away too
        }
        if self.read_due.is_none() {
            self.read_due = Some(now + READ_DELAY);
        }
    }

    fn field(&mut self, uid: u64) -> Option<&mut LiveField> {
        self.fields.iter_mut().find(|f| f.uid == uid)
    }

    fn switch_to(&mut self, uid: Option<u64>, now: Instant) {
        if self.current == uid {
            return;
        }
        if let Some(old) = self.current {
            self.idle_due = None;
            if let Some(f) = self.field(old) {
                let t = f.text.clone();
                self.persist(old, &t, false, now);
            }
        }
        self.current = uid;
    }

    fn read(&mut self, uid: u64, now: Instant) {
        let Some(f) = self.field(uid) else { return };
        if !f.use_keys {
            if let Some(v) = f.element.as_ref().and_then(|e| e.value()) {
                let full = text::clean(text::prefix(&v, MAX_LENGTH));
                if f.last_full.as_deref() != Some(full.as_str()) {
                    let region = text::region(&full, &f.baseline);
                    f.last_full = Some(full);
                    f.keys_since_change = 0;
                    self.observe(uid, region, now);
                    return;
                }
                // Value never moves while keys go in: a decoy input (Google Docs, xterm.js). Rebuild from keys.
                if f.keys_since_change < DECOY_KEYS {
                    return;
                }
            }
            f.use_keys = true;
        }
        let keys = f.keys.clone();
        self.observe(uid, keys, now);
    }

    fn apply(&mut self, k: &KeyStroke, uid: u64) {
        let Some(f) = self.field(uid) else { return };
        if k.shortcut {
            return;
        }
        match &k.key {
            Key::Backspace => {
                f.keys.pop();
            }
            Key::DeleteWord => text::delete_word(&mut f.keys),
            Key::Enter => f.keys.push('\n'),
            Key::Tab => f.keys.push('\t'),
            Key::Other => return,
            Key::Char(c) => {
                if c.is_empty()
                    || !c
                        .chars()
                        .all(|c| c as u32 >= 0x20 && c as u32 != 0x7F && !(0xF700..=0xF8FF).contains(&(c as u32)))
                {
                    return;
                }
                f.keys.push_str(c);
                f.keys_since_change += 1;
            }
        }
        if f.keys.chars().count() > MAX_LENGTH {
            f.keys = text::suffix(&f.keys, MAX_LENGTH).to_string();
        }
    }

    /// Big drops are the moment text gets lost, so the version before the drop is saved as a "cliff".
    fn observe(&mut self, uid: u64, v: String, now: Instant) {
        let Some(f) = self.field(uid) else { return };
        if v == f.text {
            return;
        }
        let prev = f.text.clone();
        let prev_len = text::len(&prev);
        if prev_len >= 20 && text::len(&v) < prev_len / 2 {
            self.idle_due = None;
            self.persist(uid, &prev, true, now);
            if text::trimmed_len(&v) < 3 {
                // Box was cleared (sent, submitted or lost): next text here is a new entry.
                self.fields.retain(|f| f.uid != uid);
                if self.current == Some(uid) {
                    self.current = None;
                }
                return;
            }
        }
        if let Some(f) = self.field(uid) {
            f.text = v;
        }
        self.idle_due = Some((now + IDLE_SAVE, uid));
    }

    fn persist(&mut self, uid: u64, t: &str, cliff: bool, now: Instant) {
        if text::trimmed_len(t) < 3 {
            return;
        }
        let Some(i) = self.fields.iter().position(|f| f.uid == uid) else { return };
        let sink = &self.sink;
        let f = &mut self.fields[i];
        if t == f.snap_text {
            if cliff && !f.snap_cliff {
                if let (Some(id), Some(s)) = (f.snap_id, f.session_id) {
                    sink.mark_cliff(id, s);
                    f.snap_cliff = true;
                }
            }
            return;
        }
        let sid = *f.session_id.get_or_insert_with(|| sink.create_session(&f.ctx));
        // Keep growing the same version while only the tail changes; start a new one every 5 min or on real edits.
        let tail_only = common_prefix_len(t, &f.snap_text) + 20 >= f.snap_text.chars().count();
        let fresh = f.snap_at.is_some_and(|at| now.duration_since(at) < NEW_VERSION_AFTER);
        match f.snap_id {
            Some(id) if !f.snap_cliff && fresh && tail_only => sink.replace_snapshot(id, sid, &f.ctx, t, cliff),
            _ => {
                f.snap_id = Some(sink.add_snapshot(sid, &f.ctx, t, cliff));
                f.snap_at = Some(now);
            }
        }
        f.snap_text = t.to_string();
        f.snap_cliff = cliff;
    }
}

fn common_prefix_len(a: &str, b: &str) -> usize {
    a.chars().zip(b.chars()).take_while(|(x, y)| x == y).count()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::source::WINDOWS;
    use std::cell::RefCell;
    use std::rc::Rc;

    #[derive(Debug, Clone, PartialEq)]
    enum Op {
        Session,
        Add(i64, String, bool),
        Replace(i64, String, bool),
        Cliff(i64),
    }

    #[derive(Default, Clone)]
    struct Recorder(Rc<RefCell<Vec<Op>>>);

    impl Sink for Recorder {
        fn create_session(&self, _: &SourceContext) -> i64 {
            self.0.borrow_mut().push(Op::Session);
            1
        }
        fn add_snapshot(&self, _: i64, _: &SourceContext, text: &str, cliff: bool) -> i64 {
            let mut ops = self.0.borrow_mut();
            let id = ops.iter().filter(|o| matches!(o, Op::Add(..))).count() as i64 + 1;
            ops.push(Op::Add(id, text.into(), cliff));
            id
        }
        fn replace_snapshot(&self, id: i64, _: i64, _: &SourceContext, text: &str, cliff: bool) {
            self.0.borrow_mut().push(Op::Replace(id, text.into(), cliff));
        }
        fn mark_cliff(&self, id: i64, _: i64) {
            self.0.borrow_mut().push(Op::Cliff(id));
        }
    }

    /// A text box whose value the test controls. `None` = the app hides its text.
    struct Box_(Rc<RefCell<Option<String>>>, i32);
    impl Field for Box_ {
        fn id(&self) -> Vec<i32> {
            vec![self.1]
        }
        fn value(&self) -> Option<String> {
            self.0.borrow().clone()
        }
        fn caret(&self) -> Option<usize> {
            self.0.borrow().as_ref().map(|v| v.chars().count())
        }
    }

    struct Fake {
        value: Rc<RefCell<Option<String>>>,
        focus: i32,
        secure: bool,
        unreadable: bool,
    }
    impl Accessibility for Fake {
        fn focused(&mut self, _: &AppRef) -> Focus {
            if self.secure {
                Focus::Secure
            } else if self.unreadable {
                Focus::Unreadable
            } else {
                Focus::Field(Box::new(Box_(self.value.clone(), self.focus)))
            }
        }
        fn context(&mut self, app: &AppRef, _: Option<&dyn Field>) -> SourceContext {
            SourceContext { app: app.name.clone(), bundle: app.bundle.clone(), window: "w".into(), domain: None }
        }
    }

    struct Rig {
        t: Tracker<Recorder>,
        ax: Fake,
        now: Instant,
        app: AppRef,
    }

    impl Rig {
        fn new(initial: Option<&str>) -> Rig {
            Rig {
                t: Tracker::new(Recorder::default(), &WINDOWS),
                ax: Fake {
                    value: Rc::new(RefCell::new(initial.map(String::from))),
                    focus: 1,
                    secure: false,
                    unreadable: false,
                },
                now: Instant::now(),
                app: AppRef { pid: 10, id: "notepad.exe".into(), name: "Notepad".into(), bundle: None },
            }
        }
        /// Types `s` one key at a time; the box value follows unless `frozen`.
        fn type_str(&mut self, s: &str, frozen: bool) {
            for c in s.chars() {
                if !frozen {
                    if let Some(v) = self.ax.value.borrow_mut().as_mut() {
                        v.push(c);
                    }
                }
                let key = if c == '\n' { Key::Enter } else { Key::Char(c.to_string()) };
                self.t.key(KeyStroke { app: self.app.clone(), key, shortcut: false }, &mut self.ax, self.now);
                self.wait(10);
            }
        }
        fn set(&mut self, v: &str) {
            *self.ax.value.borrow_mut() = Some(v.into());
        }
        fn wait(&mut self, ms: u64) {
            let end = self.now + Duration::from_millis(ms);
            while let Some(d) = self.t.next_deadline().filter(|d| *d <= end) {
                self.now = d.max(self.now);
                self.t.poll(self.now);
            }
            self.now = end;
        }
        fn ops(&self) -> Vec<Op> {
            self.t.sink().0.borrow().clone()
        }
    }

    #[test]
    fn saves_after_idle() {
        let mut r = Rig::new(Some(""));
        r.type_str("hello there", false);
        assert!(r.ops().is_empty());
        r.wait(1600);
        assert_eq!(r.ops(), vec![Op::Session, Op::Add(1, "hello there".into(), false)]);
    }

    #[test]
    fn baseline_text_is_left_out() {
        let mut r = Rig::new(Some("Existing long note. "));
        r.type_str("new bit", false);
        r.wait(1600);
        assert_eq!(r.ops().last(), Some(&Op::Add(1, "new bit".into(), false)));
    }

    #[test]
    fn growing_tail_reuses_the_version() {
        let mut r = Rig::new(Some(""));
        r.type_str("first part", false);
        r.wait(1600);
        r.type_str(" and more", false);
        r.wait(1600);
        assert_eq!(r.ops().last(), Some(&Op::Replace(1, "first part and more".into(), false)));
    }

    #[test]
    fn new_version_after_five_minutes() {
        let mut r = Rig::new(Some(""));
        r.type_str("first part", false);
        r.wait(1600);
        r.wait(301_000);
        r.type_str(" later", false);
        r.wait(1600);
        assert_eq!(r.ops().last(), Some(&Op::Add(2, "first part later".into(), false)));
    }

    #[test]
    fn cleared_box_saves_a_cliff_and_starts_a_new_entry() {
        let mut r = Rig::new(Some(""));
        r.type_str("a long message that will be lost", false);
        r.set("");
        r.type_str("x", false);
        r.wait(100);
        assert_eq!(r.ops(), vec![Op::Session, Op::Add(1, "a long message that will be lost".into(), true)]);
        // The next text in the same box is a new entry.
        r.set("");
        r.type_str("next one", false);
        r.wait(1600);
        assert_eq!(r.ops().iter().filter(|o| **o == Op::Session).count(), 2);
    }

    #[test]
    fn saved_text_then_cleared_marks_cliff() {
        let mut r = Rig::new(Some(""));
        r.type_str("a long message that will be lost", false);
        r.wait(1600);
        r.set("");
        r.type_str("x", false);
        r.wait(100);
        assert_eq!(r.ops().last(), Some(&Op::Cliff(1)));
    }

    #[test]
    fn decoy_input_falls_back_to_keys() {
        let mut r = Rig::new(Some(""));
        r.type_str("typed into a canvas", true);
        r.wait(1600);
        assert_eq!(r.ops().last(), Some(&Op::Add(1, "typed into a canvas".into(), false)));
    }

    #[test]
    fn unreadable_focus_uses_keys_with_edits() {
        let mut r = Rig::new(None);
        r.ax.unreadable = true;
        r.type_str("hello wrld", false);
        for k in [Key::DeleteWord, Key::Char("world".into()), Key::Backspace, Key::Char("d!".into())] {
            r.t.key(KeyStroke { app: r.app.clone(), key: k, shortcut: false }, &mut r.ax, r.now);
        }
        r.t.key(KeyStroke { app: r.app.clone(), key: Key::Char("v".into()), shortcut: true }, &mut r.ax, r.now);
        r.wait(1600);
        assert_eq!(r.ops().last(), Some(&Op::Add(1, "hello world!".into(), false)));
    }

    #[test]
    fn terminals_record_keystrokes_only() {
        let mut r = Rig::new(Some("PS C:\\> lots of scrollback"));
        r.app.id = "windowsterminal.exe".into();
        r.type_str("git status\n", false);
        r.wait(1600);
        assert_eq!(r.ops().last(), Some(&Op::Add(1, "git status\n".into(), false)));
    }

    #[test]
    fn password_fields_and_password_managers_are_skipped() {
        let mut r = Rig::new(Some(""));
        r.ax.secure = true;
        r.type_str("hunter2 secret", false);
        r.wait(1600);
        r.ax.secure = false;
        r.app.id = "1password.exe".into();
        r.type_str("vault text here", false);
        r.wait(1600);
        assert!(r.ops().is_empty());
    }

    #[test]
    fn switching_apps_saves_right_away() {
        let mut r = Rig::new(Some(""));
        r.type_str("half a thought", false);
        r.wait(200);
        r.t.app_switched(r.now);
        assert_eq!(r.ops().last(), Some(&Op::Add(1, "half a thought".into(), false)));
    }

    #[test]
    fn short_text_is_not_saved() {
        let mut r = Rig::new(Some(""));
        r.type_str("ok", false);
        r.wait(1600);
        assert!(r.ops().is_empty());
    }
}
