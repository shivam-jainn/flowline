//! `EventDebouncer` port (`Sources/FlowlinePipeline/EventDebouncer.swift`).
//!
//! A rejected event does **not** move the window forward; only accepted
//! events do. Strictly-greater-than comparison, verbatim.
//!
//! [`EventDebouncer::should_accept_click`] adds pointer disambiguation for
//! click steps: the window adapts to inter-click pointer velocity, close +
//! fast repeats are bounced, and OS-reported doubles inside 500 ms are
//! accepted as doubles (never suppressed as bounce, never split into two
//! singles). Rejected bounces still hold the window.

use crate::drag::pointer_velocity;
use flowline_ir::Point2D;

/// Distance below which a fast repeat is contact bounce, not intent.
pub const BOUNCE_RADIUS_PX: f64 = 6.0;
/// OS double-click coalescing window (seconds).
pub const DOUBLE_CLICK_WINDOW_SECS: f64 = 0.5;

/// Velocity-aware window: `clamp(base * (1.5 - min(vel / 10, 0.8)), 80, 400)ms`.
///
/// `velocity_px_per_sec` is the inter-click pointer speed (`None` when the
/// previous point is unknown — falls back to `base_secs` so location-less
/// replays keep the legacy fixed window).
pub fn adaptive_interval_secs(base_secs: f64, velocity_px_per_sec: Option<f64>) -> f64 {
    match velocity_px_per_sec {
        None => base_secs,
        Some(v) => {
            let v = v.max(0.0);
            (base_secs * (1.5 - (v / 10.0).min(0.8))).clamp(0.08, 0.40)
        }
    }
}

#[derive(Debug, Clone)]
pub struct EventDebouncer {
    pub min_interval: f64,
    last_accepted: Option<f64>,
    last_point: Option<Point2D>,
}

impl EventDebouncer {
    pub fn new(min_interval: f64) -> Self {
        Self {
            min_interval,
            last_accepted: None,
            last_point: None,
        }
    }

    /// Returns `true` when this timestamp (seconds) is outside the window.
    ///
    /// Legacy fixed-window path (golden replays pin this verbatim). Click
    /// steps should prefer [`Self::should_accept_click`].
    pub fn should_accept(&mut self, now_secs: f64) -> bool {
        if let Some(last) = self.last_accepted {
            if now_secs - last <= self.min_interval {
                return false;
            }
        }
        self.last_accepted = Some(now_secs);
        true
    }

    /// Velocity-aware click gate.
    ///
    /// - First click: always accepted.
    /// - OS double (`os_click_count >= 2`) within 500 ms of the accepted
    ///   click: accepted as the double — not suppressed, not a second single.
    /// - Point within 6 px and `dt <= adaptive_window`: bounce — rejected,
    ///   and the window does **not** move.
    /// - Otherwise: distinct click, accepted.
    /// - Locations unknown: falls back to the legacy time-only window.
    pub fn should_accept_click(
        &mut self,
        now_secs: f64,
        point: Option<Point2D>,
        os_click_count: i64,
    ) -> bool {
        let Some(last) = self.last_accepted else {
            self.last_accepted = Some(now_secs);
            self.last_point = point;
            return true;
        };
        let dt = now_secs - last;
        if dt < 0.0 {
            // Out-of-order clock: never suppress, never move the window back.
            return true;
        }
        // OS-reported double inside the system window is the double — accept
        // even when it lands inside the bounce window.
        if os_click_count >= 2 && dt < DOUBLE_CLICK_WINDOW_SECS {
            self.last_accepted = Some(now_secs);
            self.last_point = point;
            return true;
        }
        match (self.last_point, point) {
            (Some(prev), Some(cur)) => {
                let dist = ((cur.x - prev.x).powi(2) + (cur.y - prev.y).powi(2)).sqrt();
                let vel = if dt > 0.0 {
                    pointer_velocity(dist, dt)
                } else {
                    f64::INFINITY
                };
                let window = adaptive_interval_secs(self.min_interval, Some(vel));
                if dist < BOUNCE_RADIUS_PX && dt <= window {
                    return false;
                }
                self.last_accepted = Some(now_secs);
                self.last_point = point;
                true
            }
            _ => {
                let window = adaptive_interval_secs(self.min_interval, None);
                if dt <= window {
                    return false;
                }
                self.last_accepted = Some(now_secs);
                self.last_point = point;
                true
            }
        }
    }

