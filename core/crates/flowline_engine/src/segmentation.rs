//! Focus-aware semantic segmentation + delayed commit / revision window.
//!
//! Swift twins: `EventReducer.swift` (focus scoring), `StepProductionGate.swift`
//! (provisional → confirmed commits), `RecorderWorkflowEngine.swift` (flap
//! tracker state). The sync port keeps everything deterministic on injected
//! millis so tests drive flap / confidence without timers.
//!
//! Scoring contract (task spec):
//! - bundle change → 0.95
//! - windowID/title change → 0.85
//! - AX element/role change → 0.70
//! - only cut on role change or window/bundle; popups never cut.
//!
//! Confidence contract:
//! `score = 0.35*focus + 0.25*gap_hysteresis + 0.15*ret + 0.15*clipboard + 0.10*velocity`
//! CUT when `> 0.6`, JOIN when `< 0.4`, else provisional.
//!
//! Delayed commit contract:
//! provisional emit immediately, confirm at +400 ms default
//! (150 ms clicks, 500 ms typing), max 2 × +200 ms extensions on a
//! contradicting event. Revision history logs `v1 provisional → v2 confirmed`.

use flowline_ir::RawElementContext;

// MARK: - Tunables (spec constants)

/// Revert a CUT app-switch when focus returns within this window.
pub const FLAP_REVERT_MILLIS: u64 = 800;
/// Fewer than this many in-between events keeps a flap revertible.
pub const FLAP_MAX_MIDDLE_EVENTS: u64 = 3;
/// Oscillation A→B→A→B inside this window holds the switch in limbo.
pub const OSCILLATION_WINDOW_MILLIS: u64 = 2000;
/// Limbo switches confirm this long after the last oscillation settles.
pub const LIMBO_SETTLE_MILLIS: u64 = 400;

/// Default provisional → confirmed window.
pub const CONFIRM_DEFAULT_MILLIS: u64 = 400;
/// Click/action fast path.
pub const CONFIRM_CLICK_MILLIS: u64 = 150;
/// Typing slow path (debounce tail).
pub const CONFIRM_TYPING_MILLIS: u64 = 500;
/// One contradicting-event extension.
pub const EXTENSION_MILLIS: u64 = 200;
/// Max extensions per pending commit.
pub const MAX_EXTENSIONS: u32 = 2;

/// Confidence gate thresholds.
pub const CUT_THRESHOLD: f64 = 0.6;
/// Below this the segments join.
pub const JOIN_THRESHOLD: f64 = 0.4;

// MARK: - Focus-change cut scoring

/// `true` for transient popup chrome that must never force a segment cut
/// (menus, popovers, sheets, drawers).
pub fn is_popup_context(ctx: &RawElementContext) -> bool {
    if let Some(role) = ctx.role.as_deref() {
        match role {
            "AXMenu" | "AXMenuBarItem" | "AXMenuItem" | "AXPopover" | "AXSheet"
            | "AXDrawer" | "AXPopUpButton" => return true,
            _ => {}
        }
        let lower = role.to_ascii_lowercase();
        if lower.contains("popup") || lower.contains("popover") || lower.contains("menu") {
            return true;
        }
    }
    if let Some(desc) = ctx.role_description.as_deref() {
        let lower = desc.to_ascii_lowercase();
        if lower.contains("popup") || lower.contains("popover") || lower.contains("menu") {
            return true;
        }
    }
    false
}

