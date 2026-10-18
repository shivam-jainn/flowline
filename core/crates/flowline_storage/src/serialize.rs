//! Serialization + persistence behind an injected [`Filesystem`].
//!
//! Mirrors `SessionStore` (sessions, media) with two Rust-designed additions:
//! the append-only `events.jsonl` log and the bundle [`Manifest`](crate::schema::Manifest).
//! Core functions never touch I/O directly — everything goes through the trait.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::PathBuf;

use serde::Serialize;
use thiserror::Error;

use flowline_ir::{RawInputEvent, StepSession};
use crate::schema::{
    self, Manifest,
};

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[derive(Debug, Error)]
pub enum Error {
    #[error("storage I/O: {0}")]
    Io(String),
    #[error("encode failed: {0}")]
    Encode(String),
    #[error("decode failed: {0}")]
    Decode(String),
    #[error("migration failed: {0}")]
    Migration(String),
}

pub type Result<T> = std::result::Result<T, Error>;

// ---------------------------------------------------------------------------
// Filesystem trait (mirrors FilesystemGateway; paths are strings)
// ---------------------------------------------------------------------------

/// Minimal file operations the store needs. Paths are `/`-joined strings
/// built by [`schema`] helpers; `list` returns immediate children (full
/// paths), mirroring `FileManager.contentsOfDirectory`.
pub trait Filesystem {
    fn exists(&self, path: &str) -> bool;
    fn create_dir(&mut self, path: &str) -> Result<()>;
    fn list(&self, path: &str) -> Result<Vec<String>>;
    fn remove(&mut self, path: &str) -> Result<()>;
    fn read(&self, path: &str) -> Result<Vec<u8>>;
    fn write(&mut self, path: &str, data: &[u8]) -> Result<()>;
}

/// In-memory fake for tests. Keyed by path string.
#[derive(Debug, Default)]
pub struct MemFs {
    files: HashMap<String, Vec<u8>>,
    dirs: HashSet<String>,
}

impl MemFs {
    pub fn new() -> Self {
        Self::default()
    }

    /// Test helper: raw bytes previously written to `path`.
    pub fn read_raw(&self, path: &str) -> Option<Vec<u8>> {
        self.files.get(path).cloned()
    }

    fn mark_ancestors(&mut self, path: &str) {
        let mut dir = parent(path).to_string();
        loop {
            self.dirs.insert(dir.clone());
            if dir == "/" || dir.is_empty() {
                break;
            }
            dir = parent(&dir).to_string();
        }
    }
}

fn parent(path: &str) -> &str {
    match path.rfind('/') {
        Some(0) => "/",
        Some(i) => &path[..i],
        None => "",
    }
}

fn child_name(dir: &str, path: &str) -> Option<String> {
    let rest = path.strip_prefix(dir)?.strip_prefix('/')?;
    if rest.is_empty() {
        return None;
    }
    let first = rest.split('/').next().unwrap_or(rest);
    Some(format!("{dir}/{first}"))
}

impl Filesystem for MemFs {
    fn exists(&self, path: &str) -> bool {
        self.files.contains_key(path) || self.dirs.contains(path)
    }

    fn create_dir(&mut self, path: &str) -> Result<()> {
        self.dirs.insert(path.to_string());
        Ok(())
    }

    fn list(&self, path: &str) -> Result<Vec<String>> {
        let mut seen: HashSet<String> = HashSet::new();
        for p in self.files.keys().chain(self.dirs.iter()) {
            if let Some(child) = child_name(path, p) {
                seen.insert(child);
            }
        }
        Ok(seen.into_iter().collect())
    }

    fn remove(&mut self, path: &str) -> Result<()> {
        let prefix = format!("{path}/");
        self.files
            .retain(|k, _| k != path && !k.starts_with(&prefix));
        self.dirs.retain(|k| k != path && !k.starts_with(&prefix));
        Ok(())
    }

    fn read(&self, path: &str) -> Result<Vec<u8>> {
        self.files
            .get(path)
            .cloned()
            .ok_or_else(|| Error::Io(format!("no such file: {path}")))
    }

