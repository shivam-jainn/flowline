//! Segmentation eval: false-cut / false-join rates, WindowDiff, Pk, F1.
//!
//! Compares a predicted segmentation against a reference segmentation of the
//! same unit sequence (characters of the concatenated segment strings; see
//! `flowline_pipeline::postpass::segment_text` for how steps map to units).
//!
//! Boundary metrics (exact boundary match on character offsets):
//! - `false_cut_rate` (over-segmentation): `FP / max(1, predicted cuts)` —
//!   fraction of predicted cuts that are spurious.
//! - `false_join_rate` (under-segmentation): `FN / max(1, true cuts)` —
//!   fraction of true cuts the prediction missed.
//! - `precision` / `recall` / `f1` on boundaries. Vacuous convention: no
//!   predicted cuts means precision 1, no true cuts means recall 1, so a
//!   perfect single-segment prediction scores `f1 = 1`.
//!
//! Window metrics (character positions, `k = max(1, round(mean ref length/2))`):
//! - `pk`: probability two positions `k` apart are misclassified as
//!   same/different segment (Beeferman et al.).
//! - `window_diff`: probability the reference and predicted boundary counts
//!   differ inside a sliding window of width `k` (Pevzner & Hearst) —
//!   forgiving of near misses that `pk` punishes.
//!
//! [`check_gate`] enforces the CI rule: after-repair scores must stay within
//! 2 percentage points of the golden [`Baseline`] (absolute tolerance 0.02).

use std::collections::HashSet;

/// One eval fixture (`shared/goldens/segmentation.*.json`; schema in
/// `shared/contracts/segmentation-eval.schema.json`).
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EvalCase {
    /// Case id (`segmentation.<name>.json` stem suffix).
    pub name: String,
    /// What real-world failure this reproduces.
    pub description: String,
    /// Reference segmentation (segment strings; order = time order).
    pub reference: Vec<String>,
    /// Pre-repair segmentation (over-cut or over-joined).
    pub before: Vec<String>,
    /// Input steps fed to the repair pass (compact spec, time order).
    pub steps: Vec<StepSpec>,
    /// Per-step raw-log evidence (aligns with `steps`; short = no evidence).
    #[serde(default)]
    pub evidence: Vec<EvidenceSpec>,
    /// Expected post-repair outcome.
    pub expect: ExpectSpec,
    /// Post-repair metric baselines the CI gate pins.
    pub baseline: Baseline,
}

/// Compact step spec inside an eval case.
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StepSpec {
    /// Step id.
    pub id: String,
    /// Wire timestamp (`YYYY-MM-DDTHH:MM:SS[.mmm]Z`).
    pub timestamp: String,
    /// `typing` | `write_code` | `click` | `mouse_drag` | `app_switch` |
    /// `key_press` | `manual`.
    pub action: String,
    /// Application name.
    pub app_name: String,
    /// Bundle identifier when known.
    #[serde(default)]
    pub bundle_identifier: Option<String>,
    /// Window title.
    #[serde(default)]
    pub window_title: String,
    /// Element role when known.
    #[serde(default)]
    pub element_role: Option<String>,
    /// Element title when known.
    #[serde(default)]
    pub element_title: Option<String>,
    /// Typed/command text blob when known.
    #[serde(default)]
    pub text_blob: Option<String>,
    /// User notes when known (paste markers live here).
    #[serde(default)]
    pub user_notes: Option<String>,
}

/// Raw-log evidence spec inside an eval case.
#[derive(Debug, Clone, Copy, Default, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EvidenceSpec {
    /// Raw log shows a focus change the engine never cut on.
    #[serde(default)]
    pub missed_focus: bool,
    /// A paste landed with an app change inside the segment.
    #[serde(default)]
    pub paste_with_app_change: bool,
    /// A Return submission boundary sits inside the segment.
    #[serde(default)]
    pub return_submit: bool,
    /// The page URL domain changed mid-segment.
    #[serde(default)]
    pub url_domain_change: bool,
    /// Terminal prompts observed inside the segment.
    #[serde(default)]
    pub terminal_prompts: u32,
}

/// Expected post-repair outcome.
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExpectSpec {
    /// Coalesce merges performed.
    pub merges: usize,
    /// Extra steps produced by the split pass.
    pub splits: usize,
    /// Post-repair segmentation (segment strings, time order).
    pub after: Vec<String>,
}

/// Post-repair metric baselines pinned by the golden.
#[derive(Debug, Clone, serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Baseline {
    /// Pinned post-repair false-cut rate.
    pub false_cut_rate: f64,
    /// Pinned post-repair false-join rate.
    pub false_join_rate: f64,
    /// Pinned post-repair segmentation F1.
    pub f1: f64,
}

