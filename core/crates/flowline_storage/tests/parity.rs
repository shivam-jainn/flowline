//! Parity tests vs the Swift-exported corpus (R/M2-04).

use serde_json::Value;
use flowline_ir::{ExportPaths, MediaMode, RawInputEvent, StepSession};
use flowline_storage::migrate::{migrate_session_json, migration_needed};
use flowline_storage::schema;
use flowline_storage::serialize::{decode_session, MemFs, SessionStore};

// (1) session.sample.json decodes into our types and re-encodes to parity.
#[test]
fn session_golden_round_trip() {
    let golden = parity_harness::load_golden("session.sample.json");
    let session: StepSession = decode_session(&golden).expect("golden must decode");
    assert_eq!(session.steps.len(), 3);
    parity_harness::assert_value_parity(&session, "session.sample.json");
}

// (2) write+read round-trip through MemFs equals the golden bytes (canonical).
#[test]
fn session_memfs_round_trip_matches_golden() {
    let golden = parity_harness::load_golden("session.sample.json");
    let session: StepSession = decode_session(&golden).expect("golden must decode");

    let mut store = SessionStore::new("/base", MemFs::new());
    store.save_session(&session).expect("save");

    let raw = store
        .filesystem()
        .read_raw(&schema::session_json_path("/base", &session.id))
        .expect("session.json written");
    let written = String::from_utf8(raw).expect("utf-8");
    parity_harness::assert_parity(&written, "session.sample.json");

    // Read-back decodes to the same session (manifest is new-in-Rust metadata).
    let loaded = store.load_session(&session.id).expect("load");
    assert_eq!(loaded, session);
    let manifest_raw = store
        .filesystem()
        .read_raw(&schema::manifest_path("/base", &session.id))
        .expect("manifest.json written");
    let manifest: Value = serde_json::from_slice(&manifest_raw).expect("manifest json");
    assert_eq!(manifest["version"], Value::String("1".to_string()));
    assert_eq!(manifest["session_id"], Value::String(session.id.clone()));
}

// (3) events.sample.jsonl lines each decode as IR events and re-append identically.
#[test]
fn events_jsonl_round_trip() {
    let golden = parity_harness::load_golden("events.sample.jsonl");
    let lines: Vec<&str> = golden.lines().filter(|l| !l.trim().is_empty()).collect();
    assert!(!lines.is_empty());

    // Each line decodes as an IR event.
    let events: Vec<RawInputEvent> = lines
        .iter()
        .map(|l| serde_json::from_str(l).expect("event line must decode"))
        .collect();

    // Re-append through the store; raw bytes must match line-for-line (canonical).
    let session: StepSession =
        decode_session(&parity_harness::load_golden("session.sample.json")).unwrap();
    let mut store = SessionStore::new("/base", MemFs::new());
    store.save_session(&session).unwrap();
    for e in &events {
        store.append_event(&session.id, e).unwrap();
    }
    let raw = store
        .filesystem()
        .read_raw(&schema::events_path("/base", &session.id))
        .expect("events.jsonl written");
    let written = String::from_utf8(raw).expect("utf-8");
    let written_lines: Vec<&str> = written.lines().collect();
    assert_eq!(written_lines.len(), lines.len(), "same line count");
    for (got, want) in written_lines.iter().zip(lines.iter()) {
        assert_eq!(
            parity_harness::canonical(got),
            parity_harness::canonical(want),
            "event line parity"
        );
    }

    // Read-back yields the same events.
    assert_eq!(store.read_events(&session.id).unwrap(), events);
}

// (4) old-sparse session JSON migrates to the full golden shape.
#[test]
fn sparse_session_migrates_to_golden_shape() {
    let golden: Value =
        serde_json::from_str(&parity_harness::load_golden("session.sample.json")).unwrap();
    let mut sparse = golden.clone();
    sparse.as_object_mut().unwrap().remove("exports");
    sparse.as_object_mut().unwrap().remove("mediaMode");
    sparse.as_object_mut().unwrap().insert("xLegacy".to_string(), Value::from(7));
    // Drop the optional step key (Swift nil default → stays absent).
    sparse["steps"][1].as_object_mut().unwrap().remove("isRedacted");

    assert!(migration_needed(&sparse));
    assert!(!migration_needed(&golden));

    let migrated = migrate_session_json(sparse).expect("migrate");
    // Unknown fields preserved.
    assert_eq!(migrated["xLegacy"], Value::from(7));

    let session: StepSession =
        serde_json::from_value(migrated.clone()).expect("migrated must decode");
    assert_eq!(session.media_mode, MediaMode::Hybrid);
    assert_eq!(session.exports, ExportPaths::default());

    // Migrated shape == golden shape modulo the intentionally-dropped optional
    // `isRedacted` (absent = Swift nil default) and the extra unknown field.
    let mut expected = golden.clone();
    expected["steps"][1].as_object_mut().unwrap().remove("isRedacted");
    let mut migrated_cmp = migrated.clone();
    migrated_cmp.as_object_mut().unwrap().remove("xLegacy");
    assert_eq!(
        parity_harness::canonical(&migrated_cmp.to_string()),
        parity_harness::canonical(&expected.to_string()),
        "migrated == golden shape (modulo dropped optional)"
    );
}
