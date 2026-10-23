//! Wires the hook, the clipboard listener and UI Automation to the shared capture logic.
//! One worker thread owns the tracker and the UIA client; the hook and clipboard threads only feed it.

use crate::clipboard::{self, Copied};
use crate::keys::{self, RawKey};
use crate::{apps, uia::Uia};
use keypsake_core::capture::{Accessibility, KeyStroke, Tracker};
use keypsake_core::source::{AppRef, WINDOWS};
use keypsake_core::store::Store;
use keypsake_core::text;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::Arc;
use std::time::{Duration, Instant};

pub enum Msg {
    Key(RawKey),
    /// A different app came to the front.
    Foreground,
    Clip(Copied),
}

static PAUSED: AtomicBool = AtomicBool::new(false);
static CLIP_LIMIT: AtomicUsize = AtomicUsize::new(50);

pub struct Capture {
    /// Why typing isn't being recorded, if it isn't.
    pub typing_error: Option<String>,
    pub clipboard_error: Option<String>,
}

impl Capture {
    pub fn start(store: Arc<Store>, paused: bool, clip_limit: usize) -> Capture {
        PAUSED.store(paused, Ordering::Relaxed);
        CLIP_LIMIT.store(clip_limit, Ordering::Relaxed);
        let (tx, rx) = mpsc::channel::<Msg>();
        let (ready_tx, ready_rx) = mpsc::channel();
        let worker = std::thread::Builder::new().name("keypsake-capture".into()).spawn(move || {
            let mut uia = match Uia::new(&WINDOWS) {
                Ok(u) => {
                    let _ = ready_tx.send(None);
                    u
                }
                Err(e) => {
                    let _ = ready_tx.send(Some(format!("UI Automation isn't available: {e}")));
                    return;
                }
            };
            run(rx, store, &mut uia);
        });
        let mut typing_error = match worker {
            Ok(_) => ready_rx.recv().unwrap_or(Some("capture stopped".into())),
            Err(e) => Some(e.to_string()),
        };
        if typing_error.is_none() {
            typing_error = keys::start(tx.clone(), &PAUSED).err().map(|e| e.to_string());
        }
        let clipboard_error = clipboard::start(tx, &PAUSED).err().map(|e| e.to_string());
        Capture { typing_error, clipboard_error }
    }

    pub fn set_paused(&self, paused: bool) {
        PAUSED.store(paused, Ordering::Relaxed);
    }

    pub fn set_clip_limit(&self, limit: usize) {
        CLIP_LIMIT.store(limit, Ordering::Relaxed);
    }
}

/// The app behind a window, looking through ApplicationFrameHost to the UWP app inside.
fn app_for(hwnd: windows::Win32::Foundation::HWND) -> Option<AppRef> {
    let (pid, _) = apps::window_owner(hwnd);
    if pid == 0 {
        return None;
    }
    let app = apps::app_for_pid(pid);
    if app.id == "applicationframehost.exe" {
        return apps::foreground_pid().map(|(p, _)| apps::app_for_pid(p));
    }
    Some(app)
}

fn run(rx: mpsc::Receiver<Msg>, store: Arc<Store>, uia: &mut Uia) {
    let mut tracker = Tracker::new(store.clone(), &WINDOWS);
    loop {
        let wait = tracker
            .next_deadline()
            .map(|d| d.saturating_duration_since(Instant::now()))
            .unwrap_or(Duration::from_secs(3600));
        match rx.recv_timeout(wait) {
            Ok(Msg::Key(raw)) => {
                let (_, thread) = apps::window_owner(raw.hwnd);
                if let (Some(app), Some((key, shortcut))) = (app_for(raw.hwnd), keys::translate(&raw, thread)) {
                    tracker.key(KeyStroke { app, key, shortcut }, uia, Instant::now());
                }
            }
            Ok(Msg::Foreground) => tracker.app_switched(Instant::now()),
            Ok(Msg::Clip(c)) => record_clip(c, &store, uia),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => break,
        }
        tracker.poll(Instant::now());
    }
}

fn record_clip(c: Copied, store: &Store, uia: &mut Uia) {
    let front = apps::foreground_pid().map(|(p, _)| apps::app_for_pid(p));
    let owner = c.owner_pid.map(apps::app_for_pid);
    if [&front, &owner].into_iter().flatten().any(|a| WINDOWS.is_secret(&a.id)) {
        return;
    }
    let Some(app) = front.or(owner) else { return };
    let mut ctx = uia.context(&app, None);
    if ctx.app.is_empty() {
        ctx.app = "Unknown app".into();
    }
    store.add_clip(text::prefix(&c.text, text::MAX_LENGTH), &ctx, CLIP_LIMIT.load(Ordering::Relaxed));
}
