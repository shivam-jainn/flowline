//! Coalesce pass: repairs over-cuts (false cuts / think-pause splits).
//!
//! The typing debouncer cuts a batch on inactivity, so a think-pause inside
//! one burst of typing (or a pasted continuation) lands as two adjacent steps
//! `S1, S2` that document a single action. This pass re-joins them.
//!
//! Gate (both required):
//! - same bundle *and* same element (`bundle_identifier`, falling back to
//!   `app_name`; `element_role` + `element_title`).
//! - gap below the outer bound ([`COALESCE_OUTER_GAP_MS]).
//!
//! Vote (at least 2 of 3 required):
//! 1. `proximity`: gap < [`COALESCE_GAP_MS`] (2_500 ms).
//! 2. `similarity`: [`text_similarity]` of the two blobs > 0.6 (token Jaccard,
//!    case-insensitive).
//! 3. `continuation`: [`clipboard_chain`] (paste marker in `user_notes`, or one
//!    blob containing the other with >= 10 chars of overlap) *or* `S2` shorter
//!    than 5 chars with gap < [`COALESCE_SHORT_GAP_MS`] (3_000 ms).
//!
//! Textless steps (clicks, drags, app switches) score 0 on signals 2 and 3 by
//! construction, so they can never reach 2 votes and are never merged here.
//!
//! IR limitation (documented, not worked around): typing steps carry no field
//! identity — `StepFactory` sets `element_title` to `None` for `Text` (only
//! code steps keep a language tag) — so for typing, the element gate
//! degenerates to same-app + same-role. Cross-field safety then comes from
//! the vote: coincidentally similar text typed in two fields within 2.5 s
//! would merge, but in real streams a Tab navigation keypress lands between
//! the batches, so the typing steps are never adjacent to begin with.
//!
//! Merge semantics: when one blob contains the other (paste / restatement) the
//! longer wins; otherwise the blobs concatenate verbatim — spacing is whatever
//! the user typed, so mid-word think-pause cuts rejoin exactly. The merged
//! step keeps `S1`'s id/timestamp/context, is re-indexed by the caller, and is
//! labelled by appending `[coalesced:think-pause]` to `user_notes`.

use std::collections::HashSet;

use flowline_ir::Step;

use crate::time::parse_timestamp_millis;

/// Inner proximity bound: adjacent-step gap that votes for a merge.
pub const COALESCE_GAP_MS: u64 = 2_500;
/// Outer bound: pairs wider than this never merge (covers the S2-short case).
pub const COALESCE_OUTER_GAP_MS: u64 = 3_000;
/// Short-continuation bound: `S2` < 5 chars still merges below this gap.
pub const COALESCE_SHORT_GAP_MS: u64 = 3_000;
/// Token-Jaccard threshold for the similarity vote.
pub const SIMILARITY_THRESHOLD: f64 = 0.6;
/// `S2` text length (chars, trimmed) below which the short-continuation path applies.
pub const SHORT_CONTINUATION_CHARS: usize = 5;
/// Minimum containment overlap (chars) for the clipboard-chain signal.
pub const CLIPBOARD_OVERLAP_CHARS: usize = 10;
/// Label appended to `user_notes` on every merged step.
pub const COALESCE_LABEL: &str = "coalesced:think-pause";

/// Lowercase alphanumeric tokens (`"Update:"` -> `"update"`).
fn tokens(text: &str) -> Vec<String> {
    text.split_whitespace()
        .map(|t| {
            t.trim_matches(|c: char| !c.is_alphanumeric())
                .to_lowercase()
        })
        .filter(|t| !t.is_empty())
        .collect()
}

/// Token Jaccard similarity in `[0, 1]` (case-insensitive).
///
/// Empty-vs-anything scores 0 — including empty-vs-empty — so textless steps
/// never earn the similarity vote.
pub fn text_similarity(a: &str, b: &str) -> f64 {
    let ta = tokens(a);
    let tb = tokens(b);
    if ta.is_empty() || tb.is_empty() {
        return 0.0;
    }
    let set_a: HashSet<&str> = ta.iter().map(String::as_str).collect();
    let set_b: HashSet<&str> = tb.iter().map(String::as_str).collect();
    let inter = set_a.intersection(&set_b).count();
    let union = set_a.union(&set_b).count();
    if union == 0 {
        0.0
    } else {
        inter as f64 / union as f64
    }
}

