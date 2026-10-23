//! Word-level comparison between two versions, rendered as plain prose:
//! added words get a carbon highlight, removed words stay in place struck through in amber.

use serde::Serialize;
use similar::{capture_diff_slices, Algorithm, DiffOp};
use std::collections::HashSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Same,
    Added,
    Removed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Span {
    pub text: String,
    pub kind: Kind,
}

#[derive(Debug, Clone, Serialize)]
pub struct Result {
    pub spans: Vec<Span>,
    pub added: usize,
    pub removed: usize,
}

/// Words and the whitespace between them, so the text reassembles exactly.
pub fn tokens(s: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    let mut in_space: Option<bool> = None;
    for (i, c) in s.char_indices() {
        let space = c.is_whitespace();
        if let Some(cur) = in_space {
            if cur != space {
                out.push(&s[start..i]);
                start = i;
            }
        }
        in_space = Some(space);
    }
    if start < s.len() {
        out.push(&s[start..]);
    }
    out
}

fn is_space(t: &str) -> bool {
    t.chars().all(char::is_whitespace)
}

/// None when the texts are too long to compare word by word.
pub fn compare(old: &str, new: &str) -> Option<Result> {
    let a = tokens(old);
    let b = tokens(new);
    if a.len() + b.len() >= 40_000 {
        return None; // ponytail: diff is O(n·d); skip giant texts
    }
    let mut removed_at = HashSet::new();
    let mut inserted_at = HashSet::new();
    for op in capture_diff_slices(Algorithm::Myers, &a, &b) {
        match op {
            DiffOp::Equal { .. } => {}
            DiffOp::Delete { old_index, old_len, .. } => removed_at.extend(old_index..old_index + old_len),
            DiffOp::Insert { new_index, new_len, .. } => inserted_at.extend(new_index..new_index + new_len),
            DiffOp::Replace { old_index, old_len, new_index, new_len } => {
                removed_at.extend(old_index..old_index + old_len);
                inserted_at.extend(new_index..new_index + new_len);
            }
        }
    }

    let mut spans: Vec<Span> = Vec::new();
    let mut push = |text: &str, kind: Kind| match spans.last_mut() {
        Some(last) if last.kind == kind => last.text.push_str(text),
        _ => spans.push(Span { text: text.to_string(), kind }),
    };
    let (mut i, mut j, mut added, mut removed) = (0, 0, 0, 0);
    while i < a.len() || j < b.len() {
        if i < a.len() && removed_at.contains(&i) {
            let t = a[i];
            if !is_space(t) {
                push(t, Kind::Removed);
                push(" ", Kind::Same);
                removed += 1;
            }
            i += 1;
        } else if j < b.len() && inserted_at.contains(&j) {
            let t = b[j];
            let ws = is_space(t);
            // Spaces between two added words are highlighted too, so an added phrase reads as one block.
            let joined = ws && !t.contains('\n') && inserted_at.contains(&(j + 1));
            push(t, if ws && !joined { Kind::Same } else { Kind::Added });
            if !ws {
                added += 1;
            }
            j += 1;
        } else {
            if j < b.len() {
                push(b[j], Kind::Same);
            }
            i += 1;
            j += 1;
        }
    }
    Some(Result { spans, added, removed })
}

pub fn summary(r: &Result) -> String {
    let words = |n: usize| if n == 1 { "1 word".to_string() } else { format!("{n} words") };
    match (r.added, r.removed) {
        (0, 0) => "Same words as the version before".into(),
        (_, 0) => format!("{} added", words(r.added)),
        (0, _) => format!("{} removed", words(r.removed)),
        _ => format!("{} added, {} removed", words(r.added), r.removed),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn render(r: &Result) -> String {
        r.spans
            .iter()
            .map(|s| match s.kind {
                Kind::Same => s.text.clone(),
                Kind::Added => format!("[+{}]", s.text),
                Kind::Removed => format!("[-{}]", s.text),
            })
            .collect()
    }

    #[test]
    fn matches_swift_self_check() {
        let r = compare("the quick brown fox", "the slow brown fox jumps").unwrap();
        assert_eq!((r.added, r.removed), (2, 1));
        assert_eq!(summary(&r), "2 words added, 1 removed");
    }

    #[test]
    fn tokens_reassemble() {
        let s = "one  two\nthree ";
        assert_eq!(tokens(s).concat(), s);
        assert_eq!(tokens(s), vec!["one", "  ", "two", "\n", "three", " "]);
    }

    #[test]
    fn added_phrase_is_one_block() {
        let r = compare("hello world", "hello big new world").unwrap();
        assert_eq!(render(&r), "hello [+big new] world");
        assert_eq!(summary(&r), "2 words added");
    }

    #[test]
    fn removed_words_stay_in_place() {
        let r = compare("keep this word", "keep word").unwrap();
        assert_eq!(render(&r), "keep [-this] word");
        assert_eq!(summary(&r), "1 word removed");
    }

    #[test]
    fn same_text() {
        let r = compare("a b", "a b").unwrap();
        assert_eq!(summary(&r), "Same words as the version before");
    }

    #[test]
    fn giant_texts_are_skipped() {
        let big = "w ".repeat(20_000);
        assert!(compare(&big, &big).is_none());
    }
}
