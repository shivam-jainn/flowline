//! Session-JSON migration v0 → v1.
//!
//! Swift backward-compat inventory (read off the Swift decoders — migration
//! covers exactly these cases, nothing speculative):
//!
//! * `StepSession` uses synthesized `Codable`: every non-`Optional` field is
//!   **required** by the decoder. Pre-Phase-2 bundles missing `exports`,
//!   `mediaMode`, or `theme` fail to decode, so v0→v1 backfills them with the
//!   Swift `init` defaults (`{}`, `"hybrid"`, `"modern-minimal"`).
//! * `Step.assets` is non-optional (all-optional inside) → backfilled to `{}`.
//! * Already lenient in Swift, left untouched here: step `workingDirectory` /
//!   `hotkeyCombo` / `isRedacted` (all `Optional`, default nil → absent),
//!   `endedAt` / `summary` / `synthesizedMarkdown`, every `MediaAssets` and
//!   `ExportPaths` key.
//! * `Settings.json` leniency (`StepItSettings` section defaults,
//!   `CaptureSettings.recordAppSwitches → false` and friends) lives in the
//!   future Settings port — it is documented, not implemented, here because
//!   the aggregate types belong to another crate.
//! * Unknown fields are always preserved verbatim.

use serde_json::{json, Value};

use crate::serialize::{Error, Result};

fn is_missing_or_null(v: &Value) -> bool {
    v.is_null()
}

fn backfill_key(obj: &mut serde_json::Map<String, Value>, key: &str, default: Value) -> bool {
    match obj.get(key) {
        None => {
            obj.insert(key.to_string(), default);
            true
        }
        Some(v) if is_missing_or_null(v) => {
            obj.insert(key.to_string(), default);
            true
        }
        _ => false,
    }
}

/// Migrate a parsed `session.json` document v0 → v1. Idempotent: running it
/// on current-shape JSON returns an equal document. Unknown fields preserved.
pub fn migrate_session_json(value: Value) -> Result<Value> {
    let mut obj = match value {
        Value::Object(map) => map,
        _ => return Err(Error::Migration("session.json must be a JSON object".to_string())),
    };

    backfill_key(&mut obj, "exports", json!({}));
    backfill_key(&mut obj, "mediaMode", json!("hybrid"));
    backfill_key(&mut obj, "theme", json!("modern-minimal"));

    if let Some(Value::Array(items)) = obj.get_mut("steps") {
        for step in items.iter_mut() {
            if let Value::Object(step_obj) = step {
                backfill_key(step_obj, "assets", json!({}));
            }
        }
    }

    Ok(Value::Object(obj))
}

/// Probe: `true` when `migrate_session_json` would change anything
/// (or the document is not an object at all).
pub fn migration_needed(value: &Value) -> bool {
    let obj = match value {
        Value::Object(map) => map,
        _ => return true,
    };
    for key in ["exports", "mediaMode", "theme"] {
        match obj.get(key) {
            None | Some(Value::Null) => return true,
            _ => {}
        }
    }
    if let Some(Value::Array(items)) = obj.get("steps") {
        for step in items {
            if let Value::Object(step_obj) = step {
                match step_obj.get("assets") {
                    None | Some(Value::Null) => return true,
                    _ => {}
                }
            }
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn fills_missing_top_level_defaults() {
        let v = json!({"id": "s", "steps": []});
        assert!(migration_needed(&v));
        let m = migrate_session_json(v).unwrap();
        assert_eq!(m["exports"], json!({}));
        assert_eq!(m["mediaMode"], json!("hybrid"));
        assert_eq!(m["theme"], json!("modern-minimal"));
    }

    #[test]
    fn treats_null_like_missing() {
        let v = json!({"exports": null, "mediaMode": null, "theme": null, "steps": []});
        assert!(migration_needed(&v));
        let m = migrate_session_json(v).unwrap();
        assert_eq!(m["exports"], json!({}));
        assert_eq!(m["mediaMode"], json!("hybrid"));
    }

    #[test]
    fn backfills_step_assets_only() {
        let v = json!({
            "exports": {}, "mediaMode": "hybrid", "theme": "modern-minimal",
            "steps": [{"id": "a"}, {"id": "b", "assets": {"gif": "media/x.gif"}}],
        });
        assert!(migration_needed(&v));
        let m = migrate_session_json(v).unwrap();
        assert_eq!(m["steps"][0]["assets"], json!({}));
        assert_eq!(m["steps"][1]["assets"], json!({"gif": "media/x.gif"}));
        // Optional step keys stay absent (Swift nil default), never invented.
        assert!(m["steps"][0].get("isRedacted").is_none());
    }

    #[test]
    fn preserves_unknown_fields_and_is_idempotent() {
        let v = json!({
            "exports": {}, "mediaMode": "static", "theme": "developer-dark",
            "steps": [], "xLegacy": 1,
        });
        assert!(!migration_needed(&v));
        let m = migrate_session_json(v.clone()).unwrap();
        assert_eq!(m, v);
        assert_eq!(m["xLegacy"], json!(1));
    }

    #[test]
    fn rejects_non_objects() {
        assert!(migration_needed(&json!([1, 2])));
        assert!(migrate_session_json(json!([1, 2])).is_err());
    }
}