/// Bundle change scores 0.95; window identity (title or bounds) change 0.85;
/// AX role/subrole change 0.70. Anything else scores 0.0. A pure popup-role
/// delta never cuts (returns 0.0) per the "ignore popup" rule.
pub fn focus_cut_score(prev: &RawElementContext, curr: &RawElementContext) -> f64 {
    let prev_bundle = prev.bundle_identifier.as_deref().unwrap_or("");
    let curr_bundle = curr.bundle_identifier.as_deref().unwrap_or("");
    if prev_bundle != curr_bundle {
        return 0.95;
    }
    if prev.app_name != curr.app_name {
        return 0.95;
    }
    if prev.window_title != curr.window_title {
        return 0.85;
    }
    if prev.window_bounds != curr.window_bounds {
        // `None` ↔ `Some` and geometry moves both signal a window switch.
        // Identical `None`s fall through to the role check below.
        if prev.window_bounds.is_some() || curr.window_bounds.is_some() {
            return 0.85;
        }
    }
    let role_changed = prev.role != curr.role || prev.subrole != curr.subrole;
    if role_changed {
        if is_popup_context(curr) || is_popup_context(prev) {
            return 0.0;
        }
        return 0.70;
    }
    // Popup-only appearance with no other delta is not a cut.
    if is_popup_context(curr) && !is_popup_context(prev) {
        return 0.0;
    }
    0.0
}

/// Only role/window/bundle deltas cut; popups never do.
pub fn should_cut_on_focus(score: f64) -> bool {
    score >= 0.70
}

// MARK: - Confidence

/// Segmentation verdict for one boundary.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SegmentDecision {
    Cut,
    Join,
    Provisional,
}

/// Weighted confidence over five 0..1 signals.
pub fn confidence_score(
    focus: f64,
    gap_hysteresis: f64,
    ret: f64,
    clipboard: f64,
    velocity: f64,
) -> f64 {
    0.35 * focus.clamp(0.0, 1.0)
        + 0.25 * gap_hysteresis.clamp(0.0, 1.0)
        + 0.15 * ret.clamp(0.0, 1.0)
        + 0.15 * clipboard.clamp(0.0, 1.0)
        + 0.10 * velocity.clamp(0.0, 1.0)
}

/// CUT when `> 0.6`, JOIN when `< 0.4`, else provisional.
pub fn decide_confidence(score: f64) -> SegmentDecision {
    if score > CUT_THRESHOLD {
        SegmentDecision::Cut
    } else if score < JOIN_THRESHOLD {
        SegmentDecision::Join
    } else {
        SegmentDecision::Provisional
    }
}

/// Gap hysteresis 0..1 against the typing debounce window: a gap far past the
/// debounce is a confident cut, a gap well inside it is a confident join.
pub fn gap_hysteresis_score(gap_millis: u64, debounce_millis: u64) -> f64 {
    if debounce_millis == 0 {
        return 1.0;
    }
    let gap = gap_millis as f64;
    let debounce = debounce_millis as f64;
    if gap >= 2.0 * debounce {
        1.0
    } else if gap >= debounce {
        0.7
    } else if gap >= debounce / 2.0 {
        0.4
    } else {
        0.1
    }
}

/// Event-rate 0..1: bursts (≥5 ev/s) score high, idle streams score low.
/// Callers pass a short-window rate; the weighting keeps velocity minor (0.10).
pub fn velocity_score(events_per_sec: f64) -> f64 {
    if events_per_sec >= 5.0 {
        1.0
    } else if events_per_sec >= 2.0 {
        0.6
    } else {
        0.2
    }
}

// MARK: - Delayed commit / revision window

/// Which production path owns the pending commit (sets the confirm delay).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommitKind {
    Click,
    Typing,
    Other,
}

impl CommitKind {
    pub fn confirm_delay_millis(self) -> u64 {
        match self {
            CommitKind::Click => CONFIRM_CLICK_MILLIS,
            CommitKind::Typing => CONFIRM_TYPING_MILLIS,
            CommitKind::Other => CONFIRM_DEFAULT_MILLIS,
        }
    }
}

/// One provisionally emitted step awaiting confirmation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PendingCommit {
    pub step_id: String,
    pub provisional_millis: u64,
    pub confirm_at_millis: u64,
    pub extensions: u32,
    pub confirmed: bool,
}

impl PendingCommit {
    pub fn new(step_id: String, kind: CommitKind, now_millis: u64) -> Self {
        Self {
            step_id,
            provisional_millis: now_millis,
            confirm_at_millis: now_millis.saturating_add(kind.confirm_delay_millis()),
            extensions: 0,
            confirmed: false,
        }
    }