    fn write(&mut self, path: &str, data: &[u8]) -> Result<()> {
        self.mark_ancestors(path);
        self.files.insert(path.to_string(), data.to_vec());
        Ok(())
    }
}

/// Live std::fs-backed filesystem rooted at `root`.
#[derive(Debug)]
pub struct StdFs {
    root: PathBuf,
}

impl StdFs {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    fn full(&self, path: &str) -> PathBuf {
        self.root.join(path.trim_start_matches('/'))
    }
}

impl Filesystem for StdFs {
    fn exists(&self, path: &str) -> bool {
        self.full(path).exists()
    }

    fn create_dir(&mut self, path: &str) -> Result<()> {
        std::fs::create_dir_all(self.full(path))
            .map_err(|e| Error::Io(format!("create_dir {path}: {e}")))
    }

    fn list(&self, path: &str) -> Result<Vec<String>> {
        let dir = std::fs::read_dir(self.full(path))
            .map_err(|e| Error::Io(format!("list {path}: {e}")))?;
        let mut out = Vec::new();
        for entry in dir {
            let entry = entry.map_err(|e| Error::Io(format!("list {path}: {e}")))?;
            let name = entry.file_name().to_string_lossy().into_owned();
            out.push(format!("{path}/{name}"));
        }
        Ok(out)
    }

    fn remove(&mut self, path: &str) -> Result<()> {
        let full = self.full(path);
        if full.is_dir() {
            std::fs::remove_dir_all(&full)
        } else {
            std::fs::remove_file(&full)
        }
        .map_err(|e| Error::Io(format!("remove {path}: {e}")))
    }

    fn read(&self, path: &str) -> Result<Vec<u8>> {
        std::fs::read(self.full(path)).map_err(|e| Error::Io(format!("read {path}: {e}")))
    }

    fn write(&mut self, path: &str, data: &[u8]) -> Result<()> {
        let full = self.full(path);
        if let Some(parent) = full.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| Error::Io(format!("write parent {path}: {e}")))?;
        }
        std::fs::write(&full, data).map_err(|e| Error::Io(format!("write {path}: {e}")))
    }
}

// ---------------------------------------------------------------------------
// Canonical JSON (sorted keys, compact) — one event per jsonl line
// ---------------------------------------------------------------------------

fn canonical_value(v: &serde_json::Value) -> serde_json::Value {
    match v {
        serde_json::Value::Object(map) => {
            let sorted: BTreeMap<&String, &serde_json::Value> = map.iter().collect();
            serde_json::Value::Object(
                sorted
                    .into_iter()
                    .map(|(k, v)| (k.clone(), canonical_value(v)))
                    .collect(),
            )
        }
        serde_json::Value::Array(items) => {
            serde_json::Value::Array(items.iter().map(canonical_value).collect())
        }
        other => other.clone(),
    }
}

/// Serialize to canonical JSON (object keys sorted recursively, compact).
pub fn to_canonical<T: Serialize>(value: &T) -> Result<String> {
    let raw = serde_json::to_value(value).map_err(|e| Error::Encode(e.to_string()))?;
    serde_json::to_string(&canonical_value(&raw)).map_err(|e| Error::Encode(e.to_string()))
}

/// `session.json` bytes: pretty-printed with sorted keys, mirroring Swift's
/// `JSONEncoder[.prettyPrinted, .sortedKeys]`.
pub fn encode_session_pretty(session: &StepSession) -> Result<String> {
    let raw = serde_json::to_value(session).map_err(|e| Error::Encode(e.to_string()))?;
    serde_json::to_string_pretty(&canonical_value(&raw)).map_err(|e| Error::Encode(e.to_string()))
}

/// Decode `session.json` bytes (unknown fields ignored, like Swift).
pub fn decode_session(json: &str) -> Result<StepSession> {
    serde_json::from_str(json).map_err(|e| Error::Decode(e.to_string()))
}

/// Decode one `events.jsonl` line.
pub fn decode_event_line(line: &str) -> Result<RawInputEvent> {
    serde_json::from_str(line).map_err(|e| Error::Decode(e.to_string()))
}

