//! Which app owns a window: exe path, display name, foreground window.

use keypsake_core::source::AppRef;
use std::collections::HashMap;
use std::sync::Mutex;
use windows::core::{BOOL, PCWSTR, PWSTR};
use windows::Win32::Foundation::{CloseHandle, HWND, LPARAM};
use windows::Win32::Storage::FileSystem::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
use windows::Win32::System::Threading::{
    OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumChildWindows, GetForegroundWindow, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId,
};

pub fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Process id and thread id that own a window.
pub fn window_owner(hwnd: HWND) -> (u32, u32) {
    let mut pid = 0u32;
    let tid = unsafe { GetWindowThreadProcessId(hwnd, Some(&mut pid)) };
    (pid, tid)
}

pub fn window_title(hwnd: HWND) -> String {
    unsafe {
        let len = GetWindowTextLengthW(hwnd);
        if len <= 0 {
            return String::new();
        }
        let mut buf = vec![0u16; len as usize + 1];
        let n = GetWindowTextW(hwnd, &mut buf);
        String::from_utf16_lossy(&buf[..n.max(0) as usize])
    }
}

pub fn foreground() -> HWND {
    unsafe { GetForegroundWindow() }
}

/// UWP apps (Calculator, Mail…) draw inside ApplicationFrameHost; the real app owns a child window.
pub fn foreground_pid() -> Option<(u32, HWND)> {
    let hwnd = foreground();
    if hwnd.is_invalid() {
        return None;
    }
    let (pid, _) = window_owner(hwnd);
    if pid == 0 {
        return None;
    }
    if app_for_pid(pid).id == "applicationframehost.exe" {
        let mut found = (pid, 0u32);
        unsafe extern "system" fn child(h: HWND, l: LPARAM) -> BOOL {
            let found = &mut *(l.0 as *mut (u32, u32));
            let (pid, _) = window_owner(h);
            if pid != found.0 {
                found.1 = pid;
                return BOOL(0);
            }
            BOOL(1)
        }
        unsafe {
            let _ = EnumChildWindows(Some(hwnd), Some(child), LPARAM(&mut found as *mut _ as isize));
        }
        if found.1 != 0 {
            return Some((found.1, hwnd));
        }
    }
    Some((pid, hwnd))
}

static CACHE: Mutex<Option<HashMap<u32, AppRef>>> = Mutex::new(None);

/// App identity for a process. Cached per pid (a recycled pid with a different exe is re-read).
pub fn app_for_pid(pid: u32) -> AppRef {
    let path = exe_path(pid);
    let mut cache = CACHE.lock().unwrap_or_else(|e| e.into_inner());
    let cache = cache.get_or_insert_with(HashMap::new);
    if let Some(a) = cache.get(&pid) {
        if a.bundle == path {
            return a.clone();
        }
    }
    let id = path.as_deref().and_then(|p| p.rsplit(['\\', '/']).next()).unwrap_or("").to_lowercase();
    let name = path.as_deref().and_then(file_description).filter(|d| !d.trim().is_empty()).unwrap_or_else(|| stem(&id));
    let app = AppRef { pid, id, name, bundle: path };
    if cache.len() > 500 {
        cache.clear();
    }
    cache.insert(pid, app.clone());
    app
}

fn stem(file: &str) -> String {
    let s = file.strip_suffix(".exe").unwrap_or(file);
    let mut c = s.chars();
    match c.next() {
        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
        None => "Unknown app".into(),
    }
}

pub fn exe_path(pid: u32) -> Option<String> {
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut buf = vec![0u16; 1024];
        let mut len = buf.len() as u32;
        let ok = QueryFullProcessImageNameW(h, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len);
        let _ = CloseHandle(h);
        ok.ok()?;
        Some(String::from_utf16_lossy(&buf[..len as usize]))
    }
}

/// "Google Chrome" rather than "chrome": the FileDescription in the exe's version info.
fn file_description(path: &str) -> Option<String> {
    unsafe {
        let wpath = wide(path);
        let size = GetFileVersionInfoSizeW(PCWSTR(wpath.as_ptr()), None);
        if size == 0 {
            return None;
        }
        let mut data = vec![0u8; size as usize];
        GetFileVersionInfoW(PCWSTR(wpath.as_ptr()), None, size, data.as_mut_ptr() as _).ok()?;
        let mut ptr = std::ptr::null_mut();
        let mut len = 0u32;
        let q = wide("\\VarFileInfo\\Translation");
        let langs: Vec<(u16, u16)> = if VerQueryValueW(data.as_ptr() as _, PCWSTR(q.as_ptr()), &mut ptr, &mut len)
            .as_bool()
            && len >= 4
        {
            std::slice::from_raw_parts(ptr as *const u16, (len / 2) as usize).chunks(2).map(|c| (c[0], c[1])).collect()
        } else {
            vec![]
        };
        for (lang, cp) in langs.into_iter().chain([(0x0409, 0x04B0), (0x0409, 0x04E4)]) {
            let q = wide(&format!("\\StringFileInfo\\{lang:04x}{cp:04x}\\FileDescription"));
            if VerQueryValueW(data.as_ptr() as _, PCWSTR(q.as_ptr()), &mut ptr, &mut len).as_bool() && len > 1 {
                let s = std::slice::from_raw_parts(ptr as *const u16, len as usize);
                let end = s.iter().position(|&c| c == 0).unwrap_or(s.len());
                return Some(String::from_utf16_lossy(&s[..end]));
            }
        }
        None
    }
}
