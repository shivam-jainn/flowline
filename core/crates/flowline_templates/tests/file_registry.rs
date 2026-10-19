//! File-based template registry: every `templates/*/manifest.json` parses
//! via [`flowline_templates::load_manifest_json`] / validates via
//! [`flowline_templates::validate_manifest`] and matches the built-in
//! [`flowline_templates::GuideTemplate::all`] catalogue.

use flowline_templates::{load_manifest_json, validate_manifest, GuideTemplate};
use std::path::PathBuf;

/// Repo `templates/` dir resolved at runtime via `CARGO_MANIFEST_DIR`
/// (`core/crates/flowline_templates` → repo root → `templates/`).
fn templates_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("..")
        .join("templates")
}

fn manifest_ids() -> [&'static str; 7] {
    [
        "standard",
        "checklist",
        "sop",
        "tutorial",
        "runbook",
        "presentation",
        "reference",
    ]
}

/// All 7 `templates/*/manifest.json` files validate and parse to the
/// catalogue entries (runtime read via `CARGO_MANIFEST_DIR`).
#[test]
fn file_manifests_match_catalogue() {
    let dir = templates_dir();
    let mut seen = Vec::new();
    for id in manifest_ids() {
        let path = dir.join(id).join("manifest.json");
        let raw = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("missing manifest {}: {e}", path.display()));
        validate_manifest(&raw).unwrap_or_else(|e| panic!("manifest {id} failed validation: {e}"));
        let parsed = load_manifest_json(&raw)
            .unwrap_or_else(|e| panic!("manifest {id} failed to load: {e}"));
        assert_eq!(parsed.id, id, "parsed id");
        let expected =
            GuideTemplate::make(id).unwrap_or_else(|| panic!("unknown catalogue id {id}"));
        assert_eq!(parsed, expected, "manifest {id} must equal catalogue entry");
        seen.push(parsed.id.clone());
    }
    seen.sort();
    let mut catalogue: Vec<String> = GuideTemplate::all().iter().map(|t| t.id.clone()).collect();
    catalogue.sort();
    assert_eq!(
        seen, catalogue,
        "file registry must cover GuideTemplate::all()"
    );
    assert_eq!(
        seen,
        vec![
            "checklist",
            "presentation",
            "reference",
            "runbook",
            "sop",
            "standard",
            "tutorial"
        ],
        "exactly the 7 guide modes"
    );
}

/// Same 7 manifests embedded via `include_str!` (relative to this file:
/// `../../../../templates/<id>/manifest.json`) also validate + parse.
#[test]
fn embedded_manifests_validate() {
    const MANIFESTS: [(&str, &str); 7] = [
        (
            "standard",
            include_str!("../../../../templates/standard/manifest.json"),
        ),
        (
            "checklist",
            include_str!("../../../../templates/checklist/manifest.json"),
        ),
        (
            "sop",
            include_str!("../../../../templates/sop/manifest.json"),
        ),
        (
            "tutorial",
            include_str!("../../../../templates/tutorial/manifest.json"),
        ),
        (
            "runbook",
            include_str!("../../../../templates/runbook/manifest.json"),
        ),
        (
            "presentation",
            include_str!("../../../../templates/presentation/manifest.json"),
        ),
        (
            "reference",
            include_str!("../../../../templates/reference/manifest.json"),
        ),
    ];
    for (id, raw) in MANIFESTS {
        validate_manifest(raw)
            .unwrap_or_else(|e| panic!("embedded manifest {id} failed validation: {e}"));
        let parsed = load_manifest_json(raw)
            .unwrap_or_else(|e| panic!("embedded manifest {id} failed to load: {e}"));
        assert_eq!(parsed.id, id, "embedded id");
        assert_eq!(
            Some(parsed),
            GuideTemplate::make(id),
            "embedded manifest {id} must equal catalogue entry"
        );
    }
}

/// Minimal validation rejects bad documents: invalid JSON, missing required
/// fields, empty strings, unknown enums, non-string quirks.
#[test]
fn manifest_validation_rejects_bad_docs() {
    // Not JSON.
    assert!(validate_manifest("not json").is_err());
    assert!(load_manifest_json("not json").is_err());
    // Not an object.
    assert!(validate_manifest("[1,2]").is_err());
    // Missing required `copy`.
    assert!(validate_manifest(
        r#"{"id":"x","version":"1.0.0","label":"X","theme":"modern-minimal","synthesisStyle":"sop_guide"}"#
    )
    .is_err());
    // Missing required `version`.
    assert!(validate_manifest(
        r#"{"id":"x","label":"X","copy":"c","theme":"modern-minimal","synthesisStyle":"sop_guide"}"#
    )
    .is_err());
    // Empty id.
    assert!(validate_manifest(
        r#"{"id":"","version":"1.0.0","label":"X","copy":"c","theme":"modern-minimal","synthesisStyle":"sop_guide"}"#
    )
    .is_err());
    // Unknown theme.
    assert!(validate_manifest(
        r#"{"id":"x","version":"1.0.0","label":"X","copy":"c","theme":"nope","synthesisStyle":"sop_guide"}"#
    )
    .is_err());
    // Unknown synthesisStyle.
    assert!(validate_manifest(
        r#"{"id":"x","version":"1.0.0","label":"X","copy":"c","theme":"modern-minimal","synthesisStyle":"nope"}"#
    )
    .is_err());
    // Quirks must be a string array when present.
    assert!(validate_manifest(
        r#"{"id":"x","version":"1.0.0","label":"X","copy":"c","theme":"modern-minimal","synthesisStyle":"sop_guide","quirks":[42]}"#
    )
    .is_err());
    // A good doc loads and derives flags from quirks.
    let parsed = load_manifest_json(
        r#"{"id":"checklist","version":"1.0.0","label":"Checklist","copy":"c","theme":"modern-minimal","synthesisStyle":"sop_guide","quirks":["checklist-markers"]}"#,
    )
    .expect("good doc must load");
    assert!(parsed.supports_checklist);
}
