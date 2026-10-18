//! Split pass: repairs over-joins (false joins / runaway segments).
//!
//! Runs *after* [`crate::coalesce`]: a segment that is too long is only split
//! when high-confidence raw-log evidence says a boundary was missed. Either
//! size gate arms the pass:
//! - estimated duration > [`SPLIT_DURATION_MS`] (30 s, measured to the next
//!   step's timestamp; the last step has duration 0), or
//! - text length > [`SPLIT_CHAR_LEN`] (500 chars).
//!
//! Split triggers (any one suffices; all come from the raw log, never from
//! heuristics over the step text alone):
//! - `terminal-prompts`: terminal prompt count > 1 (multi-command segment);
//! - `return-submit`: a Return submission boundary inside the segment;
//! - `url-domain-change`: the raw log saw the page domain change mid-segment;
//! - `paste-app-change`: a paste landed with an app change inside the segment;
//! - `missed-focus`: the raw log shows a focus change the engine never cut on.
//!
//! Splitting prefers newline boundaries (Return-submit / terminal commands),
//! then URL-domain boundaries, then sentence boundaries, then word-balanced
//! chunks (terminal prompts ask for exactly N pieces). Pieces are re-indexed
//! by the caller, keep the original id on the first piece (`<id>-s2…` after),
//! interpolate timestamps across the segment duration, and are labelled
//! `[split:<primary-trigger>]` in `user_notes`. Steps without text never
//! split.

use flowline_ir::Step;

use crate::time::{format_millis, parse_timestamp_millis};

/// Duration gate: segments longer than this are split candidates.
pub const SPLIT_DURATION_MS: u64 = 30_000;
/// Character gate: blobs longer than this are split candidates.
pub const SPLIT_CHAR_LEN: usize = 500;
/// Prompt-count gate: more than this many terminal prompts is a split trigger.
pub const SPLIT_TERMINAL_PROMPT_THRESHOLD: u32 = 1;
/// Upper bound on terminal pieces (keeps pathological prompt counts bounded).
pub const SPLIT_MAX_PIECES: usize = 8;

/// Raw-log evidence for one step (aligned by position; missing entries mean
/// "no evidence"). Only high-confidence triggers — anything weaker must not
/// reach this struct.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct SplitEvidence {
    /// Raw log shows a focus change the engine never cut on.
    pub missed_focus: bool,
    /// A paste landed with an app change inside the segment.
    pub paste_with_app_change: bool,
    /// A Return submission boundary sits inside the segment.
    pub return_submit: bool,
    /// The page URL domain changed mid-segment.
    pub url_domain_change: bool,
    /// Terminal prompts observed inside the segment.
    pub terminal_prompt_count: u32,
}

impl SplitEvidence {
    /// Active triggers in priority order (first = primary split reason).
    pub fn triggers(&self) -> Vec<&'static str> {
        let mut out = Vec::new();
        if self.terminal_prompt_count > SPLIT_TERMINAL_PROMPT_THRESHOLD {
            out.push("terminal-prompts");
        }
        if self.return_submit {
            out.push("return-submit");
        }
        if self.url_domain_change {
            out.push("url-domain-change");
        }
        if self.paste_with_app_change {
            out.push("paste-app-change");
        }
        if self.missed_focus {
            out.push("missed-focus");
        }
        out
    }

    /// Any high-confidence trigger present.
    pub fn has_high_confidence_trigger(&self) -> bool {
        !self.triggers().is_empty()
    }

    /// Union of two evidences (used when coalesce merges two steps: a missed
    /// boundary in either half still justifies splitting the whole).
    pub fn or(self, other: Self) -> Self {
        Self {
            missed_focus: self.missed_focus || other.missed_focus,
            paste_with_app_change: self.paste_with_app_change || other.paste_with_app_change,
            return_submit: self.return_submit || other.return_submit,
            url_domain_change: self.url_domain_change || other.url_domain_change,
            terminal_prompt_count: self.terminal_prompt_count.max(other.terminal_prompt_count),
        }
    }
}

