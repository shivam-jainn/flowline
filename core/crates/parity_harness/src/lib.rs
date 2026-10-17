//! Parity harness (R/M2-00).
//!
//! One harness, all crates use it: loads the Swift-exported fixture corpus
//! from `shared/goldens/` and asserts byte-identical output at the *canonical*
//! JSON level (object keys sorted recursively, compact separators). Swift
//! goldens are dumped with `JSONEncoder(sortedKeys:)`; Rust outputs pass
//! through [`canonical`] before comparison, so struct field order never
//! matters — only the data.

use std::path::{Path, PathBuf};

/// Workspace `core/` dir, resolved from this crate's manifest location.
pub fn rust_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("crates/<name>/..")
        .parent()
        .expect("core/")
        .to_path_buf()
}

/// Repo root, resolved from the `core/` workspace dir.
pub fn repo_root() -> PathBuf {
    rust_dir()
        .parent()
        .expect("repo root above core/")
        .to_path_buf()
}

/// Read a golden file from `shared/goldens/<name>`.
pub fn load_golden(name: &str) -> String {
    let path = repo_root().join("shared").join("goldens").join(name);
    std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("missing golden {}: {e}", path.display()))
}

/// Canonical JSON: parse, then re-emit with object keys sorted recursively
/// and compact separators. Byte comparison happens on this form.
pub fn canonical(json: &str) -> String {
    let value: serde_json::Value =
        serde_json::from_str(json).expect("golden/candidate must be valid JSON");
    let mut out = Vec::new();
    write_canonical(&value, &mut out);
    String::from_utf8(out).expect("canonical JSON is UTF-8")
}

fn write_canonical(v: &serde_json::Value, out: &mut Vec<u8>) {
    match v {
        serde_json::Value::Null => out.extend_from_slice(b"null"),
        serde_json::Value::Bool(b) => out.extend_from_slice(if *b { b"true" } else { b"false" }),
        serde_json::Value::Number(n) => out.extend_from_slice(n.to_string().as_bytes()),
        serde_json::Value::String(s) => {
            out.extend_from_slice(serde_json::to_string(s).expect("escape").as_bytes())
        }
        serde_json::Value::Array(items) => {
            out.push(b'[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                write_canonical(item, out);
            }
            out.push(b']');
        }
        serde_json::Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            out.push(b'{');
            for (i, k) in keys.iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                out.extend_from_slice(serde_json::to_string(k).expect("escape").as_bytes());
                out.push(b':');
                write_canonical(&map[*k], out);
            }
            out.push(b'}');
        }
    }
}

/// Serialize a value to canonical JSON (via `serde_json::Value` round-trip).
pub fn to_canonical<T: serde::Serialize>(value: &T) -> String {
    let raw = serde_json::to_string(value).expect("serializable");
    canonical(&raw)
}

/// Assert a Rust-produced JSON string is byte-identical (canonical) to golden.
#[track_caller]
pub fn assert_parity(candidate_json: &str, golden_name: &str) {
    let golden = load_golden(golden_name);
    assert_eq!(
        canonical(candidate_json),
        canonical(&golden),
        "parity mismatch vs golden {golden_name}"
    );
}

/// Assert a serializable Rust value matches golden.
#[track_caller]
pub fn assert_value_parity<T: serde::Serialize>(value: &T, golden_name: &str) {
    assert_parity(&serde_json::to_string(value).expect("serializable"), golden_name);
}
