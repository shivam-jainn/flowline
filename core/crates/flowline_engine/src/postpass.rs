//! Session-level post-hoc repair: coalesce over-cuts, then split over-joins.
//!
//! Thin wrapper over [`flowline_pipeline::postpass`]: the pipeline owns the
//! pure repair logic (timestamp parsing included), the engine owns the
//! [`StepSession`] envelope. Repair preserves the envelope (id, title, theme,
//! media mode, exports) and only rewrites `steps` (plus `ended_at` is left
//! untouched — repair never extends a recording).

use flowline_ir::StepSession;

pub use flowline_pipeline::postpass::{repair_segments, segment_text, RepairReport};
pub use flowline_pipeline::split::SplitEvidence;

/// Repair one recorded session in place, returning what changed.
///
/// `evidences` aligns with the session's *input* steps (missing entries mean
/// "no evidence"); see [`flowline_pipeline::postpass::repair_segments`].
pub fn repair_session(session: &mut StepSession, evidences: &[SplitEvidence]) -> RepairReport {
    let steps = std::mem::take(&mut session.steps);
    let (repaired, report) = repair_segments(steps, evidences);
    session.steps = repaired;
    report
}

#[cfg(test)]
mod tests {
    use super::*;
    use flowline_ir::{ActionType, MediaAssets, Point2D, RawElementContext};

    fn typing_step(id: &str, index: i64, ts: &str, text: &str) -> flowline_ir::Step {
        let mut step = flowline_pipeline::step_factory::make_typing_step(
            index as i32,
            id,
            ts,
            &flowline_pipeline::aggregate::TypingBatchResult {
                text_blob: text.to_string(),
                context: Some(RawElementContext {
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
                classification: flowline_pipeline::classify::InputClassification::Text,
                location: Point2D::ZERO,
            },
            MediaAssets::default(),
            None,
            None,
        );
        step.action = ActionType::Typing;
        step
    }

    #[test]
    fn repairs_session_in_place_and_keeps_envelope() {
        let mut session = StepSession::new(
            "sess_00000001".to_string(),
            "2026-03-01T10:00:00Z".to_string(),
        );
        session.title = "Golden Session".to_string();
        session.steps = vec![
            typing_step(
                "s1",
                1,
                "2026-03-01T10:00:00Z",
                "Status update: backend migration is complete",
            ),
            typing_step(
                "s2",
                2,
                "2026-03-01T10:00:01.800Z",
                " Status update: backend migration is delayed",
            ),
        ];
        let report = repair_session(&mut session, &[]);
        assert_eq!(report.merges, 1);
        assert_eq!(session.steps.len(), 1);
        assert_eq!(session.id, "sess_00000001");
        assert_eq!(session.title, "Golden Session");
        assert_eq!(session.started_at, "2026-03-01T10:00:00Z");
        assert!(session.steps[0]
            .user_notes
            .as_deref()
            .unwrap()
            .contains("coalesced:think-pause"));
    }
}