/// Boundary + window scores for one (reference, predicted) pair.
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Scores {
    /// Character units scored.
    pub units: usize,
    /// Window width used for Pk / WindowDiff.
    pub window: usize,
    /// True boundary count.
    pub true_boundaries: usize,
    /// Predicted boundary count.
    pub pred_boundaries: usize,
    /// Exact boundary matches.
    pub true_positives: usize,
    /// Spurious predicted boundaries.
    pub false_positives: usize,
    /// Missed true boundaries.
    pub false_negatives: usize,
    /// Non-boundary agreements.
    pub true_negatives: usize,
    /// `TP / (TP + FP)` (1 when nothing predicted).
    pub precision: f64,
    /// `TP / (TP + FN)` (1 when no true boundaries).
    pub recall: f64,
    /// Harmonic mean of precision/recall.
    pub f1: f64,
    /// `FP / max(1, predicted cuts)` — over-segmentation rate.
    pub false_cut_rate: f64,
    /// `FN / max(1, true cuts)` — under-segmentation rate.
    pub false_join_rate: f64,
    /// Beeferman Pk (lower is better).
    pub pk: f64,
    /// Pevzner–Hearst WindowDiff (lower is better).
    pub window_diff: f64,
}

/// Load an eval case from `shared/goldens/<name>`.
pub fn load_case(name: &str) -> EvalCase {
    let raw = crate::load_golden(name);
    serde_json::from_str(&raw).unwrap_or_else(|e| panic!("eval case {name} parses: {e}"))
}

/// Cumulative character offsets of segment boundaries (excludes the end) plus
/// the total length.
fn offsets(segments: &[String]) -> (Vec<usize>, usize) {
    let mut bounds = Vec::new();
    let mut acc = 0usize;
    for (i, seg) in segments.iter().enumerate() {
        acc += seg.chars().count();
        if i + 1 < segments.len() {
            bounds.push(acc);
        }
    }
    (bounds, acc)
}

/// Segment id per character position (truncated to `n`).
fn labels(segments: &[String], n: usize) -> Vec<usize> {
    let mut out = Vec::with_capacity(n);
    for (id, seg) in segments.iter().enumerate() {
        for _ in 0..seg.chars().count() {
            if out.len() >= n {
                return out;
            }
            out.push(id);
        }
    }
    while out.len() < n {
        out.push(segments.len());
    }
    out
}

/// Count of `bounds` inside `(lo, hi]`.
fn count_in(bounds: &[usize], lo: usize, hi: usize) -> usize {
    bounds.iter().filter(|&&b| b > lo && b <= hi).count()
}

/// Score one (reference, predicted) segmentation pair.
pub fn evaluate(reference: &[String], predicted: &[String]) -> Scores {
    let (ref_bounds, ref_total) = offsets(reference);
    let (pred_bounds, pred_total) = offsets(predicted);
    let ref_set: HashSet<usize> = ref_bounds.iter().copied().collect();

    let true_positives = pred_bounds.iter().filter(|b| ref_set.contains(b)).count();
    let false_positives = pred_bounds.len() - true_positives;
    let false_negatives = ref_bounds
        .iter()
        .filter(|b| !pred_bounds.contains(b))
        .count();
    let units = ref_total.max(pred_total);
    let true_negatives = units
        .saturating_sub(1)
        .saturating_sub(true_positives + false_positives + false_negatives);

    let precision = if true_positives + false_positives == 0 {
        1.0
    } else {
        true_positives as f64 / (true_positives + false_positives) as f64
    };
    let recall = if true_positives + false_negatives == 0 {
        1.0
    } else {
        true_positives as f64 / (true_positives + false_negatives) as f64
    };
    let f1 = if precision + recall == 0.0 {
        0.0
    } else {
        2.0 * precision * recall / (precision + recall)
    };
    let false_cut_rate = false_positives as f64 / (pred_bounds.len().max(1)) as f64;
    let false_join_rate = false_negatives as f64 / (ref_bounds.len().max(1)) as f64;

    // Window metrics over the common prefix (goldens share the full text, so
    // the prefix is the whole sequence in practice).
    let mean_ref = if reference.is_empty() {
        0.0
    } else {
        ref_total as f64 / reference.len() as f64
    };
    let window = (mean_ref / 2.0).round() as usize;
    let window = window.max(1);
    let n = ref_total.min(pred_total);
    let (pk, window_diff) = if n <= window {
        (0.0, 0.0)
    } else {
        let ref_lab = labels(reference, n);
        let pred_lab = labels(predicted, n);
        let mut pk_miss = 0usize;
        let mut wd_miss = 0usize;
        for i in 0..n - window {
            let ref_same = ref_lab[i] == ref_lab[i + window];
            let pred_same = pred_lab[i] == pred_lab[i + window];
            if ref_same != pred_same {
                pk_miss += 1;
            }
            if count_in(&ref_bounds, i, i + window) != count_in(&pred_bounds, i, i + window) {
                wd_miss += 1;
            }
        }
        let denom = (n - window) as f64;
        (pk_miss as f64 / denom, wd_miss as f64 / denom)
    };

    Scores {
        units,
        window,
        true_boundaries: ref_bounds.len(),
        pred_boundaries: pred_bounds.len(),
        true_positives,
        false_positives,
        false_negatives,
        true_negatives,
        precision,
        recall,
        f1,
        false_cut_rate,
        false_join_rate,
        pk,
        window_diff,
    }
}

