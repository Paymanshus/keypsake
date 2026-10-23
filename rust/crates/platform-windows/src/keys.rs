//! Global keystrokes through a low-level keyboard hook, plus foreground-app changes.
//! The hook callback only snapshots the key and returns: Windows drops hooks that are slow.

use crate::capture::Msg;
use keypsake_core::capture::Key;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::Sender;
use std::sync::OnceLock;
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::UI::Accessibility::{SetWinEventHook, HWINEVENTHOOK};
use windows::Win32::UI::Input::KeyboardAndMouse::*;
use windows::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, DispatchMessageW, GetMessageW, SetWindowsHookExW, TranslateMessage, EVENT_SYSTEM_FOREGROUND, HHOOK,
    KBDLLHOOKSTRUCT, MSG, WH_KEYBOARD_LL, WINEVENT_OUTOFCONTEXT, WM_KEYDOWN, WM_SYSKEYDOWN,
};

/// A key as the hook saw it. Turned into text later, off the hook thread.
#[derive(Debug, Clone, Copy)]
pub struct RawKey {
    pub vk: u32,
    pub scan: u32,
    pub shift: bool,
    pub ctrl: bool,
    pub alt: bool,
    pub win: bool,
    pub caps: bool,
    pub hwnd: HWND,
}

// HWND is a raw pointer; it's only used as an identifier across threads.
unsafe impl Send for RawKey {}

struct Hook {
    tx: Sender<Msg>,
    paused: &'static AtomicBool,
}

static HOOK: OnceLock<Hook> = OnceLock::new();
static LAST_FG_PID: AtomicU32 = AtomicU32::new(0);

fn down(vk: VIRTUAL_KEY) -> bool {
    unsafe { GetAsyncKeyState(vk.0 as i32) as u16 & 0x8000 != 0 }
}

unsafe extern "system" fn keyboard(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code >= 0 && (wparam.0 as u32 == WM_KEYDOWN || wparam.0 as u32 == WM_SYSKEYDOWN) {
        if let Some(h) = HOOK.get() {
            if !h.paused.load(Ordering::Relaxed) {
                let k = &*(lparam.0 as *const KBDLLHOOKSTRUCT);
                let _ = h.tx.send(Msg::Key(RawKey {
                    vk: k.vkCode,
                    scan: k.scanCode,
                    shift: down(VK_SHIFT),
                    ctrl: down(VK_CONTROL),
                    alt: down(VK_MENU),
                    win: down(VK_LWIN) || down(VK_RWIN),
                    caps: GetKeyState(VK_CAPITAL.0 as i32) & 1 != 0,
                    hwnd: windows::Win32::UI::WindowsAndMessaging::GetForegroundWindow(),
                }));
            }
        }
    }
    CallNextHookEx(Some(HHOOK::default()), code, wparam, lparam)
}

unsafe extern "system" fn foreground(_: HWINEVENTHOOK, _: u32, hwnd: HWND, _: i32, _: i32, _: u32, _: u32) {
    let (pid, _) = crate::apps::window_owner(hwnd);
    if pid != 0 && LAST_FG_PID.swap(pid, Ordering::Relaxed) != pid {
        if let Some(h) = HOOK.get() {
            let _ = h.tx.send(Msg::Foreground);
        }
    }
}

/// Installs the hooks on a dedicated thread with its own message loop. Errors if the hook can't be set.
pub fn start(tx: Sender<Msg>, paused: &'static AtomicBool) -> anyhow::Result<()> {
    if HOOK.set(Hook { tx, paused }).is_err() {
        anyhow::bail!("keyboard hook already running");
    }
    let (ready_tx, ready_rx) = std::sync::mpsc::channel();
    std::thread::Builder::new().name("keypsake-hook".into()).spawn(move || unsafe {
        let hook = SetWindowsHookExW(WH_KEYBOARD_LL, Some(keyboard), None, 0);
        let _ = ready_tx.send(hook.as_ref().map(|_| ()).map_err(|e| e.to_string()));
        if hook.is_err() {
            return;
        }
        SetWinEventHook(
            EVENT_SYSTEM_FOREGROUND,
            EVENT_SYSTEM_FOREGROUND,
            None,
            Some(foreground),
            0,
            0,
            WINEVENT_OUTOFCONTEXT,
        );
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    })?;
    ready_rx.recv()?.map_err(|e| anyhow::anyhow!("couldn't install the keyboard hook: {e}"))
}

/// Maps a raw key to what it does to text. `shortcut` is true when Ctrl (without AltGr), Alt alone or Win is held.
pub fn translate(k: &RawKey, layout_thread: u32) -> Option<(Key, bool)> {
    let vk = VIRTUAL_KEY(k.vk as u16);
    // AltGr arrives as Ctrl+Alt and types text on many layouts.
    let altgr = k.ctrl && k.alt;
    let shortcut = k.win || (k.ctrl && !k.alt) || (k.alt && !k.ctrl);
    let key = match vk {
        VK_SHIFT | VK_LSHIFT | VK_RSHIFT | VK_CONTROL | VK_LCONTROL | VK_RCONTROL | VK_MENU | VK_LMENU | VK_RMENU
        | VK_LWIN | VK_RWIN | VK_CAPITAL | VK_NUMLOCK | VK_SCROLL => return None,
        VK_BACK if k.ctrl && !k.alt => return Some((Key::DeleteWord, false)),
        VK_BACK => Key::Backspace,
        VK_RETURN => Key::Enter,
        VK_TAB => Key::Tab,
        // Text from the emoji panel, on-screen keyboard and some IMEs: the character rides in the scan code.
        VK_PACKET => Key::Char(char::from_u32(k.scan).map(String::from).unwrap_or_default()),
        VK_ESCAPE | VK_LEFT | VK_RIGHT | VK_UP | VK_DOWN | VK_HOME | VK_END | VK_PRIOR | VK_NEXT | VK_DELETE
        | VK_INSERT | VK_PROCESSKEY => Key::Other,
        _ if (VK_F1.0..=VK_F24.0).contains(&vk.0) => Key::Other,
        _ => {
            let mut state = [0u8; 256];
            if k.shift {
                state[VK_SHIFT.0 as usize] = 0x80;
            }
            if k.ctrl {
                state[VK_CONTROL.0 as usize] = 0x80;
            }
            if k.alt {
                state[VK_MENU.0 as usize] = 0x80;
            }
            if k.caps {
                state[VK_CAPITAL.0 as usize] = 0x01;
            }
            let mut buf = [0u16; 8];
            // Flag 0x4: don't touch the keyboard's dead-key state, so typing in the app isn't disturbed.
            let n = unsafe {
                let layout = windows::Win32::UI::Input::KeyboardAndMouse::GetKeyboardLayout(layout_thread);
                ToUnicodeEx(k.vk, k.scan, &state, &mut buf, 0x4, Some(layout))
            };
            if n <= 0 {
                Key::Other
            } else {
                Key::Char(String::from_utf16_lossy(&buf[..n as usize]))
            }
        }
    };
    let shortcut = match &key {
        Key::Char(c) if altgr && c.chars().all(|c| !c.is_control()) => false,
        _ => shortcut,
    };
    Some((key, shortcut))
}