    /// Push the confirm deadline on a contradicting event (max 2 × +200 ms).
    /// Returns `true` when the extension applied.
    pub fn extend_on_contradiction(&mut self) -> bool {
        if self.confirmed || self.extensions >= MAX_EXTENSIONS {
            return false;
        }
        self.extensions += 1;
        self.confirm_at_millis = self.confirm_at_millis.saturating_add(EXTENSION_MILLIS);
        true
    }

    pub fn is_due(&self, now_millis: u64) -> bool {
        !self.confirmed && now_millis >= self.confirm_at_millis
    }
}

// MARK: - App-switch flap / oscillation

/// Dedup + history key: app identity *plus* window/title, never appName alone
/// (over-join fix: same app, new window must still cut).
pub fn app_switch_key(app_name: &str, bundle_id: Option<&str>, window_title: &str) -> String {
    format!(
        "{}|{}|{}",
        app_name,
        bundle_id.unwrap_or(""),
        window_title
    )
}

/// One emitted (or limbo-held) switch for flap bookkeeping.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SwitchRecord {
    pub key: String,
    pub millis: u64,
}

/// Limbo-held oscillation switch: CUT deferred until the focus settles.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LimboSwitch {
    pub bundle_id: Option<String>,
    pub app_name: String,
    pub window_title: String,
    pub key: String,
    pub first_millis: u64,
    pub confirm_at_millis: u64,
}

/// Flap-tracker verdict for an incoming switch.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FlapAction {
    /// Emit the switch step now.
    Emit,
    /// A→B→A within 800 ms with <3 middle events: drop the previous B step.
    Revert,
    /// A→B→A→B within 2 s: hold in limbo until settle+400 ms.
    HoldLimbo,
}