    pub fn reset(&mut self) {
        self.last_accepted = None;
        self.last_point = None;
    }
}

impl Default for EventDebouncer {
    fn default() -> Self {
        Self::new(0.20)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_within_window_and_holds_it() {
        let mut d = EventDebouncer::new(0.2);
        assert!(d.should_accept(0.0));
        assert!(!d.should_accept(0.05));
        // Rejected event does not move the window: 0.3 - 0.0 > 0.2.
        assert!(d.should_accept(0.3));
        assert!(!d.should_accept(0.35));
        assert!(d.should_accept(1.0));
    }

    #[test]
    fn boundary_is_exclusive() {
        let mut d = EventDebouncer::new(0.2);
        assert!(d.should_accept(0.0));
        // Exactly min_interval is NOT accepted (Swift `>`).
        assert!(!d.should_accept(0.2));
        assert!(d.should_accept(0.200_000_1));
    }

    #[test]
    fn reset_reopens() {
        let mut d = EventDebouncer::new(10.0);
        assert!(d.should_accept(0.0));
        assert!(!d.should_accept(1.0));
        d.reset();
        assert!(d.should_accept(1.0));
    }

    #[test]
    fn adaptive_interval_clamps() {
        // Stationary pointer: 200 * 1.5 = 300 ms.
        assert!((adaptive_interval_secs(0.2, Some(0.0)) - 0.30).abs() < 1e-12);
        // Fast pointer: 200 * (1.5 - 0.8) = 140 ms.
        assert!((adaptive_interval_secs(0.2, Some(100.0)) - 0.14).abs() < 1e-12);
        // Unknown velocity: base window (legacy replay parity).
        assert!((adaptive_interval_secs(0.2, None) - 0.20).abs() < 1e-12);
        // Clamp rails.
        assert!((adaptive_interval_secs(0.2, Some(1e9)) - 0.14).abs() < 1e-12);
        assert!((adaptive_interval_secs(1.0, Some(0.0)) - 0.40).abs() < 1e-12);
        assert!((adaptive_interval_secs(0.01, Some(1e9)) - 0.08).abs() < 1e-12);
    }

    #[test]
    fn click_close_fast_is_bounce_and_holds_window() {
        let mut d = EventDebouncer::new(0.2);
        let p = Point2D::new(100.0, 200.0);
        assert!(d.should_accept_click(0.0, Some(p), 1));
        // 3 px away after 100 ms: bounce, window unmoved.
        assert!(!d.should_accept_click(0.1, Some(Point2D::new(103.0, 200.0)), 1));
        // 350 ms after the *accepted* click: outside the ~300 ms stationary
        // window, so a distinct click.
        assert!(d.should_accept_click(0.35, Some(p), 1));
    }

    #[test]
    fn click_far_fast_is_distinct() {
        let mut d = EventDebouncer::new(0.2);
        assert!(d.should_accept_click(0.0, Some(Point2D::new(0.0, 0.0)), 1));
        // 100 px in 100 ms: fast relocation, distinct even though quick.
        assert!(d.should_accept_click(0.1, Some(Point2D::new(100.0, 0.0)), 1));
    }

    #[test]
    fn os_double_is_accepted_not_suppressed() {
        let mut d = EventDebouncer::new(0.2);
        let p = Point2D::new(50.0, 50.0);
        assert!(d.should_accept_click(0.0, Some(p), 1));
        // Second press of an OS double lands inside the bounce window but
        // must still surface as the double.
        assert!(d.should_accept_click(0.25, Some(p), 2));
    }

    #[test]
    fn click_rejected_bounce_holds_window_for_later() {
        let mut d = EventDebouncer::new(0.2);
        let p = Point2D::new(7.0, 7.0);
        assert!(d.should_accept_click(1.0, Some(p), 1));
        assert!(!d.should_accept_click(1.1, Some(p), 1));
        assert!(d.should_accept_click(1.35, Some(p), 1));
        assert!(!d.should_accept_click(1.40, Some(p), 1));
    }
}
