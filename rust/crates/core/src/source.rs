//! Which apps are browsers, which hold secrets, which are terminals. Lists are per OS; the logic is shared.

/// The app a keystroke or copy came from. `id` is what the lists match against:
/// the lowercase exe file name on Windows (a bundle id on macOS).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppRef {
    pub pid: u32,
    pub id: String,
    pub name: String,
    /// Stored as the `bundle` column: the exe path on Windows, used for the app icon.
    pub bundle: Option<String>,
}

pub struct Lists {
    pub browsers: &'static [&'static str],
    /// ponytail: fixed skip lists; a user-editable blocklist comes later.
    pub secrets: &'static [&'static str],
    /// Terminals expose the whole scrollback as one text box, so only keystrokes count there.
    pub keys_only: &'static [&'static str],
    /// keypsake itself.
    pub own: &'static [&'static str],
}

impl Lists {
    pub fn is_browser(&self, id: &str) -> bool {
        self.browsers.contains(&id)
    }
    pub fn is_secret(&self, id: &str) -> bool {
        self.secrets.contains(&id)
    }
    pub fn is_skipped(&self, id: &str) -> bool {
        self.is_secret(id) || self.own.contains(&id)
    }
    pub fn is_keys_only(&self, id: &str) -> bool {
        self.keys_only.contains(&id)
    }
}

pub const WINDOWS: Lists = Lists {
    browsers: &[
        "chrome.exe",
        "msedge.exe",
        "brave.exe",
        "firefox.exe",
        "opera.exe",
        "vivaldi.exe",
        "arc.exe",
        "zen.exe",
        "chromium.exe",
        "comet.exe",
        "librewolf.exe",
        "waterfox.exe",
        "floorp.exe",
    ],
    secrets: &[
        "1password.exe",
        "bitwarden.exe",
        "keepass.exe",
        "keepassxc.exe",
        "dashlane.exe",
        "enpass.exe",
        "credentialuibroker.exe",
        "consent.exe",
        "logonui.exe",
    ],
    keys_only: &[
        "windowsterminal.exe",
        "conhost.exe",
        "openconsole.exe",
        "cmd.exe",
        "powershell.exe",
        "pwsh.exe",
        "wezterm-gui.exe",
        "alacritty.exe",
        "mintty.exe",
        "tabby.exe",
        "hyper.exe",
        "warp.exe",
        "wsl.exe",
    ],
    own: &["keypsake.exe"],
};

/// Strips a leading "www." so github.com and www.github.com group together.
pub fn domain_of(url: &str) -> Option<String> {
    let rest = url.split_once("://")?;
    if !matches!(rest.0.to_ascii_lowercase().as_str(), "http" | "https") {
        return None;
    }
    let host = rest.1.split(['/', '?', '#']).next()?;
    let host = host.rsplit_once('@').map(|(_, h)| h).unwrap_or(host);
    let host = host.split(':').next()?.to_ascii_lowercase();
    if host.is_empty() {
        return None;
    }
    Some(host.strip_prefix("www.").map(str::to_string).unwrap_or(host))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn domains() {
        assert_eq!(domain_of("https://www.github.com/a/b").as_deref(), Some("github.com"));
        assert_eq!(domain_of("http://mail.google.com:443?x").as_deref(), Some("mail.google.com"));
        assert_eq!(domain_of("about:blank"), None);
        assert_eq!(domain_of("file:///C:/x.html"), None);
    }

    #[test]
    fn lists() {
        assert!(WINDOWS.is_skipped("1password.exe"));
        assert!(WINDOWS.is_skipped("keypsake.exe"));
        assert!(WINDOWS.is_keys_only("windowsterminal.exe"));
        assert!(WINDOWS.is_browser("msedge.exe"));
    }
}
