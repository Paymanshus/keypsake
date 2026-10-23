//! Real icons for the UI, as data URLs: app icons from disk, favicons fetched straight from the site.

use base64::Engine;
use keypsake_core::favicon::{candidates, MISS_DAYS};
use std::collections::HashMap;
use std::io::Cursor;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::Duration;
use url::Url;

pub struct Icons {
    dir: PathBuf,
    apps: Mutex<HashMap<String, Option<String>>>,
    sites: Mutex<HashMap<String, Option<String>>>,
}

fn data_url(png: &[u8]) -> String {
    format!("data:image/png;base64,{}", base64::engine::general_purpose::STANDARD.encode(png))
}

/// Domains come from captured page URLs; only plain host names become file names.
fn safe_domain(d: &str) -> bool {
    !d.is_empty()
        && d.len() < 254
        && !d.starts_with('.')
        && d.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-')
}

impl Icons {
    pub fn new(dir: PathBuf) -> Icons {
        let _ = std::fs::create_dir_all(&dir);
        Icons { dir, apps: Mutex::default(), sites: Mutex::default() }
    }

    pub fn app(&self, bundle: &str) -> Option<String> {
        if let Some(v) = self.apps.lock().unwrap().get(bundle) {
            return v.clone();
        }
        let v = crate::platform::app_icon_png(bundle).map(|p| data_url(&p));
        self.apps.lock().unwrap().insert(bundle.to_string(), v.clone());
        v
    }

    pub async fn site(&self, domain: &str) -> Option<String> {
        let domain = domain.to_ascii_lowercase();
        if !safe_domain(&domain) {
            return None;
        }
        if let Some(v) = self.sites.lock().unwrap().get(&domain) {
            return v.clone();
        }
        let file = self.dir.join(format!("{domain}.png"));
        let miss = self.dir.join(format!("{domain}.miss"));
        let v = if let Ok(png) = std::fs::read(&file) {
            Some(data_url(&png))
        } else if std::fs::metadata(&miss)
            .and_then(|m| m.modified())
            .is_ok_and(|t| t.elapsed().unwrap_or_default() < Duration::from_secs(MISS_DAYS * 86400))
        {
            None
        } else {
            match fetch(&domain).await {
                Some(png) => {
                    let _ = std::fs::write(&file, &png);
                    Some(data_url(&png))
                }
                None => {
                    let _ = std::fs::write(&miss, b"");
                    None
                }
            }
        };
        self.sites.lock().unwrap().insert(domain, v.clone());
        v
    }
}

async fn fetch(domain: &str) -> Option<Vec<u8>> {
    let client = reqwest::Client::builder().timeout(Duration::from_secs(8)).user_agent("keypsake").build().ok()?;
    let home = Url::parse(&format!("https://{domain}/")).ok()?;
    let mut urls = vec![];
    if let Ok(resp) = client.get(home.clone()).send().await {
        let base = resp.url().clone();
        if let Ok(body) = resp.bytes().await {
            let html = String::from_utf8_lossy(&body[..body.len().min(300_000)]).into_owned();
            urls = candidates(&html, &base);
        }
    }
    if urls.is_empty() {
        urls = candidates("", &home);
    }
    for url in urls {
        let Ok(resp) = client.get(url).send().await else { continue };
        let Ok(bytes) = resp.bytes().await else { continue };
        let Ok(img) = image::load_from_memory(&bytes) else { continue };
        if img.width() == 0 {
            continue;
        }
        let img = if img.width() > 128 { img.resize(128, 128, image::imageops::FilterType::Lanczos3) } else { img };
        let mut png = Vec::new();
        if img.write_to(&mut Cursor::new(&mut png), image::ImageFormat::Png).is_ok() {
            return Some(png);
        }
    }
    None
}
