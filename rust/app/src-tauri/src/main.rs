//! keypsake for Windows: the shell around the shared core. Windows, tray, global shortcuts, and the commands
//! the web UI calls. The macOS app (Swift, repo root) is the reference; COMPATIBILITY.md lists what must match.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod icons;
mod platform;

use keypsake_core::diff::{self, Span};
use keypsake_core::prefs::Prefs;
use keypsake_core::store::{Change, Clip, SessionItem, Snapshot, Store};
use keypsake_core::{demo, view};
use serde::Serialize;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder, WindowEvent, Wry};
use tauri_plugin_autostart::ManagerExt;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

const TRAY: &[u8] = include_bytes!("../icons/tray.png");
const TRAY_PAUSED: &[u8] = include_bytes!("../icons/tray-paused.png");

struct Ctx {
    store: Arc<Store>,
    prefs: Mutex<Prefs>,
    prefs_path: PathBuf,
    capture: Option<platform::Capture>,
    icons: icons::Icons,
    demo: bool,
    /// [open, pause]
    shortcuts: Mutex<[Option<Shortcut>; 2]>,
    shortcut_error: Mutex<Option<String>>,
    tray_pause: Mutex<Option<MenuItem<Wry>>>,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct Status {
    prefs: Prefs,
    typing_error: Option<String>,
    clipboard_error: Option<String>,
    shortcut_error: Option<String>,
    demo: bool,
}

impl Ctx {
    fn status(&self) -> Status {
        Status {
            prefs: self.prefs.lock().unwrap().clone(),
            typing_error: self.capture.as_ref().and_then(|c| c.typing_error.clone()),
            clipboard_error: self.capture.as_ref().and_then(|c| c.clipboard_error.clone()),
            shortcut_error: self.shortcut_error.lock().unwrap().clone(),
            demo: self.demo,
        }
    }
}

// MARK: commands
// Sync commands run on the main thread; anything that touches disk, the database or Win32 icons is async.

#[tauri::command]
fn status(c: State<Ctx>) -> Status {
    c.status()
}

#[tauri::command]
fn sessions(c: State<Ctx>) -> Vec<SessionItem> {
    c.store.sessions()
}

#[tauri::command]
fn clips(c: State<Ctx>) -> Vec<Clip> {
    c.store.clips()
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Versions {
    snaps: Vec<Snapshot>,
    default_version: Option<i64>,
}

#[tauri::command]
async fn snapshots(c: State<'_, Ctx>, session: i64) -> Result<Versions, ()> {
    let snaps = c.store.snapshots(session);
    let default_version = view::default_version(&snaps);
    Ok(Versions { snaps, default_version })
}

#[derive(Serialize)]
struct Changes {
    spans: Vec<Span>,
    summary: String,
}

/// None when the texts are too long to compare word by word.
#[tauri::command]
async fn compare(old: String, new: String) -> Result<Option<Changes>, ()> {
    Ok(diff::compare(&old, &new).map(|r| Changes { summary: diff::summary(&r), spans: r.spans }))
}

#[tauri::command]
fn copy(text: String) -> Result<(), String> {
    platform::copy_text(&text).map_err(|e| e.to_string())
}

#[tauri::command]
async fn delete_session(c: State<'_, Ctx>, id: i64) -> Result<(), ()> {
    c.store.delete_session(id);
    Ok(())
}

#[tauri::command]
async fn delete_clip(c: State<'_, Ctx>, id: i64) -> Result<(), ()> {
    c.store.delete_clip(id);
    Ok(())
}

#[tauri::command]
async fn delete_all(c: State<'_, Ctx>) -> Result<(), ()> {
    c.store.delete_all();
    Ok(())
}

#[tauri::command]
fn set_prefs(app: AppHandle, prefs: Prefs) -> Status {
    apply_prefs(&app, prefs)
}

#[tauri::command]
fn autostart(app: AppHandle) -> bool {
    app.autolaunch().is_enabled().unwrap_or(false)
}

#[tauri::command]
fn set_autostart(app: AppHandle, on: bool) -> Result<(), String> {
    let l = app.autolaunch();
    if on { l.enable() } else { l.disable() }.map_err(|e| format!("Couldn't change this: {e}"))
}

#[tauri::command]
fn open_settings(app: AppHandle) {
    show_settings(&app);
}

#[tauri::command]
async fn app_icon(c: State<'_, Ctx>, bundle: String) -> Result<Option<String>, ()> {
    Ok(c.icons.app(&bundle))
}

#[tauri::command]
async fn favicon(c: State<'_, Ctx>, domain: String) -> Result<Option<String>, ()> {
    Ok(c.icons.site(&domain).await)
}

// MARK: prefs

fn apply_prefs(app: &AppHandle, new: Prefs) -> Status {
    let c = app.state::<Ctx>();
    let old = std::mem::replace(&mut *c.prefs.lock().unwrap(), new.clone());
    if let Some(cap) = &c.capture {
        cap.set_paused(new.paused);
        cap.set_clip_limit(new.clip_limit);
    }
    if old.retention_days != new.retention_days || old.clip_limit != new.clip_limit {
        c.store.prune(new.retention_days, new.clip_limit);
    }
    if old.shortcut_open != new.shortcut_open || old.shortcut_pause != new.shortcut_pause {
        register_shortcuts(app);
    }
    if old.paused != new.paused {
        update_tray(app);
    }
    if !c.demo {
        let _ = new.save(&c.prefs_path);
    }
    let status = c.status();
    let _ = app.emit("status-changed", status.clone());
    status
}

fn toggle_pause(app: &AppHandle) {
    let mut p = app.state::<Ctx>().prefs.lock().unwrap().clone();
    p.paused = !p.paused;
    apply_prefs(app, p);
}

fn register_shortcuts(app: &AppHandle) {
    let c = app.state::<Ctx>();
    let gs = app.global_shortcut();
    let _ = gs.unregister_all();
    let p = c.prefs.lock().unwrap().clone();
    let mut errors = vec![];
    let mut parsed: [Option<Shortcut>; 2] = [None, None];
    for (i, s) in [&p.shortcut_open, &p.shortcut_pause].into_iter().enumerate() {
        match s.parse::<Shortcut>() {
            Ok(sc) => match gs.register(sc) {
                Ok(()) => parsed[i] = Some(sc),
                Err(_) => errors.push(format!("{s} is taken by another app")),
            },
            Err(_) => errors.push(format!("{s} isn't a shortcut")),
        }
    }
    *c.shortcuts.lock().unwrap() = parsed;
    *c.shortcut_error.lock().unwrap() = (!errors.is_empty()).then(|| errors.join(". "));
}

// MARK: windows

fn main_window(app: &AppHandle) -> Option<tauri::WebviewWindow> {
    if let Some(w) = app.get_webview_window("main") {
        return Some(w);
    }
    WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
        .title("keypsake")
        .inner_size(820.0, 540.0)
        .min_inner_size(680.0, 420.0)
        .decorations(false)
        .center()
        .visible(false)
        .build()
        .ok()
}

fn show_main(app: &AppHandle) {
    if let Some(w) = main_window(app) {
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
    }
}

fn toggle_main(app: &AppHandle) {
    if let Some(w) = main_window(app) {
        if w.is_visible().unwrap_or(false) && w.is_focused().unwrap_or(false) {
            let _ = w.hide();
        } else {
            show_main(app);
            let _ = w.emit("focus-search", ());
        }
    }
}

fn show_settings(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("settings") {
        let _ = w.show();
        let _ = w.set_focus();
        return;
    }
    let _ = WebviewWindowBuilder::new(app, "settings", WebviewUrl::App("settings.html".into()))
        .title("Settings")
        .inner_size(480.0, 640.0)
        .resizable(false)
        .maximizable(false)
        .minimizable(false)
        .decorations(false)
        .center()
        .build();
}

// MARK: tray

fn update_tray(app: &AppHandle) {
    let c = app.state::<Ctx>();
    let paused = c.prefs.lock().unwrap().paused;
    if let Some(item) = c.tray_pause.lock().unwrap().as_ref() {
        let _ = item.set_text(if paused { "Resume recording" } else { "Pause recording" });
    }
    if let Some(tray) = app.tray_by_id("main") {
        if let Ok(img) = Image::from_bytes(if paused { TRAY_PAUSED } else { TRAY }) {
            let _ = tray.set_icon(Some(img));
        }
        let _ = tray.set_tooltip(Some(if paused { "keypsake (paused)" } else { "keypsake" }));
    }
}

fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    let c = app.state::<Ctx>();
    let open = MenuItem::with_id(app, "open", "Open keypsake", true, None::<&str>)?;
    let pause = MenuItem::with_id(app, "pause", "Pause recording", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "Settings…", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit keypsake", true, None::<&str>)?;
    let sep = PredefinedMenuItem::separator(app)?;
    let menu = Menu::with_items(app, &[&open, &pause, &sep])?;
    if c.capture.as_ref().is_some_and(|c| c.typing_error.is_some()) {
        let warn =
            MenuItem::with_id(app, "open", "Typing isn't recorded: open keypsake for details", true, None::<&str>)?;
        menu.append(&warn)?;
        menu.append(&PredefinedMenuItem::separator(app)?)?;
    }
    menu.append(&settings)?;
    menu.append(&quit)?;
    *c.tray_pause.lock().unwrap() = Some(pause);

    TrayIconBuilder::with_id("main")
        .icon(Image::from_bytes(TRAY)?)
        .tooltip("keypsake")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, e| match e.id().as_ref() {
            "open" => show_main(app),
            "pause" => toggle_pause(app),
            "settings" => show_settings(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, e| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = e {
                show_main(tray.app_handle());
            }
        })
        .build(app)?;
    update_tray(app);
    Ok(())
}

// MARK: startup

fn data_dir(demo: bool) -> PathBuf {
    let base = dirs::data_local_dir().unwrap_or_else(std::env::temp_dir);
    let dir = base.join(if demo { "keypsake-demo" } else { "keypsake" });
    let _ = std::fs::create_dir_all(&dir);
    dir
}

fn open_store(app: &AppHandle, demo: bool) -> anyhow::Result<(Store, PathBuf)> {
    if demo {
        let _ = std::fs::remove_dir_all(data_dir(true));
    }
    let dir = data_dir(demo);
    // Demo data is rebuilt each launch, so its key is throwaway.
    let key = if demo { keypsake_core::store::new_key() } else { platform::load_key(&dir.join("key.bin"))? };
    let mut store = Store::open(&dir.join("keypsake.sqlite"), &key)?;
    let handle = app.clone();
    store.set_on_change(move |c| {
        let _ = handle.emit(if c == Change::Sessions { "sessions-changed" } else { "clips-changed" }, ());
    });
    Ok((store, dir))
}

fn setup(app: &AppHandle) -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let demo = args.iter().any(|a| a == "--demo");
    let (store, dir) = match open_store(app, demo) {
        Ok(s) => s,
        Err(e) => {
            platform::alert(
                "keypsake can't open its encrypted history",
                &format!("The encryption key couldn't be unlocked ({e}). Nothing was recorded or deleted. Open keypsake again while signed in as the same Windows user."),
            );
            app.exit(1);
            return Ok(());
        }
    };
    let store = Arc::new(store);
    if demo {
        demo::seed(&store);
    }
    let prefs_path = dir.join("prefs.json");
    let prefs = if demo { Prefs::default() } else { Prefs::load(&prefs_path) };
    let capture = (!demo).then(|| platform::Capture::start(store.clone(), prefs.paused, prefs.clip_limit));
    if !demo {
        store.prune(prefs.retention_days, prefs.clip_limit);
    }
    app.manage(Ctx {
        store: store.clone(),
        prefs: Mutex::new(prefs),
        prefs_path,
        capture,
        icons: icons::Icons::new(dir.join("favicons")),
        demo,
        shortcuts: Mutex::new([None, None]),
        shortcut_error: Mutex::new(None),
        tray_pause: Mutex::new(None),
    });
    if !demo {
        register_shortcuts(app);
        let handle = app.clone();
        std::thread::spawn(move || loop {
            std::thread::sleep(Duration::from_secs(3600));
            let p = handle.state::<Ctx>().prefs.lock().unwrap().clone();
            store.prune(p.retention_days, p.clip_limit);
        });
    }
    build_tray(app)?;
    let w = main_window(app);
    if args.iter().any(|a| a == "--dark") {
        if let Some(w) = &w {
            let _ = w.set_theme(Some(tauri::Theme::Dark));
        }
    }
    // Opened at login: stay in the tray.
    if !args.iter().any(|a| a == "--hidden") {
        show_main(app);
    }
    Ok(())
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| show_main(app)))
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec!["--hidden"]),
        ))
        .plugin(
            tauri_plugin_window_state::Builder::default()
                .with_denylist(&["settings"])
                .with_state_flags(
                    tauri_plugin_window_state::StateFlags::all() & !tauri_plugin_window_state::StateFlags::VISIBLE,
                )
                .build(),
        )
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, shortcut, event| {
                    if event.state() != ShortcutState::Pressed {
                        return;
                    }
                    let which = {
                        let s = *app.state::<Ctx>().shortcuts.lock().unwrap();
                        s.iter().position(|s| s.as_ref() == Some(shortcut))
                    };
                    match which {
                        Some(0) => toggle_main(app),
                        Some(1) => toggle_pause(app),
                        _ => {}
                    }
                })
                .build(),
        )
        .invoke_handler(tauri::generate_handler![
            status,
            sessions,
            clips,
            snapshots,
            compare,
            copy,
            delete_session,
            delete_clip,
            delete_all,
            set_prefs,
            autostart,
            set_autostart,
            open_settings,
            app_icon,
            favicon
        ])
        .on_window_event(|window, event| {
            // Closing the main window keeps keypsake running in the tray, like the macOS menu bar app.
            if let WindowEvent::CloseRequested { api, .. } = event {
                if window.label() == "main" {
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .setup(|app| setup(app.handle()).map_err(|e| e.into()))
        .run(tauri::generate_context!())
        .expect("error while running keypsake");
}
