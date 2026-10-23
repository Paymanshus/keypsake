//! The OS layer the shell uses. Windows is the only target that captures today; other targets compile
//! (so the shell can be checked anywhere) but record nothing. A Linux port adds its own module here.

#[cfg(windows)]
mod imp {
    pub use keypsake_platform_windows::Capture;

    pub fn load_key(file: &std::path::Path) -> anyhow::Result<[u8; 32]> {
        keypsake_platform_windows::vault::load_key(file)
    }

    pub fn app_icon_png(bundle: &str) -> Option<Vec<u8>> {
        keypsake_platform_windows::icons::exe_icon_png(bundle, 64)
    }

    pub fn copy_text(text: &str) -> anyhow::Result<()> {
        keypsake_platform_windows::clipboard::write(text)
    }

    pub fn alert(title: &str, text: &str) {
        keypsake_platform_windows::alert(title, text)
    }
}

#[cfg(not(windows))]
mod imp {
    use keypsake_core::store::Store;
    use std::sync::Arc;

    pub struct Capture {
        pub typing_error: Option<String>,
        pub clipboard_error: Option<String>,
    }

    impl Capture {
        pub fn start(_: Arc<Store>, _: bool, _: usize) -> Capture {
            let e = Some("This build of keypsake doesn't record on this OS yet.".to_string());
            Capture { typing_error: e.clone(), clipboard_error: e }
        }
        pub fn set_paused(&self, _: bool) {}
        pub fn set_clip_limit(&self, _: usize) {}
    }

    /// Development only: an unprotected key file.
    pub fn load_key(file: &std::path::Path) -> anyhow::Result<[u8; 32]> {
        if let Ok(d) = std::fs::read(file) {
            return <[u8; 32]>::try_from(d.as_slice()).map_err(|_| anyhow::anyhow!("the key file is damaged"));
        }
        let key = keypsake_core::store::new_key();
        std::fs::write(file, key)?;
        Ok(key)
    }

    pub fn app_icon_png(_: &str) -> Option<Vec<u8>> {
        None
    }

    pub fn copy_text(_: &str) -> anyhow::Result<()> {
        anyhow::bail!("copying isn't supported on this OS yet")
    }

    pub fn alert(title: &str, text: &str) {
        eprintln!("{title}\n{text}");
    }
}

pub use imp::*;