fn mentions_paste(notes: Option<&str>) -> bool {
    match notes {
        Some(n) => {
            let lower = n.to_lowercase();
            lower.contains("paste") || lower.contains("clipboard")
        }
        None => false,
    }
}

/// Clipboard-chain signal: a paste marker in either step's `user_notes`, or
/// one blob containing the other with at least [`CLIPBOARD_OVERLAP_CHARS`]
/// chars of overlap (paste-then-edit / restatement).
pub fn clipboard_chain(s1: &Step, s2: &Step) -> bool {
    if mentions_paste(s1.user_notes.as_deref()) || mentions_paste(s2.user_notes.as_deref()) {
        return true;
    }
    match (s1.text_blob.as_deref(), s2.text_blob.as_deref()) {
        (Some(a), Some(b)) => {
            let (a_len, b_len) = (a.chars().count(), b.chars().count());
            (a.contains(b) && b_len >= CLIPBOARD_OVERLAP_CHARS)
                || (b.contains(a) && a_len >= CLIPBOARD_OVERLAP_CHARS)
        }
        _ => false,
    }
}

fn same_bundle(s1: &Step, s2: &Step) -> bool {
    match (&s1.bundle_identifier, &s2.bundle_identifier) {
        (Some(a), Some(b)) => a == b,
        _ => !s1.app_name.is_empty() && s1.app_name == s2.app_name,
    }
}

fn same_element(s1: &Step, s2: &Step) -> bool {
    s1.element_role == s2.element_role && s1.element_title == s2.element_title
}

/// The 2-of-3 vote for one adjacent pair.
#[derive(Debug, Clone, PartialEq)]
pub struct CoalesceVote {
    /// Gap in millis (`None` when either timestamp is unparseable).
    pub gap_ms: Option<u64>,
    /// Same bundle *and* same element gate.
    pub same_context: bool,
    /// Signal 1: gap < [`COALESCE_GAP_MS`].
    pub proximity: bool,
    /// Raw token-Jaccard score.
    pub similarity: f64,
    /// Signal 2: similarity > [`SIMILARITY_THRESHOLD`].
    pub similar: bool,
    /// Clipboard-chain sub-signal (paste marker or >= 10-char containment).
    pub chained: bool,
    /// Short-continuation sub-signal (`S2` < 5 chars, gap < 3_000 ms).
    pub short_continuation: bool,
    /// Signal 3: chained *or* short continuation.
    pub continuation: bool,
    /// Votes cast (0–3).
    pub votes: u8,
    /// Merge verdict: gate pass *and* outer gap *and* votes >= 2.
    pub merge: bool,
}

/// Evaluate one adjacent pair without mutating anything.
pub fn should_coalesce(s1: &Step, s2: &Step) -> CoalesceVote {
    let gap_ms = match (
        parse_timestamp_millis(&s1.timestamp),
        parse_timestamp_millis(&s2.timestamp),
    ) {
        (Some(a), Some(b)) => Some(b.saturating_sub(a)),
        _ => None,
    };
    let same_context = same_bundle(s1, s2) && same_element(s1, s2);
    let proximity = gap_ms.is_some_and(|g| g < COALESCE_GAP_MS);
    let similarity = match (s1.text_blob.as_deref(), s2.text_blob.as_deref()) {
        (Some(a), Some(b)) => text_similarity(a, b),
        _ => 0.0,
    };
    let similar = similarity > SIMILARITY_THRESHOLD;
    let chained = clipboard_chain(s1, s2);
    let s2_len = s2
        .text_blob
        .as_deref()
        .map(|t| t.trim().chars().count())
        .unwrap_or(usize::MAX);
    let short_continuation = s2.text_blob.is_some()
        && s2_len < SHORT_CONTINUATION_CHARS
        && gap_ms.is_some_and(|g| g < COALESCE_SHORT_GAP_MS);
    let continuation = chained || short_continuation;
    let votes = u8::from(proximity) + u8::from(similar) + u8::from(continuation);
    let merge = same_context && gap_ms.is_some_and(|g| g < COALESCE_OUTER_GAP_MS) && votes >= 2;
    CoalesceVote {
        gap_ms,
        same_context,
        proximity,
        similarity,
        similar,
        chained,
        short_continuation,
        continuation,
        votes,
        merge,
    }
}

