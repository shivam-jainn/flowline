//! Harness-level metric checks: synthetic segmentations exercising
//! false-cut / false-join rates, WindowDiff, Pk, and F1. Prints a sample
//! report (visible with `-- --nocapture`).

use parity_harness::segmentation::{self, Baseline};

fn s(v: &[&str]) -> Vec<String> {
    v.iter().map(|x| x.to_string()).collect()
}

#[test]
fn synthetic_over_cut_and_repair() {
    let reference = s(&["Status update: backend migration is complete"]);
    let over_cut = s(&["Status update: backend", " migration is complete"]);
    let before = segmentation::evaluate(&reference, &over_cut);
    let after = segmentation::evaluate(&reference, &reference);
    println!(
        "{}",
        segmentation::format_report("synthetic-cut", &before, &after)
    );
    assert_eq!(before.false_cut_rate, 1.0);
    assert_eq!(before.false_join_rate, 0.0);
    assert_eq!(before.f1, 0.0);
    assert!(before.pk > 0.0);
    assert!(before.window_diff > 0.0);
    assert_eq!(
        (after.false_cut_rate, after.false_join_rate, after.f1),
        (0.0, 0.0, 1.0)
    );
    assert_eq!((after.pk, after.window_diff), (0.0, 0.0));
    let baseline = Baseline {
        false_cut_rate: 0.0,
        false_join_rate: 0.0,
        f1: 1.0,
    };
    segmentation::check_gate(&after, &baseline, "synthetic-cut").expect("gate passes");
    segmentation::check_gate(&before, &baseline, "synthetic-cut").expect_err("over-cut fails gate");
}

#[test]
fn synthetic_over_join_and_repair() {
    let reference = s(&["git status", "npm test", "docker build"]);
    let over_joined = s(&["git status\nnpm test\ndocker build"]);
    let before = segmentation::evaluate(&reference, &over_joined);
    let after = segmentation::evaluate(&reference, &reference);
    println!(
        "{}",
        segmentation::format_report("synthetic-join", &before, &after)
    );
    assert_eq!(before.false_join_rate, 1.0);
    assert_eq!(before.false_cut_rate, 0.0);
    assert_eq!(before.f1, 0.0);
    assert_eq!(
        (after.false_cut_rate, after.false_join_rate, after.f1),
        (0.0, 0.0, 1.0)
    );
}
