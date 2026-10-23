//! User settings, stored as JSON next to the database. Defaults match the macOS build.

use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Prefs {
    pub paused: bool,
    pub retention_days: u32,
    pub clip_limit: usize,
    /// Accelerator strings, e.g. "Ctrl+Alt+K".
    pub shortcut_open: String,
    pub shortcut_pause: String,
    pub show_changes: bool,
}

pub const RETENTION_CHOICES: [u32; 4] = [7, 30, 90, 365];
pub const CLIP_CHOICES: [usize; 5] = [25, 50, 100, 250, 500];

impl Default for Prefs {
    fn default() -> Self {
        Prefs {
            paused: false,
            retention_days: 30,
            clip_limit: 50,
            shortcut_open: "Ctrl+Alt+K".into(),
            shortcut_pause: "Ctrl+Alt+P".into(),
            show_changes: true,
        }
    }
}

impl Prefs {
    pub fn load(path: &Path) -> Prefs {
        std::fs::read(path).ok().and_then(|d| serde_json::from_slice(&d).ok()).unwrap_or_default()
    }

    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        let tmp = path.with_extension("tmp");
        std::fs::write(&tmp, serde_json::to_vec_pretty(self).unwrap_or_default())?;
        std::fs::rename(tmp, path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_fields_fall_back_to_defaults() {
        let p: Prefs = serde_json::from_str(r#"{"clipLimit": 100}"#).unwrap();
        assert_eq!(p.clip_limit, 100);
        assert_eq!(p.retention_days, 30);
        assert!(p.show_changes);
    }
}
