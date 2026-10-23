//! Windows implementations of what keypsake needs from the OS. Empty on other platforms.
#![cfg(windows)]

pub mod apps;
pub mod capture;
pub mod clipboard;
pub mod icons;
pub mod keys;
pub mod uia;
pub mod vault;

pub use capture::Capture;

/// A blocking message box, for errors before any window exists.
pub fn alert(title: &str, text: &str) {
    use windows::core::PCWSTR;
    use windows::Win32::UI::WindowsAndMessaging::{MessageBoxW, MB_ICONERROR, MB_OK};
    let (t, m) = (apps::wide(title), apps::wide(text));
    unsafe {
        MessageBoxW(None, PCWSTR(m.as_ptr()), PCWSTR(t.as_ptr()), MB_OK | MB_ICONERROR);
    }
}
