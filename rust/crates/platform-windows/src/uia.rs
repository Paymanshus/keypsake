//! Reading the focused text box through UI Automation: the Windows counterpart of the macOS AX helpers.

use crate::apps;
use keypsake_core::capture::{Accessibility, Field, Focus};
use keypsake_core::source::{domain_of, AppRef, Lists};
use keypsake_core::store::SourceContext;
use keypsake_core::text::MAX_LENGTH;
use windows::core::Interface;
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED, SAFEARRAY,
};
use windows::Win32::System::Ole::{SafeArrayDestroy, SafeArrayGetElement, SafeArrayGetLBound, SafeArrayGetUBound};
use windows::Win32::System::Variant::VARIANT;
use windows::Win32::UI::Accessibility::*;

pub struct Uia {
    automation: IUIAutomation,
    walker: IUIAutomationTreeWalker,
    lists: &'static Lists,
}

impl Uia {
    /// Must be called on the thread that will use it. Initializes COM (multithreaded) there.
    pub fn new(lists: &'static Lists) -> anyhow::Result<Uia> {
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
            let automation: IUIAutomation = CoCreateInstance(&CUIAutomation8, None, CLSCTX_INPROC_SERVER)
                .or_else(|_| CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER))?;
            // A hung app must not stall capture.
            if let Ok(a2) = automation.cast::<IUIAutomation2>() {
                let _ = a2.SetConnectionTimeout(500);
                let _ = a2.SetTransactionTimeout(500);
            }
            let walker = automation.ControlViewWalker()?;
            Ok(Uia { automation, walker, lists })
        }
    }

    fn focused_element(&self) -> Option<IUIAutomationElement> {
        unsafe { self.automation.GetFocusedElement().ok() }
    }

    /// Walk up from the focused element to the web document, whose value is the page URL.
    fn page_url(&self, from: &IUIAutomationElement, hwnd: windows::Win32::Foundation::HWND) -> Option<String> {
        unsafe {
            let mut el = Some(from.clone());
            for _ in 0..60 {
                let Some(cur) = el else { break };
                if cur.CurrentControlType().ok() == Some(UIA_DocumentControlTypeId) {
                    if let Some(v) = value_pattern(&cur) {
                        if domain_of(&v).is_some() {
                            return Some(v);
                        }
                    }
                }
                el = self.walker.GetParentElement(&cur).ok();
            }
            // Firefox: the address bar has a stable automation id.
            let root = self.automation.ElementFromHandle(hwnd).ok()?;
            let cond = self
                .automation
                .CreatePropertyCondition(UIA_AutomationIdPropertyId, &VARIANT::from("urlbar-input"))
                .ok()?;
            let bar = root.FindFirst(TreeScope_Descendants, &cond).ok()?;
            let v = value_pattern(&bar)?;
            Some(if v.contains("://") { v } else { format!("https://{v}") })
        }
    }
}

fn value_pattern(el: &IUIAutomationElement) -> Option<String> {
    unsafe {
        let p: IUIAutomationValuePattern = el.GetCurrentPatternAs(UIA_ValuePatternId).ok()?;
        p.CurrentValue().ok().map(|b| b.to_string())
    }
}

fn text_pattern(el: &IUIAutomationElement) -> Option<IUIAutomationTextPattern> {
    unsafe { el.GetCurrentPatternAs(UIA_TextPatternId).ok() }
}

fn runtime_id(el: &IUIAutomationElement) -> Vec<i32> {
    unsafe {
        let Ok(arr) = el.GetRuntimeId() else { return vec![] };
        let out = read_i32_array(arr);
        let _ = SafeArrayDestroy(arr);
        out
    }
}

unsafe fn read_i32_array(arr: *mut SAFEARRAY) -> Vec<i32> {
    if arr.is_null() {
        return vec![];
    }
    let (Ok(lo), Ok(hi)) = (SafeArrayGetLBound(arr, 1), SafeArrayGetUBound(arr, 1)) else { return vec![] };
    let mut out = Vec::new();
    for i in lo..=hi {
        let mut v = 0i32;
        if SafeArrayGetElement(arr, &i, &mut v as *mut i32 as *mut _).is_ok() {
            out.push(v);
        }
    }
    out
}