// ---------------------------------------------------------------------------
// SessionStore
// ---------------------------------------------------------------------------

/// Persistence gateway mirroring Swift's `SessionStore`, parameterized
/// over the filesystem so tests inject [`MemFs`].
#[derive(Debug)]
pub struct SessionStore<FS> {
    base: String,
    fs: FS,
}

impl<FS: Filesystem> SessionStore<FS> {
    pub fn new(base: impl Into<String>, fs: FS) -> Self {
        Self {
            base: base.into(),
            fs,
        }
    }

    pub fn filesystem(&self) -> &FS {
        &self.fs
    }

    pub fn save_session(&mut self, session: &StepSession) -> Result<()> {
        let id = &session.id;
        self.fs.create_dir(&schema::session_dir(&self.base, id))?;
        self.fs.create_dir(&schema::media_dir(&self.base, id))?;
        self.fs.create_dir(&schema::exports_dir(&self.base, id))?;
        let body = encode_session_pretty(session)?;
        self.fs
            .write(&schema::session_json_path(&self.base, id), body.as_bytes())?;
        let manifest = Manifest::new(id.clone(), session.started_at.clone());
        let manifest_body =
            serde_json::to_string_pretty(&manifest).map_err(|e| Error::Encode(e.to_string()))?;
        self.fs
            .write(&schema::manifest_path(&self.base, id), manifest_body.as_bytes())?;
        Ok(())
    }

    pub fn load_session(&self, id: &str) -> Result<StepSession> {
        let bytes = self.fs.read(&schema::session_json_path(&self.base, id))?;
        let text = String::from_utf8(bytes).map_err(|e| Error::Decode(e.to_string()))?;
        decode_session(&text)
    }

    /// All decodable sessions, newest `startedAt` first (opaque-string
    /// comparison is chronological for iso8601 `Z` timestamps).
    /// Unreadable bundles are skipped, like Swift's `listSessions`.
    pub fn list_sessions(&self) -> Vec<StepSession> {
        let items = self
            .fs
            .list(&schema::sessions_dir(&self.base))
            .unwrap_or_default();
        let mut sessions: Vec<StepSession> = items
            .iter()
            .filter_map(|dir| {
                let id = dir.rsplit('/').next()?;
                self.load_session(id).ok()
            })
            .collect();
        sessions.sort_by(|a, b| b.started_at.cmp(&a.started_at));
        sessions
    }

    pub fn delete_session(&mut self, id: &str) -> Result<()> {
        let dir = schema::session_dir(&self.base, id);
        if self.fs.exists(&dir) {
            self.fs.remove(&dir)?;
        }
        Ok(())
    }

    /// Store media bytes; returns the `media/<filename>` session-relative
    /// reference (mirrors `SessionStore.saveMedia`).
    pub fn save_media(
        &mut self,
        data: &[u8],
        session_id: &str,
        filename: &str,
    ) -> Result<String> {
        self.fs
            .create_dir(&schema::media_dir(&self.base, session_id))?;
        self.fs.write(
            &format!("{}/{}", schema::media_dir(&self.base, session_id), filename),
            data,
        )?;
        Ok(schema::media_relative_path(filename))
    }

    /// Append one canonical event line to `events.jsonl`.
    pub fn append_event(&mut self, session_id: &str, event: &RawInputEvent) -> Result<()> {
        let path = schema::events_path(&self.base, session_id);
        let mut body = self.fs.read(&path).unwrap_or_default();
        let mut line = to_canonical(event)?;
        line.push('\n');
        body.extend_from_slice(line.as_bytes());
        self.fs.write(&path, &body)?;
        Ok(())
    }

    /// Read back every non-blank line of `events.jsonl`.
    pub fn read_events(&self, session_id: &str) -> Result<Vec<RawInputEvent>> {
        let bytes = self.fs.read(&schema::events_path(&self.base, session_id))?;
        let text = String::from_utf8(bytes).map_err(|e| Error::Decode(e.to_string()))?;
        text.lines()
            .filter(|l| !l.trim().is_empty())
            .map(decode_event_line)
            .collect()
    }
}
