//! Real site icons, fetched from the site itself (no third-party icon service). This part picks the URLs.

use regex::Regex;
use std::sync::OnceLock;
use url::Url;

/// How long a site with no usable icon is left alone before trying again.
pub const MISS_DAYS: u64 = 7;

/// Prefer apple-touch-icon (large), then the biggest declared `<link rel=icon>`, then /favicon.ico.
pub fn candidates(html: &str, base: &Url) -> Vec<Url> {
    static TAG: OnceLock<Regex> = OnceLock::new();
    let tag = TAG.get_or_init(|| Regex::new(r"(?i)<link\b[^>]*>").unwrap());
    let attr = |name: &str, s: &str| -> Option<String> {
        let re = Regex::new(&format!(r#"(?i)\b{name}\s*=\s*["']([^"']*)["']"#)).ok()?;
        re.captures(s).map(|c| c[1].to_string())
    };
    let mut found: Vec<(u32, Url)> = Vec::new();
    for m in tag.find_iter(html) {
        let s = m.as_str();
        let (Some(rel), Some(href)) = (attr("rel", s).map(|r| r.to_lowercase()), attr("href", s)) else { continue };
        if !rel.contains("icon") {
            continue;
        }
        let Ok(url) = base.join(&href.replace("&amp;", "&")) else { continue };
        let size = attr("sizes", s)
            .and_then(|v| v.to_lowercase().split('x').next().and_then(|n| n.parse().ok()))
            .unwrap_or(16);
        found.push((if rel.contains("apple-touch") { 1000 + size } else { size }, url));
    }
    found.sort_by_key(|f| std::cmp::Reverse(f.0));
    let mut out: Vec<Url> = found.into_iter().map(|f| f.1).collect();
    if let Ok(ico) = base.join("/favicon.ico") {
        out.push(ico);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ranks_icons() {
        let html = r#"<link rel="icon" href="/s.png" sizes="16x16"><LINK REL='icon' href="big.png" sizes="96x96">
                      <link href="/touch.png" rel="apple-touch-icon"><link rel="stylesheet" href="x.css">"#;
        let base = Url::parse("https://example.com/a/").unwrap();
        let urls: Vec<String> = candidates(html, &base).iter().map(|u| u.to_string()).collect();
        assert_eq!(
            urls,
            [
                "https://example.com/touch.png",
                "https://example.com/a/big.png",
                "https://example.com/s.png",
                "https://example.com/favicon.ico"
            ]
        );
    }
}
