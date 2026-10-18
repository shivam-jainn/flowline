//! Post-hoc repair eval (false cuts / false joins) vs
//! `shared/goldens/segmentation.*.json`.
//!
//! For each golden: build input [`Step`]s from the compact spec, assert the
//! pre-repair rendering matches `before` (fixture consistency), run
//! [`repair_segments`], assert the outcome matches `expect`, score
//! before/after with [`segmentation::evaluate`], print the metric report
//! (visible with `-- --nocapture`), and enforce the CI gate: after-repair
//! scores within 2pp of `baseline`, and no 2pp regression vs pre-repair.

use parity_harness::segmentation;
use flowline_ir::{ActionType, MediaAssets, Step};
use flowline_pipeline::postpass::{repair_segments, segment_text};
use flowline_pipeline::split::SplitEvidence;

const CASES: &[&str] = &[
    "segmentation.think-pause.json",
    "segmentation.cross-field-tab.json",
    "segmentation.rapid-clicks.json",
    "segmentation.jitter-drag.json",
    "segmentation.cmd-tab-flap.json",
    "segmentation.paste-burst.json",
    "segmentation.terminal-multi.json",
];

fn build_step(spec: &segmentation::StepSpec) -> Step {
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
        index: 0,
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

#[test]
fn repair_eval_over_seven_goldens() {
    for name in CASES {
        let case = segmentation::load_case(name);
        let steps: Vec<Step> = case.steps.iter().map(build_step).collect();
        let evidences: Vec<SplitEvidence> = case.evidence.iter().map(to_evidence).collect();

        let before_strings: Vec<String> = steps.iter().map(segment_text).collect();
        assert_eq!(
            before_strings, case.before,
            "fixture consistency (pre-repair rendering) for {}",
            case.name
        );

        let (after_steps, report) = repair_segments(steps, &evidences);
        assert_eq!(
            report.merges, case.expect.merges,
            "merges for {}",
            case.name
        );
        assert_eq!(
            report.splits, case.expect.splits,
            "splits for {}",
            case.name
        );
        let after_strings: Vec<String> = after_steps.iter().map(segment_text).collect();
        assert_eq!(
            after_strings, case.expect.after,
            "post-repair segmentation for {}",
            case.name
        );
        // Re-indexed 1-based with no gaps.
        for (pos, step) in after_steps.iter().enumerate() {
            assert_eq!(step.index, (pos + 1) as i64, "re-index for {}", case.name);
        }

        let before_scores = segmentation::evaluate(&case.reference, &before_strings);
        let after_scores = segmentation::evaluate(&case.reference, &after_strings);
        println!(
            "{}",
            segmentation::format_report(&case.name, &before_scores, &after_scores)
        );

        segmentation::check_gate(&after_scores, &case.baseline, &case.name)
            .expect("CI gate: no +2pp regression vs golden baseline");
        assert!(
            after_scores.false_cut_rate <= before_scores.false_cut_rate + 0.02,
            "no false-cut regression for {}",
            case.name
        );
        assert!(
            after_scores.false_join_rate <= before_scores.false_join_rate + 0.02,
            "no false-join regression for {}",
            case.name
        );
        assert!(
            after_scores.f1 >= before_scores.f1 - 0.02,
            "no F1 regression for {}",
            case.name
        );
    }
}
