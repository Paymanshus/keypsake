//! String helpers shared by capture and the store. Counts are grapheme clusters, matching Swift's `String.count`.

use unicode_segmentation::UnicodeSegmentation;

/// Longest text kept per box or per copy.
pub const MAX_LENGTH: usize = 200_000;

/// Character count as the user sees it (and as the macOS build stores it).
pub fn len(s: &str) -> usize {
    s.graphemes(true).count()
}

/// Length after trimming surrounding whitespace and newlines.
pub fn trimmed_len(s: &str) -> usize {
    len(s.trim())
}

/// The first `n` characters.
pub fn prefix(s: &str, n: usize) -> &str {
    match s.char_indices().nth(n) {
        Some((i, _)) => &s[..i],
        None => s,
    }
}

/// The last `n` characters.
pub fn suffix(s: &str, n: usize) -> &str {
    let count = s.chars().count();
    if count <= n {
        return s;
    }
    match s.char_indices().nth(count - n) {
        Some((i, _)) => &s[i..],
        None => s,
    }
}

fn is_private_use(c: char) -> bool {
    matches!(c as u32, 0xE000..=0xF8FF | 0xF0000..=0xFFFFD | 0x100000..=0x10FFFD)
}

/// Drops invisible placeholders apps embed in text values (U+FFFC attachments, private-use icon glyphs).
pub fn clean(s: &str) -> String {
    if !s.chars().any(|c| c == '\u{FFFC}' || is_private_use(c)) {
        return s.to_string();
    }
    s.chars().filter(|&c| c != '\u{FFFC}' && !is_private_use(c)).collect()
}

/// The part of `full` that differs from `baseline`: everything between the common start and common end.
pub fn region(full: &str, baseline: &str) -> String {
    if baseline.is_empty() {
        return full.to_string();
    }
    let x: Vec<char> = full.chars().collect();
    let y: Vec<char> = baseline.chars().collect();
    let m = x.len().min(y.len());
    let mut p = 0;
    while p < m && x[p] == y[p] {
        p += 1;
    }
    let mut s = 0;
    while s < m - p && x[x.len() - 1 - s] == y[y.len() - 1 - s] {
        s += 1;
    }
    let (lo, hi) = (p, x.len() - s);
    if lo < hi {
        x[lo..hi].iter().collect()
    } else {
        String::new()
    }
}

/// The baseline is read right after the first keystroke, which may already be in the box. Take it back out.
/// `caret` is the insertion point in characters, after the keystroke landed.
pub fn without_just_typed(v: &str, typed: Option<&str>, caret: Option<usize>) -> String {
    let (Some(typed), Some(caret)) = (typed, caret) else { return v.to_string() };
    let mut it = typed.chars();
    let (Some(c), None) = (it.next(), it.next()) else { return v.to_string() };
    if (c as u32) < 0x20 || caret == 0 {
        return v.to_string();
    }
    let mut chars: Vec<char> = v.chars().collect();
    let i = caret - 1;
    if i >= chars.len() || chars[i] != c {
        return v.to_string();
    }
    chars.remove(i);
    chars.into_iter().collect()
}

/// Removes the last word and the whitespace after it (Option-Delete on macOS, Ctrl+Backspace on Windows).
pub fn delete_word(s: &mut String) {
    let trimmed = s.trim_end_matches(|c: char| c.is_whitespace()).len();
    let word = s[..trimmed].trim_end_matches(|c: char| !c.is_whitespace()).len();
    s.truncate(word);
}

/// Collapses whitespace runs to single spaces over the first `n` characters, for one-line previews.
pub fn one_line(s: &str, n: usize) -> String {
    prefix(s, n).split_whitespace().collect::<Vec<_>>().join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn region_matches_swift_self_check() {
        assert_eq!(region("hello big world", "hello world"), "big ");
        assert_eq!(region("note\nnew line", "note\n"), "new line");
        assert_eq!(region("abc", ""), "abc");
        assert_eq!(region("same", "same"), "");
        assert_eq!(region("ab😀cd", "abcd"), "😀");
    }

    #[test]
    fn clean_drops_placeholders() {
        assert_eq!(clean("\u{FFFC}jp.yaml"), "jp.yaml");
        assert_eq!(clean("a\u{E001}b"), "ab");
        assert_eq!(clean("plain"), "plain");
    }

    #[test]
    fn just_typed_is_removed_at_caret() {
        assert_eq!(without_just_typed("helxlo", Some("x"), Some(4)), "hello");
        assert_eq!(without_just_typed("hello", Some("x"), Some(4)), "hello");
        assert_eq!(without_just_typed("hello", None, Some(4)), "hello");
        assert_eq!(without_just_typed("hello", Some("\n"), Some(1)), "hello");
    }

    #[test]
    fn delete_word_eats_word_and_trailing_space() {
        let mut s = "one two  ".to_string();
        delete_word(&mut s);
        assert_eq!(s, "one ");
        delete_word(&mut s);
        assert_eq!(s, "");
    }

    #[test]
    fn counts_are_graphemes() {
        assert_eq!(len("e\u{301}"), 1);
        assert_eq!(len("👍🏽"), 1);
        assert_eq!(trimmed_len("  ab \n"), 2);
        assert_eq!(prefix("héllo", 2), "hé");
        assert_eq!(suffix("héllo", 3), "llo");
        assert_eq!(one_line("a\n\n b  c", 300), "a b c");
    }
}
