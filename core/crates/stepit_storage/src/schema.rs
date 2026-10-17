//! Bundle layout + path helpers (mirrors `SessionStore` directory functions).
//!
//! On-disk layout (Swift-owned rows marked `*`, Rust-designed rows marked `+`):
//!
//! ```text
//! <base>/                          (SessionStore.baseDirectory)
//!   Settings.json              *   (owned by SettingsFileStore; helper only)
//!   Sessions/
//!     <id>/
//!       session.json           *   (pretty+sortedKeys, iso8601)
//!       manifest.json          +   (bundle Manifest, version "1")
//!       events.jsonl           +   (append-only raw input events)
//!       media/                 *
//!       exports/               *
//!         web/                 *
//! ```
//!
//! `session.json` stays byte-identical to Swift. `manifest.json` and
//! `events.jsonl` are new in Rust (Swift has no such machinery): the manifest
//! pins the bundle version + identity, the jsonl log records the raw event
//! stream one canonical object per line.

pub use stepit_ir::ExportPaths;

/// Bundle manifest version written by this crate.
pub const BUNDLE_VERSION: &str = "1";

pub const SESSIONS_DIR_NAME: &str = "Sessions";
pub const SESSION_FILENAME: &str = "session.json";
pub const MANIFEST_FILENAME: &str = "manifest.json";
pub const EVENTS_FILENAME: &str = "events.jsonl";
pub const MEDIA_DIR_NAME: &str = "media";
pub const EXPORTS_DIR_NAME: &str = "exports";
pub const WEB_EXPORT_DIR_NAME: &str = "web";
pub const SETTINGS_FILENAME: &str = "Settings.json";

/// Bundle manifest (new in Rust): pins bundle version + session identity.
///
/// Lives at `Sessions/<id>/manifest.json`. `version` is `"1"`;
/// `session_id` duplicates the directory name so a moved bundle stays
/// identifiable; `created_at` is the session's `startedAt` (opaque string).
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Manifest {
    pub version: String,
    pub session_id: String,
    pub created_at: String,
}

impl Manifest {
    pub fn new(session_id: impl Into<String>, created_at: impl Into<String>) -> Self {
        Self {
            version: BUNDLE_VERSION.to_string(),
            session_id: session_id.into(),
            created_at: created_at.into(),
        }
    }
}

/// `<base>/Sessions`
pub fn sessions_dir(base: &str) -> String {
    format!("{base}/{SESSIONS_DIR_NAME}")
}

/// `<base>/Settings.json`
pub fn settings_path(base: &str) -> String {
    format!("{base}/{SETTINGS_FILENAME}")
}

/// `<base>/Sessions/<id>`
pub fn session_dir(base: &str, id: &str) -> String {
    format!("{}/{id}", sessions_dir(base))
}

/// `<base>/Sessions/<id>/session.json`
pub fn session_json_path(base: &str, id: &str) -> String {
    format!("{}/{SESSION_FILENAME}", session_dir(base, id))
}

/// `<base>/Sessions/<id>/manifest.json`
pub fn manifest_path(base: &str, id: &str) -> String {
    format!("{}/{MANIFEST_FILENAME}", session_dir(base, id))
}

/// `<base>/Sessions/<id>/events.jsonl`
pub fn events_path(base: &str, id: &str) -> String {
    format!("{}/{EVENTS_FILENAME}", session_dir(base, id))
}

/// `<base>/Sessions/<id>/media`
pub fn media_dir(base: &str, id: &str) -> String {
    format!("{}/{MEDIA_DIR_NAME}", session_dir(base, id))
}

/// `<base>/Sessions/<id>/exports`
pub fn exports_dir(base: &str, id: &str) -> String {
    format!("{}/{EXPORTS_DIR_NAME}", session_dir(base, id))
}

/// `<base>/Sessions/<id>/exports/web`
pub fn web_export_dir(base: &str, id: &str) -> String {
    format!("{}/{WEB_EXPORT_DIR_NAME}", exports_dir(base, id))
}

/// Media reference stored in session JSON: `media/<filename>`
/// (mirrors `SessionStore.saveMedia` returning `"media/\(filename)"`).
pub fn media_relative_path(filename: &str) -> String {
    format!("{MEDIA_DIR_NAME}/{filename}")
}

/// Resolve a `media/<filename>` reference to its in-bundle path.
/// Returns `None` when the reference is not under `media/`.
pub fn resolve_media_path(base: &str, session_id: &str, relative: &str) -> Option<String> {
    let filename = media_filename(relative)?;
    Some(format!("{}/{filename}", media_dir(base, session_id)))
}

/// Split `media/<filename>` into the filename. `None` for anything else.
pub fn media_filename(relative: &str) -> Option<&str> {
    relative
        .strip_prefix(&format!("{MEDIA_DIR_NAME}/"))
        .filter(|f| !f.is_empty() && !f.contains('/'))
}
