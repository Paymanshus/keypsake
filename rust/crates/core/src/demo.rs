//! `--demo`: made-up history for screenshots, the same story the macOS demo tells. Nothing is recorded.

use crate::store::{now, SourceContext, Store};
use serde::Deserialize;

pub const DATA: &str = include_str!("demo.json");

#[derive(Deserialize)]
struct Data {
    sessions: Vec<Session>,
    clips: Vec<DemoClip>,
}

#[derive(Deserialize)]
struct Session {
    app: String,
    bundle: String,
    domain: Option<String>,
    window: String,
    versions: Vec<Version>,
}

#[derive(Deserialize)]
struct Version {
    ago: f64,
    text: String,
    cliff: bool,
}

#[derive(Deserialize)]
struct DemoClip {
    app: String,
    bundle: String,
    domain: Option<String>,
    text: String,
    ago: f64,
}

/// `ago` values are minutes before now.
pub fn seed(store: &Store) {
    let data: Data = serde_json::from_str(DATA).expect("demo.json");
    let now = now();
    for s in &data.sessions {
        let ctx = SourceContext {
            app: s.app.clone(),
            bundle: Some(s.bundle.clone()),
            window: s.window.clone(),
            domain: s.domain.clone(),
        };
        let sid = store.create_session(&ctx);
        for v in &s.versions {
            let id = store.add_snapshot(sid, &ctx, &v.text, v.cliff);
            store.backdate_snapshot(id, now - v.ago * 60.0);
        }
        let first = s.versions.first().map_or(0.0, |v| v.ago);
        let last = s.versions.last().map_or(0.0, |v| v.ago);
        store.backdate_session(sid, now - first * 60.0, now - last * 60.0);
    }
    for c in data.clips.iter().rev() {
        let ctx = SourceContext {
            app: c.app.clone(),
            bundle: Some(c.bundle.clone()),
            window: String::new(),
            domain: c.domain.clone(),
        };
        store.add_clip(&c.text, &ctx, 50);
        if let Some(id) = store.latest_clip_id() {
            store.backdate_clip(id, now - c.ago * 60.0);
        }
    }
    store.reload();
}

#[cfg(test)]
mod tests {
    #[test]
    fn seeds() {
        let s = crate::store::Store::in_memory(&[0u8; 32]).unwrap();
        super::seed(&s);
        assert_eq!(s.sessions().len(), 7);
        assert_eq!(s.sessions()[0].domain.as_deref(), Some("mail.google.com"));
        assert_eq!(s.clips().len(), 8);
        assert_eq!(s.clips()[0].text, "https://github.com/Paymanshus/keypsake");
    }
}
