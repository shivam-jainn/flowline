//! Parity tests: template renders == `shared/goldens/templates.sample.json`.

use flowline_ir::session::Step;
use flowline_templates::{render_guide, render_step, GuideTemplate};

fn load_fixture() -> serde_json::Value {
    let raw = parity_harness::load_golden("templates.sample.json");
    serde_json::from_str(&raw).expect("templates.sample.json must be valid JSON")
}

fn load_steps(fixture: &serde_json::Value) -> Vec<Step> {
    serde_json::from_value(fixture["steps"].clone()).expect("golden steps must deserialize")
}

/// The built-in catalogue matches the `templates/*/manifest.json` data
/// files (id/label/copy/theme/synthesisStyle/quirks).
#[test]
fn catalogue_matches_manifests() {
    let root = parity_harness::repo_root().join("templates");
    let mut seen = Vec::new();
    for template in GuideTemplate::all() {
        let path = root.join(&template.id).join("manifest.json");
        let raw = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("missing manifest {}: {e}", path.display()));
        let manifest: serde_json::Value =
            serde_json::from_str(&raw).expect("manifest must be valid JSON");
        assert_eq!(manifest["id"].as_str(), Some(template.id.as_str()), "id");
        assert_eq!(
            manifest["label"].as_str(),
            Some(template.label.as_str()),
            "label"
        );
        assert_eq!(
            manifest["copy"].as_str(),
            Some(template.copy.as_str()),
            "copy"
        );
        assert_eq!(
            manifest["theme"].as_str(),
            Some(template.theme.as_str()),
            "theme"
        );
        assert_eq!(
            manifest["synthesisStyle"].as_str(),
            Some(template.synthesis_style.as_str()),
            "synthesisStyle"
        );
        let quirks: Vec<String> = serde_json::from_value(manifest["quirks"].clone())
            .expect("quirks must be a string array");
        assert_eq!(quirks, template.quirks, "quirks");
        seen.push(template.id.clone());
    }
    seen.sort();
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

/// `render_step` for every mode matches the golden renders byte-for-byte.
#[test]
fn step_renders_match_golden() {
    let fixture = load_fixture();
    let steps = load_steps(&fixture);
    for template in GuideTemplate::all() {
        let expected = fixture["renders"][template.id.as_str()]
            .as_array()
            .unwrap_or_else(|| panic!("no golden renders for {}", template.id));
        assert_eq!(expected.len(), steps.len(), "render count");
        for (i, step) in steps.iter().enumerate() {
            assert_eq!(
                render_step(step, i as i64 + 1, &template),
                expected[i].as_str().expect("render must be a string"),
                "mode {} step {}",
                template.id,
                i + 1
            );
        }
    }
}

/// `render_guide` (checklist) matches the golden guide text byte-for-byte.
#[test]
fn guide_render_matches_golden() {
    let fixture = load_fixture();
    let steps = load_steps(&fixture);
    let guide = &fixture["guide"];
    let template_id = guide["template"].as_str().expect("guide.template");
    let template =
        GuideTemplate::make(template_id).unwrap_or_else(|| panic!("unknown {template_id}"));
    let mut session = flowline_ir::StepSession::new(
        "sess_00000001".to_string(),
        "2026-03-01T10:00:00Z".to_string(),
    );
    session.title = guide["title"].as_str().expect("guide.title").to_string();
    session.steps = steps;
    assert_eq!(
        render_guide(&session, &template),
        guide["text"].as_str().expect("guide.text"),
        "guide text diverged from shared/goldens/templates.sample.json"
    );
}

/// Unknown template ids fall back to standard rendering.
#[test]
fn unknown_template_falls_back_to_standard() {
    let fixture = load_fixture();
    let steps = load_steps(&fixture);
    let unknown = GuideTemplate::new("nope", "Nope", "Missing.", "modern-minimal", "sop_guide");
    let standard = GuideTemplate::make("standard").expect("standard must exist in the catalogue");
    for (i, step) in steps.iter().enumerate() {
        assert_eq!(
            render_step(step, i as i64 + 1, &unknown),
            render_step(step, i as i64 + 1, &standard),
            "fallback step {}",
            i + 1
        );
    }
}