pub struct UiaField {
    el: IUIAutomationElement,
    id: Vec<i32>,
}

impl Field for UiaField {
    fn id(&self) -> Vec<i32> {
        self.id.clone()
    }

    fn value(&self) -> Option<String> {
        // Plain inputs answer ValuePattern; rich editors (Word, WinUI, contenteditable) answer TextPattern.
        if let Some(v) = value_pattern(&self.el).filter(|v| !v.is_empty()) {
            return Some(v);
        }
        let tp = text_pattern(&self.el)?;
        unsafe {
            let doc = tp.DocumentRange().ok()?;
            doc.GetText(MAX_LENGTH as i32).ok().map(|b| b.to_string())
        }
    }

    fn caret(&self) -> Option<usize> {
        let tp = text_pattern(&self.el)?;
        unsafe {
            let sel = tp.GetSelection().ok()?;
            if sel.Length().ok()? < 1 {
                return None;
            }
            let caret = sel.GetElement(0).ok()?;
            let before = tp.DocumentRange().ok()?;
            before.MoveEndpointByRange(TextPatternRangeEndpoint_End, &caret, TextPatternRangeEndpoint_Start).ok()?;
            before.GetText(MAX_LENGTH as i32).ok().map(|b| b.to_string().chars().count())
        }
    }
}

impl Accessibility for Uia {
    fn focused(&mut self, app: &AppRef) -> Focus {
        let Some(el) = self.focused_element() else { return Focus::Unreadable };
        unsafe {
            if el.CurrentIsPassword().map(|b| b.as_bool()).unwrap_or(false) {
                return Focus::Secure;
            }
            // Focus moved to another process between the key and this read.
            if el.CurrentProcessId().map(|p| p as u32) != Ok(app.pid) {
                return Focus::Unreadable;
            }
            let has_text =
                el.GetCurrentPattern(UIA_ValuePatternId).is_ok() || el.GetCurrentPattern(UIA_TextPatternId).is_ok();
            if !has_text {
                return Focus::Unreadable;
            }
        }
        let id = runtime_id(&el);
        Focus::Field(Box::new(UiaField { el, id }))
    }

    fn context(&mut self, app: &AppRef, focused: Option<&dyn Field>) -> SourceContext {
        let hwnd = apps::foreground();
        let window = if apps::window_owner(hwnd).0 == app.pid || apps::foreground_pid().map(|p| p.0) == Some(app.pid) {
            apps::window_title(hwnd)
        } else {
            String::new()
        };
        let mut domain = None;
        if self.lists.is_browser(&app.id) {
            let _ = focused; // the element is re-read: UIA elements aren't shared across the trait boundary
            if let Some(el) = self.focused_element() {
                domain = self.page_url(&el, hwnd).and_then(|u| domain_of(&u));
            }
        }
        SourceContext {
            app: app.name.clone(),
            bundle: app.bundle.clone(),
            window: strip_app_suffix(&window, &app.name),
            domain,
        }
    }
}

/// Browsers and editors append " - Google Chrome" / " — Notepad" to window titles; the app is shown separately.
fn strip_app_suffix(title: &str, app: &str) -> String {
    for sep in [" - ", " — ", " – "] {
        if let Some(rest) = title.strip_suffix(&format!("{sep}{app}")) {
            return rest.to_string();
        }
    }
    // Chrome profiles: "Page - Google Chrome - Profile"; Edge: "Page - Profile - Microsoft Edge".
    if let Some(i) = title.find(&format!(" - {app}")) {
        return title[..i].to_string();
    }
    title.to_string()
}

#[cfg(test)]
mod tests {
    #[test]
    fn titles_lose_the_app_name() {
        assert_eq!(super::strip_app_suffix("Inbox - Gmail - Google Chrome", "Google Chrome"), "Inbox - Gmail");
        assert_eq!(super::strip_app_suffix("notes.txt - Notepad", "Notepad"), "notes.txt");
        assert_eq!(super::strip_app_suffix("Alex", "WhatsApp"), "Alex");
    }
}