/// Merge `S2` into `S1`: notes union, then text (superset wins, else
/// verbatim concatenation), description refresh for text steps, and the
/// `[coalesced:think-pause]` label.
fn merge_pair(s1: &Step, s2: &Step) -> Step {
    let mut merged = s1.clone();
    merged.user_notes = match (merged.user_notes, s2.user_notes.clone()) {
        (Some(a), Some(b)) if a.contains(&b) => Some(a),
        (Some(a), Some(b)) if b.contains(&a) => Some(b),
        (Some(a), Some(b)) => Some(format!("{a} {b}")),
        (Some(a), None) => Some(a),
        (None, Some(b)) => Some(b),
        (None, None) => None,
    };
    merged.text_blob = match (s1.text_blob.clone(), s2.text_blob.clone()) {
        (Some(a), Some(b)) => {
            if a.contains(&b) {
                Some(a)
            } else if b.contains(&a) {
                Some(b)
            } else {
                Some(format!("{a}{b}"))
            }
        }
        (Some(a), None) => Some(a),
        (None, Some(b)) => Some(b),
        (None, None) => None,
    };
    if matches!(
        merged.action,
        flowline_ir::ActionType::Typing | flowline_ir::ActionType::WriteCode
    ) {
        merged.action_description = crate::step_factory::synthesize_default_description(
            merged.action,
            merged.element_title.as_deref(),
            merged.element_role.as_deref(),
            &merged.app_name,
            &merged.window_title,
            merged.text_blob.as_deref(),
            merged.is_code,
        );
    }
    let label = format!("[{COALESCE_LABEL}]");
    merged.user_notes = match merged.user_notes {
        Some(notes) if !notes.contains(COALESCE_LABEL) => Some(format!("{notes} {label}")),
        Some(notes) => Some(notes),
        None => Some(label),
    };
    merged
}

/// What one output step was built from (input indices into the pre-pass vec).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoalesceReport {
    /// Number of merges performed.
    pub merges: usize,
    /// Input-index group per output step (used to remap split evidence).
    pub groups: Vec<Vec<usize>>,
}

/// Greedy left-to-right coalesce: a merged step is immediately re-compared
/// against the next input. Output is re-indexed 1-based.
pub fn coalesce_steps(steps: Vec<Step>) -> (Vec<Step>, CoalesceReport) {
    let mut out: Vec<Step> = Vec::with_capacity(steps.len());
    let mut groups: Vec<Vec<usize>> = Vec::with_capacity(steps.len());
    let mut merges = 0usize;

    for (i, step) in steps.into_iter().enumerate() {
        let merge_into_prev = match out.last() {
            Some(prev) => should_coalesce(prev, &step).merge,
            None => false,
        };
        if merge_into_prev {
            let prev = out.pop().expect("checked above");
            out.push(merge_pair(&prev, &step));
            groups.last_mut().expect("group exists").push(i);
            merges += 1;
        } else {
            out.push(step);
            groups.push(vec![i]);
        }
    }
    for (pos, step) in out.iter_mut().enumerate() {
        step.index = (pos + 1) as i64;
    }
    (out, CoalesceReport { merges, groups })
}

#[cfg(test)]
mod tests {
    use super::*;
    use flowline_ir::{ActionType, MediaAssets, Point2D};

    fn typing(
        id: &str,
        ts: &str,
        app: &str,
        bundle: Option<&str>,
        role: &str,
        title: &str,
        text: &str,
    ) -> Step {
        crate::step_factory::make_typing_step(
            1,
            id,
            ts,
            &crate::aggregate::TypingBatchResult {
                text_blob: text.to_string(),
                context: Some(flowline_ir::RawElementContext {
                    app_name: app.to_string(),
                    bundle_identifier: bundle.map(str::to_string),
                    window_title: "Draft".to_string(),
                    role: Some(role.to_string()),
                    subrole: None,
                    title: Some(title.to_string()),
                    value: None,
                    placeholder: None,
                    role_description: None,
                    is_secure: false,
                    bounding_box: None,
                    window_bounds: None,
                    selectors: Vec::new(),
                }),
                classification: crate::classify::InputClassification::Text,
                location: Point2D::ZERO,
            },
            MediaAssets::default(),
            None,
            None,
        )
    }

    fn click(id: &str, ts: &str, title: &str) -> Step {
        let ctx = flowline_ir::RawElementContext {
            app_name: "Safari".to_string(),
            bundle_identifier: Some("com.apple.Safari".to_string()),
            window_title: "Docs".to_string(),
            role: Some("AXButton".to_string()),
            subrole: None,
            title: Some(title.to_string()),
            value: None,
            placeholder: None,
            role_description: None,
            is_secure: false,
            bounding_box: None,
            window_bounds: None,
            selectors: Vec::new(),
        };
        crate::step_factory::make_click_step(
            1,
            id,
            ts,
            ActionType::Click,
            Point2D::new(1.0, 2.0),
            Some(&ctx),
            MediaAssets::default(),
            None,
        )
    }

