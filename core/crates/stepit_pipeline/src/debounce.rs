//! `EventDebouncer` port (`Sources/StepItPipeline/EventDebouncer.swift`).
//!
//! A rejected event does **not** move the window forward; only accepted
//! events do. Strictly-greater-than comparison, verbatim.

#[derive(Debug, Clone)]
pub struct EventDebouncer {
    pub min_interval: f64,
    last_accepted: Option<f64>,
}

impl EventDebouncer {
    pub fn new(min_interval: f64) -> Self {
        Self {
            min_interval,
            last_accepted: None,
        }
    }

    /// Returns `true` when this timestamp (seconds) is outside the window.
    pub fn should_accept(&mut self, now_secs: f64) -> bool {
        if let Some(last) = self.last_accepted {
            if now_secs - last <= self.min_interval {
                return false;
            }
        }
        self.last_accepted = Some(now_secs);
        true
    }

    pub fn reset(&mut self) {
        self.last_accepted = None;
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
}
