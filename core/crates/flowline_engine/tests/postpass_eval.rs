//! Session-level post-hoc repair eval (`flowline_engine::postpass`).
//!
//! Exercises the engine wrapper (envelope preservation + in-place step
//! rewrite) on the merge path (think-pause) and the split path
//! (terminal-multi). Prints the metric reports (visible with `-- --nocapture`).

use parity_harness::segmentation;
use flowline_engine::postpass::SplitEvidence;
use flowline_engine::postpass::{repair_session, segment_text};
use flowline_ir::{ActionType, MediaAssets, Step, StepSession};

fn build_step(spec: &segmentation::StepSpec, index: i64) -> Step {
    let action = match spec.action.as_str() {
        "typing" => ActionType::Typing,
        "write_code" => ActionType::WriteCode,
        "click" => ActionType::Click,
        "mouse_drag" => ActionType::MouseDrag,
        "app_switch" => ActionType::AppSwitch,
        "key_press" => ActionType::KeyPress,
        "manual" => ActionType::Manual,
        other => panic!("unknown action {other}"),
    };
    let mut step = Step {
        id: spec.id.clone(),
        index,
        timestamp: spec.timestamp.clone(),
        action,
        app_name: spec.app_name.clone(),
        bundle_identifier: spec.bundle_identifier.clone(),
        window_title: spec.window_title.clone(),
        element_role: spec.element_role.clone(),
        element_title: spec.element_title.clone(),
        element_value: None,
        coordinates: None,
        window_bounds: None,
        element_bounds: None,
        action_description: String::new(),
        user_notes: spec.user_notes.clone(),
        text_blob: spec.text_blob.clone(),
        is_code: action == ActionType::WriteCode,
        code_language: None,
        assets: MediaAssets::default(),
        working_directory: None,
        hotkey_combo: None,
        is_redacted: None,
    };
    step.ensure_description();
    step
}

fn to_evidence(spec: &segmentation::EvidenceSpec) -> SplitEvidence {
    SplitEvidence {
        missed_focus: spec.missed_focus,
        paste_with_app_change: spec.paste_with_app_change,
        return_submit: spec.return_submit,
        url_domain_change: spec.url_domain_change,
        terminal_prompt_count: spec.terminal_prompts,
    }
}

fn session_for(case: &segmentation::EvalCase) -> (StepSession, Vec<SplitEvidence>) {
    let mut session = StepSession::new(
        "sess_00000001".to_string(),
        case.steps
            .first()
            .map(|s| s.timestamp.clone())
            .unwrap_or_default(),
    );
    session.title = format!("eval {}", case.name);
    session.steps = case
        .steps
        .iter()
        .enumerate()
        .map(|(i, s)| build_step(s, (i + 1) as i64))
        .collect();
    let evidences = case.evidence.iter().map(to_evidence).collect();
    (session, evidences)
}

#[test]
fn session_repair_merge_path() {
    let case = segmentation::load_case("segmentation.think-pause.json");
    let (mut session, evidences) = session_for(&case);
    let before: Vec<String> = session.steps.iter().map(segment_text).collect();
    let report = repair_session(&mut session, &evidences);
    assert_eq!(report.merges, 1);
    assert_eq!(report.splits, 0);
    let after: Vec<String> = session.steps.iter().map(segment_text).collect();
    assert_eq!(after, case.expect.after);
    // Envelope preserved.
    assert_eq!(session.id, "sess_00000001");
    assert_eq!(session.title, "eval think-pause");
    assert_eq!(session.started_at, "2026-03-01T10:00:00Z");
    let before_scores = segmentation::evaluate(&case.reference, &before);
    let after_scores = segmentation::evaluate(&case.reference, &after);
    println!(
        "{}",
        segmentation::format_report(&case.name, &before_scores, &after_scores)
    );
    segmentation::check_gate(&after_scores, &case.baseline, &case.name).expect("CI gate");
}

#[test]
fn session_repair_split_path() {
    let case = segmentation::load_case("segmentation.terminal-multi.json");
    let (mut session, evidences) = session_for(&case);
    let before: Vec<String> = session.steps.iter().map(segment_text).collect();
    let report = repair_session(&mut session, &evidences);
    assert_eq!(report.merges, 0);
    assert_eq!(report.splits, 2);
    let after: Vec<String> = session.steps.iter().map(segment_text).collect();
    assert_eq!(after, case.expect.after);
    assert_eq!(session.steps.len(), 3);
    assert_eq!(session.steps[0].id, "s1");
    assert_eq!(session.steps[1].id, "s1-s2");
    assert_eq!(session.steps[2].id, "s1-s3");
    let before_scores = segmentation::evaluate(&case.reference, &before);
    let after_scores = segmentation::evaluate(&case.reference, &after);
    println!(
        "{}",
        segmentation::format_report(&case.name, &before_scores, &after_scores)
    );
    segmentation::check_gate(&after_scores, &case.baseline, &case.name).expect("CI gate");
}
