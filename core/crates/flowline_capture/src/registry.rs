//! Capture-driver registry (sync port of Swift
//! `Sources/FlowlineCaptureAPI/DriverRegistry.swift`).
//!
//! Drivers register a factory + [`PluginManifest`](flowline_ir::PluginManifest)
//! at the composition root; call sites resolve by id and never name
//! concretes. `resolve` enforces the manifest's minimum-host version gate
//! (`PluginManifest::validate_host`), mirroring Swift.

use std::collections::HashMap;
use std::sync::Mutex;

use flowline_ir::PluginManifest;

use crate::driver::CaptureDriver;

/// Default host version used when callers do not pass one (mirrors Swift's
/// `resolve(id:hostVersion:)` default of `"r-m1"`).
pub const DEFAULT_HOST_VERSION: &str = "r-m1";

struct Entry {
    manifest: PluginManifest,
    factory: Box<dyn Fn() -> Box<dyn CaptureDriver> + Send + Sync>,
}

/// Type-erased driver registry. `Mutex`-guarded like Swift's `NSLock`, so a
/// single shared registry can be used from any thread.
#[derive(Default)]
pub struct DriverRegistry {
    entries: Mutex<HashMap<String, Entry>>,
}

impl DriverRegistry {
    /// Empty registry.
    pub fn new() -> Self {
        Self {
            entries: Mutex::new(HashMap::new()),
        }
    }

    /// Register a driver factory + manifest (overwrites any existing `id`).
    pub fn register<F>(&self, manifest: PluginManifest, factory: F)
    where
        F: Fn() -> Box<dyn CaptureDriver> + Send + Sync + 'static,
    {
        let mut entries = self.entries.lock().expect("registry lock");
        entries.insert(
            manifest.id.clone(),
            Entry {
                manifest,
                factory: Box::new(factory),
            },
        );
    }

    /// Build the driver for `id` when registered *and* its manifest's
    /// minimum-host gate passes for `host_version`. Returns `None` for
    /// unknown ids or failed version gates (mirrors Swift `resolve`).
    pub fn resolve(&self, id: &str, host_version: &str) -> Option<Box<dyn CaptureDriver>> {
        let entries = self.entries.lock().expect("registry lock");
        let entry = entries.get(id)?;
        if !entry.manifest.validate_host(host_version) {
            return None;
        }
        Some((entry.factory)())
    }

    /// [`DriverRegistry::resolve`] with [`DEFAULT_HOST_VERSION`].
    pub fn resolve_default(&self, id: &str) -> Option<Box<dyn CaptureDriver>> {
        self.resolve(id, DEFAULT_HOST_VERSION)
    }

    /// Clone of the registered manifest, if any.
    pub fn manifest(&self, id: &str) -> Option<PluginManifest> {
        let entries = self.entries.lock().expect("registry lock");
        entries.get(id).map(|e| e.manifest.clone())
    }

    /// Sorted registered ids.
    pub fn registered_ids(&self) -> Vec<String> {
        let entries = self.entries.lock().expect("registry lock");
        let mut ids: Vec<String> = entries.keys().cloned().collect();
        ids.sort();
        ids
    }
}