/// Pure flap/oscillation classifier over the emitted-switch history.
///
/// - `history`: previously *emitted* switches, oldest → newest.
/// - `events_since_last`: raw input events observed since the last emission.
/// - `now_millis`: arrival time of `key`.
pub fn classify_app_switch(
    history: &[SwitchRecord],
    key: &str,
    now_millis: u64,
    events_since_last: u64,
) -> FlapAction {
    if history.is_empty() {
        return FlapAction::Emit;
    }
    let Some(last) = history.last() else {
        return FlapAction::Emit;
    };
    if last.key == key {
        // Deduped upstream; reaching here is a no-op emit.
        return FlapAction::Emit;
    }
    // Flap revert: A … B → A inside 800 ms with <3 middle events.
    if history.len() >= 2 {
        let original = &history[history.len() - 2];
        if original.key == key
            && now_millis.saturating_sub(last.millis) <= FLAP_REVERT_MILLIS
            && events_since_last < FLAP_MAX_MIDDLE_EVENTS
        {
            return FlapAction::Revert;
        }
    } else if history.len() == 1 {
        // Single-hop return (baseline A → B → A): history holds only B, so
        // compare against the caller's seeded baseline via the same rule when
        // the baseline key is supplied as the first history entry by the
        // engine. Without a baseline there is nothing to revert to.
    }
    // Oscillation: A→B→A→B inside 2 s → hold in limbo.
    if history.len() >= 3 {
        let n = history.len();
        let a = &history[n - 3];
        let b = &history[n - 2];
        let c = &history[n - 1];
        if a.key == c.key && b.key != a.key && key == b.key {
            let span = now_millis.saturating_sub(a.millis);
            if span <= OSCILLATION_WINDOW_MILLIS {
                return FlapAction::HoldLimbo;
            }
        }
        // General rapid alternation: last two hops both inside 2 s and the
        // newcomer re-visits either of them → limbo until settle.
        if c.millis.saturating_sub(b.millis) <= OSCILLATION_WINDOW_MILLIS
            && now_millis.saturating_sub(c.millis) <= OSCILLATION_WINDOW_MILLIS
            && (key == a.key || key == c.key)
        {
            return FlapAction::HoldLimbo;
        }
    }
    FlapAction::Emit
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ctx(app: &str, bundle: Option<&str>, window: &str, role: Option<&str>) -> RawElementContext {
        RawElementContext {
            app_name: app.to_string(),
            bundle_identifier: bundle.map(|s| s.to_string()),
            window_title: window.to_string(),
            role: role.map(|s| s.to_string()),
            subrole: None,
            title: None,
            value: None,
            placeholder: None,
            role_description: None,
            is_secure: false,
            bounding_box: None,
            window_bounds: None,
            selectors: Vec::new(),
        }
    }

    #[test]
    fn focus_scores_match_spec() {
        let a = ctx("Safari", Some("com.apple.Safari"), "Docs", Some("AXButton"));
        let b = ctx("Terminal", Some("com.apple.Terminal"), "zsh", Some("AXButton"));
        assert_eq!(focus_cut_score(&a, &b), 0.95);

        let w2 = ctx("Safari", Some("com.apple.Safari"), "Other tab", Some("AXButton"));
        assert_eq!(focus_cut_score(&a, &w2), 0.85);

        let r2 = ctx("Safari", Some("com.apple.Safari"), "Docs", Some("AXTextField"));
        assert_eq!(focus_cut_score(&a, &r2), 0.70);

        let popup = ctx("Safari", Some("com.apple.Safari"), "Docs", Some("AXMenu"));
        assert_eq!(focus_cut_score(&a, &popup), 0.0);
        assert!(!should_cut_on_focus(0.0));
        assert!(should_cut_on_focus(0.70));
    }

    #[test]
    fn confidence_thresholds_gate_cut_join_provisional() {
        // Strong focus + wide gap → CUT.
        let cut = confidence_score(0.95, 1.0, 0.0, 0.5, 0.2);
        assert!(cut > CUT_THRESHOLD, "cut score {cut}");
        assert_eq!(decide_confidence(cut), SegmentDecision::Cut);
        // Weak everything → JOIN.
        let join = confidence_score(0.0, 0.1, 0.0, 0.0, 0.2);
        assert!(join < JOIN_THRESHOLD, "join score {join}");
        assert_eq!(decide_confidence(join), SegmentDecision::Join);
        // Middle → provisional.
        assert_eq!(decide_confidence(0.5), SegmentDecision::Provisional);
        assert_eq!(decide_confidence(0.6), SegmentDecision::Provisional);
    }

    #[test]
    fn pending_commit_delays_and_extensions() {
        let mut c = PendingCommit::new("step-0001".into(), CommitKind::Click, 1000);
        assert_eq!(c.confirm_at_millis, 1150);
        assert!(c.extend_on_contradiction());
        assert!(c.extend_on_contradiction());
        assert!(!c.extend_on_contradiction());
        assert_eq!(c.extensions, 2);
        let t = PendingCommit::new("step-0002".into(), CommitKind::Typing, 1000);
        assert_eq!(t.confirm_at_millis, 1500);
        let d = PendingCommit::new("step-0003".into(), CommitKind::Other, 1000);
        assert_eq!(d.confirm_at_millis, 1400);
    }

    #[test]
    fn flap_revert_and_oscillation() {
        let a = "A|a|w".to_string();
        let b = "B|b|w".to_string();
        let history = vec![
            SwitchRecord { key: a.clone(), millis: 0 },
            SwitchRecord { key: b.clone(), millis: 100 },
        ];
        assert_eq!(
            classify_app_switch(&history, &a, 500, 1),
            FlapAction::Revert
        );
        // Too many middle events → no revert.
        assert_eq!(
            classify_app_switch(&history, &a, 500, 5),
            FlapAction::Emit
        );
        // Too late → no revert.
        assert_eq!(
            classify_app_switch(&history, &a, 2000, 1),
            FlapAction::Emit
        );
        // Oscillation A→B→A→B inside 2 s → limbo.
        let osc = vec![
            SwitchRecord { key: a.clone(), millis: 0 },
            SwitchRecord { key: b.clone(), millis: 400 },
            SwitchRecord { key: a.clone(), millis: 800 },
        ];
        assert_eq!(
            classify_app_switch(&osc, &b, 1200, 10),
            FlapAction::HoldLimbo
        );
    }
}
