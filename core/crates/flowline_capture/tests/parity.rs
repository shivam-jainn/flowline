//! Parity tests for the portable capture SPI: registry round-trip (with the
//! manifest version gate), `CaptureCapabilities` JSON keys, and
//! `PluginManifest::validate_host`.

use flowline_capture::{
    CaptureCapabilities, CaptureDriverError, ClipBufferConfig, DriverRegistry, InputEventSource,
    DEFAULT_HOST_VERSION,
};
use flowline_capture::driver::{ElementInspector, VisualCapture};
use flowline_ir::{ClipAsset, FrameSnapshot, PluginManifest, Point2D, RawElementContext};

// MARK: - Mock driver

#[derive(Debug, Default)]
struct MockDriver {
    started: bool,
    snapshots_taken: i64,
}

impl InputEventSource for MockDriver {
    fn platform_identifier(&self) -> &str {
        "mock"
    }

    fn capabilities(&self) -> CaptureCapabilities {
        CaptureCapabilities::mock_full()
    }

    fn start(&mut self) -> Result<(), CaptureDriverError> {
        self.started = true;
        Ok(())
    }

    fn pause(&mut self) {}

    fn resume(&mut self) {}

    fn stop(&mut self) {
        self.started = false;
    }
}

impl ElementInspector for MockDriver {
    fn inspect_element(&mut self, _x: f64, _y: f64) -> Option<RawElementContext> {
        None
    }

    fn inspect_focused(&mut self) -> Option<RawElementContext> {
        None
    }
}

impl VisualCapture for MockDriver {
    fn start_clip_buffering(&mut self, _config: ClipBufferConfig) {}

    fn stop_clip_buffering(&mut self) {}

    fn capture_snapshot(
        &mut self,
        _highlight_at: Option<Point2D>,
        _step_index: i64,
    ) -> Option<FrameSnapshot> {
        self.snapshots_taken += 1;
        None
    }

    fn capture_micro_clip(
        &mut self,
        _around: Point2D,
        _post_duration_secs: f64,
    ) -> Option<ClipAsset> {
        None
    }
}

fn mock_manifest() -> PluginManifest {
    PluginManifest::new(
        "mock".to_string(),
        "1.0.0".to_string(),
        vec!["snapshots".to_string()],
        DEFAULT_HOST_VERSION.to_string(),
    )
}

// MARK: - Registry round-trip

#[test]
fn registry_round_trip() {
    let registry = DriverRegistry::new();
    registry.register(mock_manifest(), || {
        Box::new(MockDriver::default())
    });

    assert_eq!(registry.registered_ids(), vec!["mock".to_string()]);
    assert_eq!(registry.manifest("mock"), Some(mock_manifest()));
    assert_eq!(registry.manifest("unknown"), None);

    let mut driver = registry.resolve("mock", DEFAULT_HOST_VERSION).expect("resolve mock");
    assert_eq!(driver.platform_identifier(), "mock");
    assert_eq!(driver.capabilities(), CaptureCapabilities::mock_full());
    driver.start().expect("mock start always succeeds");

    assert!(registry.resolve("unknown", DEFAULT_HOST_VERSION).is_none());
}

#[test]
fn registry_version_gate() {
    let registry = DriverRegistry::new();
    registry.register(
        PluginManifest::new(
            "future".to_string(),
            "9.9.9".to_string(),
            Vec::new(),
            "r-m99".to_string(),
        ),
        || Box::new(MockDriver::default()),
    );

    // Host older than the manifest minimum: gated out.
    assert!(registry.resolve("future", DEFAULT_HOST_VERSION).is_none());
    // Host satisfying the minimum: resolves.
    assert!(registry.resolve("future", "r-m99").is_some());
    // `resolve_default` uses the r-m1 host version.
    assert!(registry.resolve_default("future").is_none());
}

// MARK: - Capabilities JSON

#[test]
fn capabilities_json_keys_match_swift() {
    let value = serde_json::to_value(CaptureCapabilities::mac_native()).unwrap();
    assert_eq!(
        value,
        serde_json::json!({
            "snapshots": true,
            "microClips": true,
            "accessibilityTree": true,
            "secureFieldDetection": true,
        })
    );

    let back: CaptureCapabilities = serde_json::from_value(value).unwrap();
    assert_eq!(back, CaptureCapabilities::mac_native());
    assert_eq!(back, CaptureCapabilities::mock_full());
    assert_eq!(
        CaptureCapabilities::none(),
        CaptureCapabilities {
            snapshots: false,
            micro_clips: false,
            accessibility_tree: false,
            secure_field_detection: false,
        }
    );
}

// MARK: - Manifest host validation

#[test]
fn manifest_validate_host() {
    let manifest = mock_manifest();
    assert!(manifest.validate_host("r-m1"));
    assert!(manifest.validate_host("r-m2"));
    assert!(!manifest.validate_host("r-m0"));
    assert!(manifest.supports("snapshots"));
    assert!(!manifest.supports("microClips"));
}
