//! Post-hoc repair orchestrator: coalesce (fix over-cuts) then split (fix
//! over-joins).
//!
//! Order matters: [`crate::coalesce`] first re-joins think-pause fragments so
//! [`crate::split`] measures the *repaired* segment length against its
//! duration/chars gates. Split evidence aligns with the pre-coalesce steps and
//! is remapped across merges with [`SplitEvidence::or`] (a missed boundary in
//! either half still justifies splitting the whole).
//!
//! [`segment_text`] renders one step as a single eval unit: the text blob when
//! present, else a `<action:element>` placeholder so textless steps (clicks,
//! drags, app switches) still occupy segmentation units.

use flowline_ir::Step;

use crate::coalesce::{coalesce_steps, CoalesceReport};
use crate::split::{split_steps, SplitEvidence, SplitReport};

/// What the full repair pass did.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RepairReport {
    /// Adjacent pairs merged by the coalesce pass.
    pub merges: usize,
    /// Extra steps produced by the split pass.
    pub splits: usize,
    /// Step count before repair.
    pub input_steps: usize,
    /// Step count after repair.
    pub output_steps: usize,
}

impl RepairReport {
    /// Merge the two pass reports with input/output counts.
    pub fn new(
        input_steps: usize,
        output_steps: usize,
        coalesce: &CoalesceReport,
        split: &SplitReport,
    ) -> Self {
        Self {
            merges: coalesce.merges,
            splits: split.splits,
            input_steps,
            output_steps,
        }
    }
}

/// Render one step as a single segmentation unit.
pub fn segment_text(step: &Step) -> String {
    match step.text_blob.as_deref() {
        Some(text) if !text.trim().is_empty() => text.to_string(),
        _ => {
            let target = step
                .element_title
                .as_deref()
                .or(step.element_role.as_deref())
                .unwrap_or(step.app_name.as_str());
            format!("<{}:{target}>", step.action.raw_value())
        }
    }
}

/// Run coalesce then split over `steps`.
///
/// `evidences` aligns with the *input* steps (missing entries mean "no
/// evidence"); it is remapped across coalesce merges before splitting.
pub fn repair_segments(steps: Vec<Step>, evidences: &[SplitEvidence]) -> (Vec<Step>, RepairReport) {
    let input_steps = steps.len();
    let (merged, coalesce_report) = coalesce_steps(steps);
    let remapped: Vec<SplitEvidence> = coalesce_report
        .groups
        .iter()
        .map(|group| {
            group
                .iter()
                .map(|&i| evidences.get(i).copied().unwrap_or_default())
                .reduce(SplitEvidence::or)
                .unwrap_or_default()
        })
        .collect();
    let (out, split_report) = split_steps(merged, &remapped);
    let report = RepairReport::new(input_steps, out.len(), &coalesce_report, &split_report);
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
                    app_name: "Notes".to_string(),
                    bundle_identifier: Some("com.apple.Notes".to_string()),
                    window_title: "Draft".to_string(),
                    role: Some("AXTextField".to_string()),
                    subrole: None,
                    title: Some("Draft".to_string()),
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

    #[test]
    fn coalesce_runs_before_split() {
        // Two fragments that coalesce into an oversized, evidenced segment
        // which the split pass then re-splits on newlines.
        let big_a = format!("{}-part-one\n", "word ".repeat(120));
        let big_b = format!("{}-part-two\n{}", "word ".repeat(120), "tail ".repeat(40));
        let s1 = typing("a", "2026-03-01T10:00:00Z", &big_a);
        let mut s2 = typing("b", "2026-03-01T10:00:01.000Z", &big_b);
        // Force the coalesce vote: same context + proximity are not enough
        // alone, so add a paste marker for the continuation vote.
        s2.user_notes = Some("pasted".to_string());
        let ev = SplitEvidence {
            return_submit: true,
            ..SplitEvidence::default()
        };
        let (out, report) = repair_segments(vec![s1, s2], &[SplitEvidence::default(), ev]);
        assert_eq!(report.merges, 1, "fragments coalesce first");
        assert!(
            report.splits >= 1,
            "repaired segment still splits on newlines"
        );
        assert_eq!(report.input_steps, 2);
        assert_eq!(report.output_steps, out.len());
    }

    #[test]
    fn evidence_remaps_across_merges() {
        // Evidence attached to the second fragment must survive the merge and
        // still trigger a split of the repaired segment.
        let line = "selectABCDEFGH ".repeat(30);
        let text_a = format!("{line}\n");
        let text_b = format!("{line}\n{line}\n");
        let s1 = typing("a", "2026-03-01T10:00:00Z", &text_a);
        let mut s2 = typing("b", "2026-03-01T10:00:01.000Z", &text_b);
        s2.user_notes = Some("pasted from clipboard".to_string());
        let ev = SplitEvidence {
            return_submit: true,
            ..SplitEvidence::default()
        };
        let (out, report) = repair_segments(vec![s1, s2], &[SplitEvidence::default(), ev]);
        assert_eq!(report.merges, 1);
        assert!(report.splits >= 1, "remapped evidence triggers the split");
        assert!(out.len() >= 2);
    }

    #[test]
    fn segment_text_placeholders() {
        let t = typing("a", "2026-03-01T10:00:00Z", "hello");
        assert_eq!(segment_text(&t), "hello");
        let mut click = t.clone();
        click.text_blob = None;
        click.action = flowline_ir::ActionType::Click;
        click.element_title = Some("Save".to_string());
        assert_eq!(segment_text(&click), "<click:Save>");
    }
}