/// Absolute CI tolerance: no metric may regress more than 2 points.
pub const GATE_TOLERANCE: f64 = 0.02;

/// Enforce the CI gate: after-repair scores within tolerance of the baseline.
pub fn check_gate(after: &Scores, baseline: &Baseline, case: &str) -> Result<(), String> {
    let mut violations = Vec::new();
    if after.false_cut_rate > baseline.false_cut_rate + GATE_TOLERANCE {
        violations.push(format!(
            "false_cut_rate {:.4} exceeds baseline {:.4} + 0.02",
            after.false_cut_rate, baseline.false_cut_rate
        ));
    }
    if after.false_join_rate > baseline.false_join_rate + GATE_TOLERANCE {
        violations.push(format!(
            "false_join_rate {:.4} exceeds baseline {:.4} + 0.02",
            after.false_join_rate, baseline.false_join_rate
        ));
    }
    if after.f1 < baseline.f1 - GATE_TOLERANCE {
        violations.push(format!(
            "f1 {:.4} below baseline {:.4} - 0.02",
            after.f1, baseline.f1
        ));
    }
    if violations.is_empty() {
        Ok(())
    } else {
        Err(format!("gate failed for {case}: {}", violations.join("; ")))
    }
}

/// One printable line per case: before → after with deltas.
pub fn format_report(name: &str, before: &Scores, after: &Scores) -> String {
    format!(
        "{name:>18}: cuts {bc:.3}->{ac:.3} (Δ{dc:+.3})  joins {bj:.3}->{aj:.3} (Δ{dj:+.3})  \
         F1 {bf:.3}->{af:.3} (Δ{df:+.3})  Pk {bp:.3}->{ap:.3}  WD {bw:.3}->{aw:.3}",
        bc = before.false_cut_rate,
        ac = after.false_cut_rate,
        dc = after.false_cut_rate - before.false_cut_rate,
        bj = before.false_join_rate,
        aj = after.false_join_rate,
        dj = after.false_join_rate - before.false_join_rate,
        bf = before.f1,
        af = after.f1,
        df = after.f1 - before.f1,
        bp = before.pk,
        ap = after.pk,
        bw = before.window_diff,
        aw = after.window_diff,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|x| x.to_string()).collect()
    }

    #[test]
    fn perfect_pair_scores_one() {
        let a = evaluate(
            &s(&["hello world", "foo bar"]),
            &s(&["hello world", "foo bar"]),
        );
        assert_eq!((a.false_cut_rate, a.false_join_rate), (0.0, 0.0));
        assert_eq!((a.precision, a.recall, a.f1), (1.0, 1.0, 1.0));
        assert_eq!((a.pk, a.window_diff), (0.0, 0.0));
    }

    #[test]
    fn perfect_single_segment_scores_one() {
        let a = evaluate(&s(&["hello world"]), &s(&["hello world"]));
        assert_eq!(a.f1, 1.0);
        assert_eq!((a.false_cut_rate, a.false_join_rate), (0.0, 0.0));
    }

    #[test]
    fn spurious_cut_rates() {
        let a = evaluate(&s(&["hello world"]), &s(&["hello", " world"]));
        assert_eq!(a.false_positives, 1);
        assert_eq!(a.false_cut_rate, 1.0);
        assert_eq!(a.false_join_rate, 0.0);
        assert_eq!(a.f1, 0.0);
        assert!(a.pk > 0.0 && a.window_diff > 0.0);
    }

    #[test]
    fn missed_cut_rates() {
        let a = evaluate(&s(&["hello", " world"]), &s(&["hello world"]));
        assert_eq!(a.false_negatives, 1);
        assert_eq!(a.false_join_rate, 1.0);
        assert_eq!(a.false_cut_rate, 0.0);
        assert_eq!(a.f1, 0.0);
    }

    #[test]
    fn gate_allows_two_points() {
        let base = Baseline {
            false_cut_rate: 0.0,
            false_join_rate: 0.0,
            f1: 1.0,
        };
        let ok = evaluate(&s(&["ab"]), &s(&["ab"]));
        assert!(check_gate(&ok, &base, "x").is_ok());
        let mut bad = ok.clone();
        bad.false_cut_rate = 0.021;
        assert!(check_gate(&bad, &base, "x").is_err());
        bad.false_cut_rate = 0.02;
        assert!(
            check_gate(&bad, &base, "x").is_ok(),
            "boundary is inclusive"
        );
    }
}