/// Size gate + evidence check. Returns the active triggers when this step
/// must split, `None` otherwise.
pub fn should_split(
    step: &Step,
    duration_ms: u64,
    evidence: &SplitEvidence,
) -> Option<Vec<&'static str>> {
    let len = step
        .text_blob
        .as_deref()
        .map(|t| t.chars().count())
        .unwrap_or(0);
    if len == 0 {
        return None;
    }
    let oversized = duration_ms > SPLIT_DURATION_MS || len > SPLIT_CHAR_LEN;
    if oversized && evidence.has_high_confidence_trigger() {
        Some(evidence.triggers())
    } else {
        None
    }
}

/// Estimated segment duration: next step's timestamp minus this step's
/// (0 for the last step or unparseable timestamps).
pub fn segment_duration_ms(step: &Step, next: Option<&Step>) -> u64 {
    match (parse_timestamp_millis(&step.timestamp), next) {
        (Some(a), Some(n)) => parse_timestamp_millis(&n.timestamp)
            .map(|b| b.saturating_sub(a))
            .unwrap_or(0),
        _ => 0,
    }
}

fn non_empty_lines(text: &str) -> Vec<String> {
    text.split('\n')
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(str::to_string)
        .collect()
}

/// Sentence split on `.`/`!`/`?` followed by whitespace (keeps the closer).
fn split_sentences(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut start = 0usize;
    let bytes = text.as_bytes();
    let mut i = 0usize;
    while i < bytes.len() {
        let c = bytes[i];
        if (c == b'.' || c == b'!' || c == b'?')
            && bytes.get(i + 1).is_some_and(|n| n.is_ascii_whitespace())
        {
            let piece = text[start..=i].trim().to_string();
            if !piece.is_empty() {
                out.push(piece);
            }
            start = i + 1;
        }
        i += 1;
    }
    let tail = text[start..].trim().to_string();
    if !tail.is_empty() {
        out.push(tail);
    }
    out
}

/// Split words into `n` contiguous, roughly balanced chunks.
fn chunk_words(text: &str, n: usize) -> Vec<String> {
    let words: Vec<&str> = text.split_whitespace().collect();
    if words.is_empty() || n <= 1 || words.len() <= n {
        return vec![text.trim().to_string()];
    }
    let n = n.min(words.len()).min(SPLIT_MAX_PIECES);
    let base = words.len() / n;
    let mut extra = words.len() % n;
    let mut out = Vec::with_capacity(n);
    let mut idx = 0usize;
    for _ in 0..n {
        let mut take = base;
        if extra > 0 {
            take += 1;
            extra -= 1;
        }
        out.push(words[idx..idx + take].join(" "));
        idx += take;
    }
    out
}

/// Find the two URLs' domains in `text` and split between them when they
/// differ. Returns `None` when fewer than two distinct domains are present.
fn split_on_domain_change(text: &str) -> Option<Vec<String>> {
    let domains: Vec<(usize, String)> = {
        let mut found = Vec::new();
        for marker in ["https://", "http://"] {
            let mut rest = text;
            let mut base = 0usize;
            while let Some(pos) = rest.find(marker) {
                let abs_url = base + pos + marker.len();
                let tail = &text[abs_url..];
                let end = tail
                    .find(['/', ' ', '"', '\n', ')'])
                    .map(|e| abs_url + e)
                    .unwrap_or(text.len());
                let domain = text[abs_url..end].to_lowercase();
                if !domain.is_empty() {
                    found.push((abs_url, domain));
                }
                rest = &rest[pos + marker.len()..];
                base += pos + marker.len();
            }
        }
        found.sort_by_key(|(pos, _)| *pos);
        found
    };
    let first_change = domains
        .windows(2)
        .find(|w| w[0].1 != w[1].1)
        .map(|w| w[1].0)?;
    // Split at the whitespace before the second domain's URL when possible.
    let cut = text[..first_change]
        .rfind(char::is_whitespace)
        .unwrap_or(first_change);
    let (a, b) = (text[..cut].trim(), text[cut..].trim());
    if a.is_empty() || b.is_empty() {
        None
    } else {
        Some(vec![a.to_string(), b.to_string()])
    }
}

