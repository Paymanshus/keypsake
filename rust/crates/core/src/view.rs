//! Small decisions the UI shows, kept here so they are tested.

use crate::store::Snapshot;

/// If the latest version is much shorter than the longest, text was probably lost: preselect the longest.
pub fn default_version(s: &[Snapshot]) -> Option<i64> {
    let last = s.last()?;
    let mut longest = &s[0];
    for x in s {
        if x.length > longest.length {
            longest = x;
        }
    }
    Some(if last.length < longest.length / 2 { longest.id } else { last.id })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snap(id: i64, length: i64) -> Snapshot {
        Snapshot { id, created: 0.0, length, cliff: false, text: String::new() }
    }

    #[test]
    fn picks_longest_after_a_drop() {
        assert_eq!(default_version(&[]), None);
        assert_eq!(default_version(&[snap(1, 10), snap(2, 12)]), Some(2));
        assert_eq!(default_version(&[snap(1, 100), snap(2, 40)]), Some(1));
        assert_eq!(default_version(&[snap(1, 100), snap(2, 100), snap(3, 10)]), Some(1));
    }
}