    const T0: &str = "2026-03-01T10:00:00Z";

    #[test]
    fn similarity_token_jaccard() {
        assert_eq!(text_similarity("", ""), 0.0);
        assert_eq!(text_similarity("hello", ""), 0.0);
        assert_eq!(text_similarity("Hello World", "hello world"), 1.0);
        let s = text_similarity(
            "Status update: backend migration is complete",
            "Status update: backend migration is delayed",
        );
        assert!(s > SIMILARITY_THRESHOLD, "s={s}");
        assert!(text_similarity("alpha beta", "gamma delta") < SIMILARITY_THRESHOLD);
    }

    #[test]
    fn think_pause_revision_merges_on_proximity_plus_similarity() {
        let s1 = typing(
            "a",
            T0,
            "Notes",
            Some("com.apple.Notes"),
            "AXTextField",
            "Draft",
            "Status update: backend migration is complete",
        );
        let s2 = typing(
            "b",
            "2026-03-01T10:00:01.800Z",
            "Notes",
            Some("com.apple.Notes"),
            "AXTextField",
            "Draft",
            " Status update: backend migration is delayed",
        );
        let v = should_coalesce(&s1, &s2);
        assert_eq!(v.gap_ms, Some(1800));
        assert!(v.same_context && v.proximity && v.similar && !v.continuation);
        assert_eq!(v.votes, 2);
        assert!(v.merge);
        let (out, report) = coalesce_steps(vec![s1, s2]);
        assert_eq!(report.merges, 1);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].index, 1);
        assert!(out[0]
            .user_notes
            .as_deref()
            .unwrap()
            .contains(COALESCE_LABEL));
        assert_eq!(
            out[0].text_blob.as_deref(),
            Some("Status update: backend migration is complete Status update: backend migration is delayed")
        );
    }

    #[test]
    fn short_continuation_merges_without_similarity() {
        let s1 = typing(
            "a",
            T0,
            "Notes",
            Some("com.apple.Notes"),
            "AXTextField",
            "Draft",
            "Thanks for the update on the timeline",
        );
        let s2 = typing(
            "b",
            "2026-03-01T10:00:02.200Z",
            "Notes",
            Some("com.apple.Notes"),
            "AXTextField",
            "Draft",
            " soon",
        );
        let v = should_coalesce(&s1, &s2);
        assert!(v.proximity && !v.similar && v.short_continuation && v.continuation);
        assert!(v.merge);
        let (out, _) = coalesce_steps(vec![s1, s2]);
        assert_eq!(
            out[0].text_blob.as_deref(),
            Some("Thanks for the update on the timeline soon")
        );
    }

    #[test]
    fn paste_chain_prefers_superset() {
        let s1 = typing(
            "a",
            T0,
            "Notes",
            Some("com.apple.Notes"),
            "AXTextField",
            "Draft",
            "Report figures",
        );
        let mut s2 = typing(
            "b",
            "2026-03-01T10:00:00.600Z",
            "Notes",
            Some("com.apple.Notes"),
            "AXTextField",
            "Draft",
            "Report figures Q3 final pasted",
        );
        s2.user_notes = Some("pasted from Sheets".to_string());
        let v = should_coalesce(&s1, &s2);
        assert!(v.chained && v.proximity && !v.similar);
        assert!(v.merge);
        let (out, _) = coalesce_steps(vec![s1, s2]);
        assert_eq!(
            out[0].text_blob.as_deref(),
            Some("Report figures Q3 final pasted")
        );
        assert!(out[0]
            .user_notes
            .as_deref()
            .unwrap()
            .contains("pasted from Sheets"));
        assert!(out[0]
            .user_notes
            .as_deref()
            .unwrap()
            .contains(COALESCE_LABEL));
    }

    #[test]
    fn cross_field_tab_stays_split_without_similarity() {
        // Cross-field fast Tab: same app + 300 ms gap, but dissimilar text.
        // Typing steps carry no field identity in this IR (element_title is
        // None for Text), so same_context is true here — the vote still
        // refuses: only proximity fires (similarity 0, no chain, not short).
        let s1 = typing(
            "a",
            T0,
            "Safari",
            Some("com.apple.Safari"),
            "AXTextField",
            "Full Name",
            "Ada Lovelace",
        );
        let s2 = typing(
            "b",
            "2026-03-01T10:00:00.300Z",
            "Safari",
            Some("com.apple.Safari"),
            "AXTextField",
            "Email",
            "ada@example.com",
        );
        let v = should_coalesce(&s1, &s2);
        assert!(v.proximity && !v.similar && !v.continuation);
        assert_eq!(v.votes, 1);
        assert!(!v.merge);
        let (out, report) = coalesce_steps(vec![s1, s2]);
        assert_eq!(report.merges, 0);
        assert_eq!(out.len(), 2);
    }

    #[test]
    fn different_bundle_never_merges() {
        // Cmd-Tab flap: same title, different bundles.
        let mut s1 = typing(
            "a",
            T0,
            "Safari",
            Some("com.apple.Safari"),
            "AXTextField",
            "Draft",
            "hi",
        );
        let mut s2 = typing(
            "b",
            "2026-03-01T10:00:00.800Z",
            "Terminal",
            Some("com.apple.Terminal"),
            "AXTextField",
            "Draft",
            "hi",
        );
        // Force identical low-similarity texts so only the bundle differs.
        s1.text_blob = Some("alpha beta gamma delta".to_string());
        s2.text_blob = Some("alpha beta gamma delta".to_string());
        let v = should_coalesce(&s1, &s2);
        assert!(!v.same_context && v.similar && v.proximity && v.chained);
        assert_eq!(
            v.votes, 3,
            "identical texts vote 3x but the gate still blocks"
        );
        assert!(!v.merge, "gate blocks cross-bundle merges");
    }

    #[test]
    fn wide_gap_never_merges() {
        let s1 = typing(
            "a",
            T0,
            "Notes",
            Some("com.apple.Notes"),
            "AXTextField",
            "Draft",
            "Status update: backend migration is complete",
        );
        let s2 = typing(
            "b",
            "2026-03-01T10:00:05.000Z",
            "Notes",
            Some("com.apple.Notes"),
            "AXTextField",
            "Draft",
            " Status update: backend migration is delayed",
        );
        let v = should_coalesce(&s1, &s2);
        assert_eq!(v.gap_ms, Some(5000));
        assert!(!v.proximity && v.similar);
        assert!(!v.merge);
    }

    #[test]
    fn textless_steps_never_reach_two_votes() {
        // Rapid distinct clicks + jitter-drag: proximity alone is not enough.
        let c1 = click("a", T0, "Save");
        let c2 = click("b", "2026-03-01T10:00:00.150Z", "Save");
        let v = should_coalesce(&c1, &c2);
        assert_eq!(v.votes, 1, "only proximity votes for textless steps");
        assert!(!v.merge);
        let (out, report) = coalesce_steps(vec![c1, c2]);
        assert_eq!(report.merges, 0);
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].index, 1);
        assert_eq!(out[1].index, 2);
    }

    #[test]
    fn greedy_chain_merges_three_in_a_row() {
        let mk = |id: &str, ts: &str, text: &str| {
            typing(
                id,
                ts,
                "Notes",
                Some("com.apple.Notes"),
                "AXTextField",
                "Draft",
                text,
            )
        };
        let steps = vec![
            mk("a", T0, "Status update: backend migration is complete"),
            mk(
                "b",
                "2026-03-01T10:00:01.000Z",
                " Status update: backend migration is delayed",
            ),
            mk(
                "c",
                "2026-03-01T10:00:02.000Z",
                " Status update: backend migration is delayed again",
            ),
        ];
        let (out, report) = coalesce_steps(steps);
        assert_eq!(report.merges, 2);
        assert_eq!(out.len(), 1);
        assert_eq!(report.groups, vec![vec![0, 1, 2]]);
    }

    #[test]
    fn unparseable_timestamps_decline() {
        let mut s1 = typing(
            "a",
            T0,
            "Notes",
            Some("com.apple.Notes"),
            "AXTextField",
            "Draft",
            "Report figures",
        );
        let mut s2 = typing(
            "b",
            T0,
            "Notes",
            Some("com.apple.Notes"),
            "AXTextField",
            "Draft",
            "Report figures Q3",
        );
        s1.timestamp = "bogus".to_string();
        s2.timestamp = "also bogus".to_string();
        assert!(!should_coalesce(&s1, &s2).merge);
    }
}