/// Choose piece boundaries for `text` given the active evidence.
pub fn split_text(text: &str, evidence: &SplitEvidence) -> Vec<String> {
    // 1. Newlines are Return-submit / terminal-command boundaries.
    let lines = non_empty_lines(text);
    if lines.len() >= 2 {
        if evidence.terminal_prompt_count > SPLIT_TERMINAL_PROMPT_THRESHOLD {
            let want = (evidence.terminal_prompt_count as usize)
                .clamp(2, SPLIT_MAX_PIECES)
                .min(lines.len());
            if want < lines.len() {
                // Regroup lines into `want` contiguous chunks.
                let mut out = Vec::with_capacity(want);
                let base = lines.len() / want;
                let mut extra = lines.len() % want;
                let mut idx = 0usize;
                for _ in 0..want {
                    let mut take = base;
                    if extra > 0 {
                        take += 1;
                        extra -= 1;
                    }
                    out.push(lines[idx..idx + take].join("\n"));
                    idx += take;
                }
                return out;
            }
        }
        return lines;
    }
    // 2. URL domain change: split between the differing domains.
    if evidence.url_domain_change {
        if let Some(pieces) = split_on_domain_change(text) {
            return pieces;
        }
    }
    // 3. Sentences: halves, or prompt-count chunks for terminal text.
    let sentences = split_sentences(text);
    if sentences.len() >= 2 {
        if evidence.terminal_prompt_count > SPLIT_TERMINAL_PROMPT_THRESHOLD {
            let want = (evidence.terminal_prompt_count as usize)
                .clamp(2, SPLIT_MAX_PIECES)
                .min(sentences.len());
            if want > 2 {
                let joined = sentences.join(" ");
                return chunk_words(&joined, want);
            }
        }
        let mid = sentences.len() / 2;
        return vec![sentences[..mid].join(" "), sentences[mid..].join(" ")];
    }
    // 4. Fallback: word-balanced chunks (N for terminal, else halves).
    let n = if evidence.terminal_prompt_count > SPLIT_TERMINAL_PROMPT_THRESHOLD {
        (evidence.terminal_prompt_count as usize).clamp(2, SPLIT_MAX_PIECES)
    } else {
        2
    };
    let chunks = chunk_words(text, n);
    if chunks.len() >= 2 {
        chunks
    } else {
        vec![text.trim().to_string()]
    }
}

/// Split one step into pieces (first keeps the id, rest get `<id>-s<N>`).
/// Returns a single-element vec when no clean boundary exists.
pub fn split_step(
    step: &Step,
    evidence: &SplitEvidence,
    start_ms: Option<u64>,
    duration_ms: u64,
) -> Vec<Step> {
    let text = step.text_blob.as_deref().unwrap_or("").trim().to_string();
    if text.is_empty() {
        return vec![step.clone()];
    }
    let pieces = split_text(&text, evidence);
    if pieces.len() < 2 {
        return vec![step.clone()];
    }
    let triggers = evidence.triggers();
    let primary = triggers.first().copied().unwrap_or("evidence");
    let label = format!("[split:{primary}]");
    let count = pieces.len() as u64;
    pieces
        .into_iter()
        .enumerate()
        .map(|(i, piece)| {
            let mut part = step.clone();
            if i > 0 {
                part.id = format!("{}-s{}", step.id, i + 1);
            }
            part.text_blob = Some(piece);
            if matches!(
                part.action,
                flowline_ir::ActionType::Typing | flowline_ir::ActionType::WriteCode
            ) {
                part.action_description = crate::step_factory::synthesize_default_description(
                    part.action,
                    part.element_title.as_deref(),
                    part.element_role.as_deref(),
                    &part.app_name,
                    &part.window_title,
                    part.text_blob.as_deref(),
                    part.is_code,
                );
            }
            if let Some(start) = start_ms {
                if duration_ms > 0 {
                    part.timestamp = format_millis(start + i as u64 * duration_ms / count);
                }
            }
            part.user_notes = match part.user_notes {
                Some(notes) if !notes.contains(&label) => Some(format!("{notes} {label}")),
                Some(notes) => Some(notes),
                None => Some(label.clone()),
            };
            part
        })
        .collect()
}

