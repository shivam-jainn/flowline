//! Pointer disambiguation: click vs. jitter vs. drag (`MouseDragDetector`
//! port, `Sources/FlowlineMacCapture/MouseDragDetector.swift`).
//!
//! Pure geometry over a press → release pair — no clock, no AppKit — so the
//! distance / duration / velocity bands are unit-testable with synthetic
//! coordinates and timestamps.
//!
//! Bands (spec):
//! - `< click_radius` (4 px mouse, 6 px trackpad): `Click`, moves ignored.
//! - `4–10 px`: velocity-gated — `> 50 px/s` is `Drag`, else `Jitter`.
//! - `> 10 px`, or held `> 300 ms` past the click radius: `Drag`.
//!
//! Callers treat [`PressRelease::Jitter`] like [`PressRelease::Click`]
//! (no `.mouseDrag` step); the distinct variant exists so tests can pin the
//! band boundary. Drag emission always forces a source-vs-target element
//! boundary check at the engine layer (`produce_drag` inspects both ends).

/// Tuning for [`classify_with`]. Defaults encode the spec bands.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DragConfig {
    /// Euclidean distance below which any press → release is a click.
    pub click_radius_px: f64,
    /// Same, for trackpads (larger deadzone, 5–6 px).
    pub trackpad_click_radius_px: f64,
    /// Distance above which the gesture is always a drag.
    pub drag_radius_px: f64,
    /// 4–10 px band gate: above this press → release velocity is a drag.
    pub velocity_threshold_px_per_sec: f64,
    /// Held past the click radius longer than this is a drag even when slow.
    pub long_hold_secs: f64,
}

impl Default for DragConfig {
    fn default() -> Self {
        Self {
            click_radius_px: 4.0,
            trackpad_click_radius_px: 6.0,
            drag_radius_px: 10.0,
            velocity_threshold_px_per_sec: 50.0,
            long_hold_secs: 0.30,
        }
    }
}

/// Classification of a completed press → release gesture.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PressRelease {
    /// Ordinary click — emit `.mouseClick`.
    Click,
    /// Small, slow movement — hand tremor, not intent. Emit `.mouseClick`
    /// (never `.mouseDrag`).
    Jitter,
    /// Deliberate drag — emit `.mouseDrag`.
    Drag,
}

impl PressRelease {
    /// `true` when the gesture must become a `.mouseDrag` step.
    pub fn is_drag(self) -> bool {
        self == Self::Drag
    }
}

/// Mean press → release velocity in px/s. Zero/negative durations yield
/// `+∞` for non-zero distances (an instant teleport is fast, not still) and
/// `0.0` for a true no-move.
pub fn pointer_velocity(distance_px: f64, duration_secs: f64) -> f64 {
    if distance_px <= 0.0 {
        return 0.0;
    }
    if duration_secs <= 0.0 {
        return f64::INFINITY;
    }
    distance_px / duration_secs
}

/// Classify with default tuning.
pub fn classify(distance_px: f64, duration_secs: f64, is_trackpad: bool) -> PressRelease {
    classify_with(distance_px, duration_secs, is_trackpad, &DragConfig::default())
}

/// Classify a press → release pair.
///
/// `distance_px` is the Euclidean press → release distance,
/// `duration_secs` the press → release hold time.
pub fn classify_with(
    distance_px: f64,
    duration_secs: f64,
    is_trackpad: bool,
    config: &DragConfig,
) -> PressRelease {
    let distance_px = if distance_px.is_finite() {
        distance_px.max(0.0)
    } else {
        return PressRelease::Click;
    };
    let click_radius = if is_trackpad {
        config.trackpad_click_radius_px
    } else {
        config.click_radius_px
    };
    // Inside the deadzone movement is ignored: plain click.
    if distance_px < click_radius {
        return PressRelease::Click;
    }
    // Unambiguous displacement: always a drag.
    if distance_px > config.drag_radius_px {
        return PressRelease::Drag;
    }
    // Held past the click radius: deliberate even when slow. Strict `>`
    // keeps a release exactly on the boundary in the velocity gate.
    if duration_secs > config.long_hold_secs {
        return PressRelease::Drag;
    }
    // 4–10 px band: velocity-gated.
    if pointer_velocity(distance_px, duration_secs) > config.velocity_threshold_px_per_sec {
        PressRelease::Drag
    } else {
        PressRelease::Jitter
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sub_click_radius_is_click() {
        assert_eq!(classify(0.0, 1.2, false), PressRelease::Click);
        assert_eq!(classify(3.9, 0.05, false), PressRelease::Click);
        // Long stationary hold stays a click (long-press ≠ drag).
        assert_eq!(classify(0.0, 5.0, false), PressRelease::Click);
    }

    #[test]
    fn mid_band_slow_is_jitter() {
        // 8.94 pt / 300 ms ≈ 29.8 px/s — hand tremor, not intent.
        let d = (8.0_f64 * 8.0 + 5.0 * 5.0).sqrt();
        assert_eq!(classify(d, 0.3, false), PressRelease::Jitter);
        assert!(!classify(d, 0.3, false).is_drag());
    }

    #[test]
    fn mid_band_fast_is_drag() {
        // Same displacement flicked in 20 ms ≈ 447 px/s.
        let d = (8.0_f64 * 8.0 + 5.0 * 5.0).sqrt();
        assert_eq!(classify(d, 0.02, false), PressRelease::Drag);
    }

    #[test]
    fn beyond_drag_radius_is_always_drag() {
        assert_eq!(classify(10.01, 0.01, false), PressRelease::Drag);
        // Even a fast flick with a large displacement is a drag.
        assert_eq!(classify(200.0, 0.05, false), PressRelease::Drag);
        assert_eq!(classify(360.0, 0.5, false), PressRelease::Drag);
    }

    #[test]
    fn held_past_click_radius_is_drag() {
        assert_eq!(classify(5.0, 0.31, false), PressRelease::Drag);
        // Exactly on the hold boundary stays in the velocity gate.
        assert_eq!(classify(5.0, 0.30, false), PressRelease::Jitter);
    }

    #[test]
    fn trackpad_deadzone_is_wider() {
        // 5 px: a click on trackpad, jitter-band on a mouse.
        assert_eq!(classify(5.0, 0.05, true), PressRelease::Click);
        assert_eq!(classify(5.0, 0.05, false), PressRelease::Drag);
        // 6 px trackpad edge: at the deadzone rim the velocity gate applies.
        assert_eq!(classify(6.0, 0.30, true), PressRelease::Jitter);
        assert_eq!(classify(6.0, 0.02, true), PressRelease::Drag);
        // ...unless held past the long-hold threshold, which is a drag.
        assert_eq!(classify(6.0, 1.0, true), PressRelease::Drag);
    }

    #[test]
    fn degenerate_inputs_do_not_panic() {
        assert_eq!(classify(5.0, 0.0, false), PressRelease::Drag);
        assert_eq!(classify(0.0, 0.0, false), PressRelease::Click);
    }
}
