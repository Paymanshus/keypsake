//! Clipboard history: a message-only window gets WM_CLIPBOARDUPDATE on every copy (no polling, unlike macOS).

use crate::apps;
use crate::capture::Msg;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::Sender;
use std::sync::OnceLock;
use windows::core::PCWSTR;
use windows::Win32::Foundation::{GlobalFree, HANDLE, HGLOBAL, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::DataExchange::*;
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalSize, GlobalUnlock, GMEM_MOVEABLE};
use windows::Win32::System::Ole::CF_UNICODETEXT;
use windows::Win32::UI::WindowsAndMessaging::*;

pub struct Copied {
    pub text: String,
    /// The process that put it there, if known.
    pub owner_pid: Option<u32>,
}

struct Listener {
    tx: Sender<Msg>,
    paused: &'static AtomicBool,
}

static LISTENER: OnceLock<Listener> = OnceLock::new();
/// Sequence number of our own last write, so copying from keypsake isn't recorded again.
static OWN_SEQ: AtomicU32 = AtomicU32::new(0);

fn format(name: &str) -> u32 {
    let w = apps::wide(name);
    unsafe { RegisterClipboardFormatW(PCWSTR(w.as_ptr())) }
}

/// Password managers mark secrets with these (Windows clipboard history honors the same markers).
fn is_private() -> bool {
    unsafe {
        if IsClipboardFormatAvailable(format("ExcludeClipboardContentFromMonitorProcessing")).is_ok()
            || IsClipboardFormatAvailable(format("Clipboard Viewer Ignore")).is_ok()
        {
            return true;
        }
        let f = format("CanIncludeInClipboardHistory");
        if IsClipboardFormatAvailable(f).is_ok() {
            if let Ok(h) = GetClipboardData(f) {
                let p = GlobalLock(HGLOBAL(h.0)) as *const u32;
                let allowed = !p.is_null() && *p != 0;
                let _ = GlobalUnlock(HGLOBAL(h.0));
                return !allowed;
            }
        }
        false
    }
}

fn open(hwnd: Option<HWND>) -> bool {
    // Another app may still hold the clipboard right after writing it.
    for _ in 0..10 {
        if unsafe { OpenClipboard(hwnd) }.is_ok() {
            return true;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    false
}

fn read_text() -> Option<String> {
    unsafe {
        let h = GetClipboardData(CF_UNICODETEXT.0 as u32).ok()?;
        let g = HGLOBAL(h.0);
        let p = GlobalLock(g) as *const u16;
        if p.is_null() {
            return None;
        }
        let max = GlobalSize(g) / 2;
        let s = std::slice::from_raw_parts(p, max);
        let end = s.iter().position(|&c| c == 0).unwrap_or(max);
        let text = String::from_utf16_lossy(&s[..end]);
        let _ = GlobalUnlock(g);
        Some(text)
    }
}

unsafe extern "system" fn wndproc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if msg == WM_CLIPBOARDUPDATE {
        if let Some(l) = LISTENER.get() {
            let seq = GetClipboardSequenceNumber();
            if !l.paused.load(Ordering::Relaxed) && seq != OWN_SEQ.load(Ordering::Relaxed) && open(Some(hwnd)) {
                let owner = GetClipboardOwner().ok().map(|w| apps::window_owner(w).0).filter(|&p| p != 0);
                let text = if is_private() { None } else { read_text() };
                let _ = CloseClipboard();
                if let Some(text) = text.filter(|t| !t.trim().is_empty()) {
                    let _ = l.tx.send(Msg::Clip(Copied { text, owner_pid: owner }));
                }
            }
        }
        return LRESULT(0);
    }
    DefWindowProcW(hwnd, msg, wparam, lparam)
}

pub fn start(tx: Sender<Msg>, paused: &'static AtomicBool) -> anyhow::Result<()> {
    if LISTENER.set(Listener { tx, paused }).is_err() {
        anyhow::bail!("clipboard listener already running");
    }
    let (ready_tx, ready_rx) = std::sync::mpsc::channel();
    std::thread::Builder::new().name("keypsake-clipboard".into()).spawn(move || unsafe {
        let class = apps::wide("keypsake-clipboard");
        let instance = GetModuleHandleW(None).unwrap_or_default();
        let wc = WNDCLASSW {
            lpfnWndProc: Some(wndproc),
            hInstance: instance.into(),
            lpszClassName: PCWSTR(class.as_ptr()),
            ..Default::default()
        };
        RegisterClassW(&wc);
        let hwnd = CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            PCWSTR(class.as_ptr()),
            PCWSTR::null(),
            WINDOW_STYLE::default(),
            0,
            0,
            0,
            0,
            Some(HWND_MESSAGE),
            None,
            Some(instance.into()),
            None,
        );
        let ok = match hwnd {
            Ok(h) => AddClipboardFormatListener(h).map_err(|e| e.to_string()),
            Err(e) => Err(e.to_string()),
        };
        let failed = ok.is_err();
        let _ = ready_tx.send(ok);
        if failed {
            return;
        }
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    })?;
    ready_rx.recv()?.map_err(|e| anyhow::anyhow!("couldn't watch the clipboard: {e}"))
}

/// Copy from inside keypsake without re-recording it.
pub fn write(text: &str) -> anyhow::Result<()> {
    let wide: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
    unsafe {
        if !open(None) {
            anyhow::bail!("the clipboard is busy");
        }
        let result = (|| -> anyhow::Result<()> {
            EmptyClipboard()?;
            let g = GlobalAlloc(GMEM_MOVEABLE, wide.len() * 2)?;
            let p = GlobalLock(g) as *mut u16;
            if p.is_null() {
                let _ = GlobalFree(Some(g));
                anyhow::bail!("out of memory");
            }
            std::ptr::copy_nonoverlapping(wide.as_ptr(), p, wide.len());
            let _ = GlobalUnlock(g);
            if let Err(e) = SetClipboardData(CF_UNICODETEXT.0 as u32, Some(HANDLE(g.0))) {
                let _ = GlobalFree(Some(g));
                return Err(e.into());
            }
            Ok(())
        })();
        // Read before closing: the listener runs as soon as the clipboard is released.
        OWN_SEQ.store(GetClipboardSequenceNumber(), Ordering::Relaxed);
        let _ = CloseClipboard();
        result
    }
}