/// What the split pass did.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct SplitReport {
    /// Extra steps produced (`sum(pieces) - splits`).
    pub splits: usize,
    /// Input indices that were split.
    pub split_inputs: Vec<usize>,
    /// Primary trigger per split input.
    pub reasons: Vec<String>,
}

/// Split every oversized, high-evidence step. Output is re-indexed 1-based.
pub fn split_steps(steps: Vec<Step>, evidences: &[SplitEvidence]) -> (Vec<Step>, SplitReport) {
    let mut out: Vec<Step> = Vec::with_capacity(steps.len());
    let mut report = SplitReport::default();

    for (i, step) in steps.iter().enumerate() {
        let next = steps.get(i + 1);
        let duration = segment_duration_ms(step, next);
        let evidence = evidences.get(i).copied().unwrap_or_default();
        match should_split(step, duration, &evidence) {
            Some(triggers) => {
                let start = parse_timestamp_millis(&step.timestamp);
                let pieces = split_step(step, &evidence, start, duration);
                if pieces.len() >= 2 {
                    report.splits += pieces.len() - 1;
                    report.split_inputs.push(i);
                    report
                        .reasons
                        .push(triggers.first().copied().unwrap_or("evidence").to_string());
                    out.extend(pieces);
                    continue;
                }
                out.push(step.clone());
            }
            None => out.push(step.clone()),
        }
    }
    for (pos, step) in out.iter_mut().enumerate() {
        step.index = (pos + 1) as i64;
    }
    (out, report)
}

#[cfg(test)]
mod tests {
    use super::*;
    use flowline_ir::{MediaAssets, Point2D};

    fn typing(id: &str, ts: &str, text: &str) -> Step {
        crate::step_factory::make_typing_step(
            1,
            id,
            ts,
            &crate::aggregate::TypingBatchResult {
                text_blob: text.to_string(),
                context: Some(flowline_ir::RawElementContext {
                    app_name: "Ghostty".to_string(),
                    bundle_identifier: Some("com.mitchellh.ghostty".to_string()),
                    window_title: "zsh".to_string(),
                    role: None,
                    subrole: None,
                    title: None,
                    value: None,
                    placeholder: None,
                    role_description: None,
                    is_secure: false,
                    bounding_box: None,
                    window_bounds: None,
                    selectors: Vec::new(),
                }),
                classification: crate::classify::InputClassification::Terminal,
                location: Point2D::ZERO,
            },
            MediaAssets::default(),
            Some("~/Code"),
            None,
        )
    }

    fn long_commands() -> String {
        // Three newline-separated commands, ~880 chars total (oversized).
        let a = format!(
            "git log --oneline --graph {}",
            "--decorate --all ".repeat(30)
        );
        let b = format!("npm run test:workspace {}", "--reporter=spec ".repeat(30));
        let c = format!("docker build --pull {}", "--build-arg X=Y ".repeat(30));
        format!("{a}\n{b}\n{c}")
    }

    const T0: &str = "2026-03-01T10:00:00Z";

    #[test]
    fn gates_require_size_and_evidence() {
        let step = typing("a", T0, "short");
        let ev = SplitEvidence {
            terminal_prompt_count: 3,
            ..SplitEvidence::default()
        };
        assert!(should_split(&step, 0, &ev).is_none(), "short + no duration");
        assert!(
            should_split(&step, 45_000, &SplitEvidence::default()).is_none(),
            "long duration without evidence"
        );
        assert!(
            should_split(&step, 45_000, &ev).is_some(),
            "long duration + prompts splits"
        );
        let big = typing("b", T0, &"x ".repeat(300));
        assert!(
            should_split(&big, 0, &ev).is_some(),
            "chars>500 + prompts splits"
        );
        // Textless steps never split.
        let mut click = step.clone();
        click.text_blob = None;
        assert!(should_split(&click, 60_000, &ev).is_none());
    }

    #[test]
    fn terminal_newlines_split_into_commands() {
        let text = long_commands();
        assert!(
            text.chars().count() > SPLIT_CHAR_LEN,
            "fixture is oversized"
        );
        let ev = SplitEvidence {
            terminal_prompt_count: 3,
            return_submit: true,
            ..SplitEvidence::default()
        };
        let step = typing("a", T0, &text);
        let pieces = split_text(&text, &ev);
        assert_eq!(pieces.len(), 3);
        let out = split_step(&step, &ev, parse_timestamp_millis(T0), 0);
        assert_eq!(out.len(), 3);
        assert_eq!(out[0].id, "a");
        assert_eq!(out[1].id, "a-s2");
        assert_eq!(out[2].id, "a-s3");
        assert!(
            out.iter().all(|s| s
                .user_notes
                .as_deref()
                .unwrap()
                .contains("[split:terminal-prompts]")),
            "primary trigger labels every piece"
        );
    }

    #[test]
    fn sentence_fallback_halves() {
        let text = "First we provision the cluster. Then we deploy the canary. Then we flip traffic. Then we verify.";
        let ev = SplitEvidence {
            missed_focus: true,
            ..SplitEvidence::default()
        };
        let pieces = split_text(text, &ev);
        assert_eq!(pieces.len(), 2);
        assert!(pieces[0].contains("provision"));
        assert!(pieces[1].contains("verify"));
    }

    #[test]
    fn domain_change_splits_between_domains() {
        let text = "Read the guide at https://docs.example.com/setup then compare https://other.dev/setup for details on setup";
        let ev = SplitEvidence {
            url_domain_change: true,
            ..SplitEvidence::default()
        };
        let pieces = split_text(text, &ev);
        assert_eq!(pieces.len(), 2);
        assert!(pieces[0].contains("docs.example.com"));
        assert!(pieces[1].contains("other.dev"));
    }

    #[test]
    fn duration_splits_and_interpolates_timestamps() {
        let text = "Alpha phase complete and signed off by reviewers. Beta phase begins with the rollout plan and oncall rotation.";
        let a = typing("a", T0, text);
        let b = typing("b", "2026-03-01T10:01:00Z", "next");
        let ev = SplitEvidence {
            missed_focus: true,
            ..SplitEvidence::default()
        };
        let duration = segment_duration_ms(&a, Some(&b));
        assert_eq!(duration, 60_000);
        assert!(should_split(&a, duration, &ev).is_some());
        let (out, report) = split_steps(vec![a, b], &[ev, SplitEvidence::default()]);
        assert_eq!(report.splits, 1);
        assert_eq!(report.reasons, vec!["missed-focus".to_string()]);
        assert_eq!(out.len(), 3);
        assert_eq!(out[0].timestamp, T0);
        assert_eq!(out[1].timestamp, "2026-03-01T10:00:30Z");
        assert_eq!(out[2].timestamp, "2026-03-01T10:01:00Z");
        assert_eq!(out[2].index, 3);
    }

    #[test]
    fn no_evidence_is_identity() {
        let a = typing("a", T0, &"y ".repeat(300));
        let (out, report) = split_steps(vec![a], &[]);
        assert_eq!(report.splits, 0);
        assert_eq!(out.len(), 1);
    }
}
