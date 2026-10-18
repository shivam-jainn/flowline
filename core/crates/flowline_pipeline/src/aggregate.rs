//! `TypingBatchAggregator` port (`Sources/FlowlinePipeline/TypingBatchAggregator.swift`).
//!
//! Synchronous state machine: the Swift `async` context provider and timer
//! task become explicit `ctx: &RawElementContext` arguments and injected
//! `now_millis: u64` timestamps. No clock, no RNG.
//!
//! Semantics mirrored verbatim:
//! - secure-field keystrokes never enter the buffer raw (bullets when masking
//!   is on, dropped when off);
//! - Return finalizes immediately (smart: multiline plain Return joins);
//! - Control-C appends `^C` / ` ^C` and finalizes;
//! - flush drops whitespace-only buffers;
//! - hysteresis segmentation (`T_LOW` JOIN / `T_HIGH` CUT, ambiguous holds
//!   unless focus/app/Return corroborates) with per-app profiles
//!   (terminal 900/2500, editor 600/1800, URL 400/1200) and adaptive
//!   `T_user = 0.8 * T_app + 0.2 * p95_IKI` personalization;
//! - any bundle/window/AX-role change forces a cut before the next char
//!   (`AXUnknown` popups are ignorable noise);
//! - paste/burst/IME: >15 Hz bursts, `Cmd+V`, or clipboard-hash changes are
//!   atomic (never cut inside); the gap timer suspends during IME;
//! - Backspace word-undo coalesces; whitespace-only and secure invariants hold;
//! - inactivity past the effective high threshold cuts the batch on the next
//!   ingestion (or via [`TypingBatchAggregator::poll_timeout`]);
//! - finalization normalizes empty/`"Unknown App"` app names to `"Terminal"`,
//!   falls window title back to the app name, strips secure values, classifies,
//!   and centers on the window when it is larger than 50×50.

use crate::classify::{
    InputClassification, ReturnAction, adaptive_thresholds, classify,
    classify_return, focus_identity_changed, p95_iki,
    should_cut_by_hysteresis, thresholds_for_context,
};
use flowline_ir::{Point2D, RawElementContext};

/// Apply the typing-batch context fallbacks (`TypingBatchAggregator.makeResult`):
/// unknown/empty app becomes `"Terminal"`, empty window title becomes the app
/// name, and secure values never ride along. Shared with `flowline_engine`
/// (which delegates here instead of duplicating the block).
pub fn normalize_batch_context(mut context: RawElementContext) -> RawElementContext {
    if context.app_name.is_empty() || context.app_name == RawElementContext::unknown().app_name {
        context.app_name = "Terminal".to_string();
    }
    if context.window_title.is_empty() {
        context.window_title.clone_from(&context.app_name);
    }
    if context.is_secure {
        context.value = None;
    }
    context
}

#[derive(Debug, Clone)]
pub struct TypingBatchResult {
    pub text_blob: String,
    pub context: Option<RawElementContext>,
    pub classification: InputClassification,
    pub location: Point2D,
}

#[derive(Debug, Clone)]
pub struct TypingBatchAggregator {
    debounce_interval_millis: u64,
    /// `true` once [`TypingBatchAggregator::enable_smart_segmentation`] runs:
    /// timeouts use per-app hysteresis + adaptive p95 instead of the single
    /// legacy interval.
    smart_segmentation: bool,
    buffer: String,
    last_location: Point2D,
    last_activity_millis: Option<u64>,
    pending_context: Option<RawElementContext>,
    mask_secure: bool,
    iki_history: Vec<u64>,
    ime_composing: bool,
    clipboard_hash: Option<u64>,
}

impl TypingBatchAggregator {
    pub fn new(debounce_interval_millis: u64) -> Self {
        Self {
            debounce_interval_millis,
            smart_segmentation: false,
            buffer: String::new(),
            last_location: Point2D::ZERO,
            last_activity_millis: None,
            pending_context: None,
            mask_secure: true,
            iki_history: Vec::new(),
            ime_composing: false,
            clipboard_hash: None,
        }
    }

    /// Hysteresis-ready aggregator: `T_LOW 600` JOIN / `T_HIGH 1800` CUT
    /// defaults (per-app overrides + adaptive p95 at ingestion time).
    pub fn new_smart() -> Self {
        Self {
            debounce_interval_millis: 600,
            smart_segmentation: true,
            buffer: String::new(),
            last_location: Point2D::ZERO,
            last_activity_millis: None,
            pending_context: None,
            mask_secure: true,
            iki_history: Vec::new(),
            ime_composing: false,
            clipboard_hash: None,
        }
    }

    /// Opt an existing aggregator into hysteresis segmentation.
    pub fn enable_smart_segmentation(&mut self) {
        self.smart_segmentation = true;
    }

    pub fn set_mask_secure(&mut self, mask: bool) {
        self.mask_secure = mask;
    }

    /// Suspend the gap timer while IME composition is active.
    pub fn set_composing(&mut self, composing: bool) {
        self.ime_composing = composing;
    }

    pub fn is_composing(&self) -> bool {
        self.ime_composing
    }

    pub fn set_clipboard_hash(&mut self, hash: Option<u64>) {
        self.clipboard_hash = hash;
    }

    pub fn clipboard_hash(&self) -> Option<u64> {
        self.clipboard_hash
    }

    pub fn has_pending_text(&self) -> bool {
        !self.buffer.trim().is_empty()
    }

    /// Effective `(low, high)` thresholds for `ctx`.
    ///
    /// Legacy aggregators return the single debounce interval for both;
    /// smart aggregators use the per-app profile blended with the adaptive
    /// `0.8 * T_app + 0.2 * p95_IKI` personalization.
    pub fn effective_thresholds(&self, ctx: &RawElementContext) -> (u64, u64) {
        if !self.smart_segmentation {
            return (self.debounce_interval_millis, self.debounce_interval_millis);
        }
        let (low, high) = thresholds_for_context(ctx);
        adaptive_thresholds(low, high, p95_iki(&self.iki_history))
    }

    fn thresholds_for_pending(&self) -> (u64, u64) {
        match self.pending_context.as_ref() {
            Some(ctx) => self.effective_thresholds(ctx),
            None => {
                if self.smart_segmentation {
                    adaptive_thresholds(600, 1800, p95_iki(&self.iki_history))
                } else {
                    (self.debounce_interval_millis, self.debounce_interval_millis)
                }
            }
        }
    }

    fn gap_since_last(&self, now_millis: u64) -> Option<u64> {
        self.last_activity_millis
            .map(|last| now_millis.saturating_sub(last))
    }

    fn record_gap(&mut self, now_millis: u64) {
        if let Some(gap) = self.gap_since_last(now_millis) {
            self.iki_history.push(gap);
            if self.iki_history.len() > 200 {
                let excess = self.iki_history.len() - 200;
                self.iki_history.drain(..excess);
            }
        }
    }

    fn is_timed_out(&self, now_millis: u64) -> bool {
        if self.ime_composing {
            return false;
        }
        let Some(last) = self.last_activity_millis else {
            return false;
        };
        let gap = now_millis.saturating_sub(last);
        let (low, high) = self.thresholds_for_pending();
        if self.smart_segmentation {
            // Ambiguous band holds here; corroboration (focus/Return) is handled
            // by the caller's explicit cut before reaching the timeout.
            // (Burst-rate gaps are far below T_LOW, so hysteresis already joins
            // them — no special-case needed on the timer path.)
            should_cut_by_hysteresis(gap, low, high, false)
        } else {
            gap >= high
        }
    }

    /// Focus-cut probe: flush the pending batch when the element identity
    /// changed (bundle/window/AX-role). Returns the cut batch, if any.
    fn take_focus_cut(&mut self, ctx: &RawElementContext) -> Option<TypingBatchResult> {
        if self.buffer.is_empty() {
            return None;
        }
        if !focus_identity_changed(self.pending_context.as_ref(), ctx) {
            return None;
        }
        let text = std::mem::take(&mut self.buffer);
        let flushed_ctx = self.pending_context.take();
        self.last_activity_millis = None;
        if text.trim().is_empty() {
            return None;
        }
        let location = self.last_location;
        Some(make_result(
            &text,
            location,
            &flushed_ctx.unwrap_or_else(RawElementContext::unknown),
        ))
    }

    fn take_timed_out(&mut self, now_millis: u64) -> Option<TypingBatchResult> {
        if !self.is_timed_out(now_millis) {
            return None;
        }
        let text = std::mem::take(&mut self.buffer);
        let ctx = self.pending_context.take();
        self.last_activity_millis = None;
        if text.trim().is_empty() {
            return None;
        }
        let location = self.last_location;
        Some(make_result(&text, location, &ctx.unwrap_or_else(RawElementContext::unknown)))
    }

    /// Inactivity finalization path (the timer arm in Swift).
    pub fn poll_timeout(&mut self, now_millis: u64) -> Option<TypingBatchResult> {
        self.take_timed_out(now_millis)
    }

    /// Completed batches cut by a focus or timeout boundary *before* this keystroke.
    /// Mirrors one `append(char:at:)` (context probed per keystroke).
    pub fn append(
        &mut self,
        ch: &str,
        location: Point2D,
        ctx: &RawElementContext,
        now_millis: u64,
    ) -> Vec<TypingBatchResult> {
        let mut done = Vec::new();
        // Focus change always forces the boundary first (over-join killer).
        if let Some(r) = self.take_focus_cut(ctx) {
            done.push(r);
        } else if let Some(r) = self.take_timed_out(now_millis) {
            done.push(r);
        }
        self.record_gap(now_millis);
        if ctx.is_secure {
            if self.mask_secure {
                let n = ch.chars().count().max(1);
                self.buffer.extend(std::iter::repeat_n('•', n));
            }
        } else {
            self.buffer.push_str(ch);
        }
        self.last_location = location;
        self.pending_context = Some(ctx.clone());
        self.last_activity_millis = Some(now_millis);
        done
    }

    /// Atomic paste: one `text` insertion, never cut inside.
    ///
    /// Forces the boundary *before* the paste when the focused element
    /// changed (or the clipboard hash rotated while text is pending), then
    /// buffers the whole payload as a single unit. Secure fields still mask.
    pub fn handle_paste(
        &mut self,
        text: &str,
        location: Point2D,
        ctx: &RawElementContext,
        now_millis: u64,
        clipboard_hash: Option<u64>,
    ) -> Vec<TypingBatchResult> {
        let mut done = Vec::new();
        // A clipboard rotation is the paste *detection* signal, not a cut cue:
        // the boundary before the paste lands only when the focused element
        // changed. The payload itself is always one atomic unit.
        if let Some(r) = self.take_focus_cut(ctx) {
            done.push(r);
        } else if let Some(r) = self.take_timed_out(now_millis) {
            // A genuine pause before the paste still cuts; burst-rate pastes
            // (tiny gaps) never reach here via hysteresis.
            done.push(r);
        }
        if let Some(hash) = clipboard_hash {
            self.clipboard_hash = Some(hash);
        }
        self.record_gap(now_millis);
        if text.is_empty() {
            self.last_location = location;
            self.pending_context = Some(ctx.clone());
            self.last_activity_millis = Some(now_millis);
            return done;
        }
        if ctx.is_secure {
            if self.mask_secure {
                let n = text.chars().count().max(1);
                self.buffer.extend(std::iter::repeat_n('•', n));
            }
        } else {
            self.buffer.push_str(text);
        }
        self.last_location = location;
        self.pending_context = Some(ctx.clone());
        self.last_activity_millis = Some(now_millis);
        done
    }

    pub fn backspace(&mut self, location: Point2D, now_millis: u64) -> Vec<TypingBatchResult> {
        let mut done = Vec::new();
        if let Some(r) = self.take_timed_out(now_millis) {
            done.push(r);
        }
        self.record_gap(now_millis);
        if !self.buffer.is_empty() {
            self.buffer.pop();
        }
        self.last_location = location;
        self.last_activity_millis = Some(now_millis);
        done
    }

    /// Option+Backspace word-undo: delete to the previous word boundary and
    /// keep the (now shorter) batch coalesced.
    pub fn backspace_word(&mut self, location: Point2D, now_millis: u64) -> Vec<TypingBatchResult> {
        let mut done = Vec::new();
        if let Some(r) = self.take_timed_out(now_millis) {
            done.push(r);
        }
        self.record_gap(now_millis);
        pop_previous_word(&mut self.buffer);
        self.last_location = location;
        self.last_activity_millis = Some(now_millis);
        done
    }

    /// Enter / Return finalizes the command / line immediately.
    /// Legacy unconditional cut (terminal / single-line parity).
    pub fn handle_return(
        &mut self,
        location: Point2D,
        ctx: &RawElementContext,
        now_millis: u64,
    ) -> Option<TypingBatchResult> {
        let _ = now_millis;
        self.last_activity_millis = None;
        self.pending_context = None;
        self.ime_composing = false;
        let text = std::mem::take(&mut self.buffer);
        if text.trim().is_empty() {
            return None;
        }
        Some(make_result(&text, location, ctx))
    }

    /// Smart Return: terminal / single-line / `Cmd+Return` CUT; multiline
    /// plain Return JOINs a newline into the pending batch.
    pub fn handle_return_smart(
        &mut self,
        location: Point2D,
        ctx: &RawElementContext,
        now_millis: u64,
        command_held: bool,
    ) -> Option<TypingBatchResult> {
        if ctx.is_secure {
            return self.handle_return(location, ctx, now_millis);
        }
        match classify_return(ctx, command_held) {
            ReturnAction::Cut => self.handle_return(location, ctx, now_millis),
            ReturnAction::JoinNewline => {
                // Newline joins the batch: never an implicit cut. Record the
                // gap for adaptivity, then buffer the newline.
                self.record_gap(now_millis);
                self.buffer.push('\n');
                self.last_location = location;
                self.pending_context = Some(ctx.clone());
                self.last_activity_millis = Some(now_millis);
                None
            }
        }
    }

    /// Control+C appends the `^C` marker and finalizes.
    pub fn handle_control_c(
        &mut self,
        location: Point2D,
        ctx: &RawElementContext,
        now_millis: u64,
    ) -> Option<TypingBatchResult> {
        if self.buffer.is_empty() {
            self.buffer = "^C".to_string();
        } else {
            self.buffer.push_str(" ^C");
        }
        self.handle_return(location, ctx, now_millis)
    }

    /// The **only** flush API. Returns the final batch or `None`.
    pub fn flush_pending(&mut self, ctx: &RawElementContext) -> Option<TypingBatchResult> {
        self.last_activity_millis = None;
        self.pending_context = None;
        let text = std::mem::take(&mut self.buffer);
        if text.trim().is_empty() {
            return None;
        }
        Some(make_result(&text, self.last_location, ctx))
    }
}

impl Default for TypingBatchAggregator {
    fn default() -> Self {
        Self::new(1_000)
    }
}

/// Delete the previous word: trailing separators first, then one run of
/// word characters, then any dangling separator left behind so batches never
/// end with a stray space. Empty / whitespace-only buffers stay empty.
fn pop_previous_word(buffer: &mut String) {
    if buffer.is_empty() {
        return;
    }
    // Work on chars to keep unicode boundaries intact.
    let mut chars: Vec<char> = buffer.chars().collect();
    while chars.last().is_some_and(|c| c.is_whitespace()) {
        chars.pop();
    }
    while chars.last().is_some_and(|c| !c.is_whitespace()) {
        chars.pop();
    }
    while chars.last().is_some_and(|c| c.is_whitespace()) {
        chars.pop();
    }
    *buffer = chars.into_iter().collect();
}

fn make_result(text: &str, location: Point2D, raw: &RawElementContext) -> TypingBatchResult {
    let context = normalize_batch_context(raw.clone());

    let classification = classify(text, Some(&context));

    let mut effective = location;
    if let Some(bounds) = context.window_bounds {
        if bounds.width > 50.0 && bounds.height > 50.0 {
            effective = bounds.center();
        }
    }

    TypingBatchResult {
        text_blob: text.to_string(),
        context: Some(context),
        classification,
        location: effective,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn ctx(app: &str) -> RawElementContext {
        RawElementContext {
            app_name: app.to_string(),
            bundle_identifier: None,
            window_title: String::new(),
            role: None,
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

    use flowline_ir::ElementRect;

    fn notes() -> RawElementContext {
        let mut c = ctx("Notes");
        c.window_title = "Draft".to_string();
        c
    }

    fn ghostty() -> RawElementContext {
        let mut c = ctx("Ghostty");
        c.bundle_identifier = Some("com.mitchellh.ghostty".to_string());
        c.window_title = "ghostty".to_string();
        c
    }

    fn feed(agg: &mut TypingBatchAggregator, text: &str, ctx: &RawElementContext, t: u64) {
        for ch in text.chars() {
            let out = agg.append(&ch.to_string(), Point2D::ZERO, ctx, t);
            assert!(out.is_empty(), "unexpected timeout cut while feeding");
        }
    }

    #[test]
    fn append_and_flush_coalesces() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new(50);
        assert!(!agg.has_pending_text());
        feed(&mut agg, "hello", &ctx, 0);
        assert!(agg.has_pending_text());
        let r = agg.flush_pending(&ctx).expect("batch");
        assert_eq!(r.text_blob, "hello");
        assert_eq!(r.classification, InputClassification::Text);
        assert!(!agg.has_pending_text());
        assert!(agg.flush_pending(&ctx).is_none());
    }

    #[test]
    fn flush_without_pending_returns_none() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new(50);
        assert!(agg.flush_pending(&ctx).is_none());
        let out = agg.append(" ", Point2D::ZERO, &ctx, 0);
        assert!(out.is_empty());
        assert!(agg.flush_pending(&ctx).is_none());
    }

    #[test]
    fn return_finalizes_immediately() {
        let ctx = ghostty();
        let mut agg = TypingBatchAggregator::new(5_000);
        feed(&mut agg, "git status", &ctx, 0);
        let r = agg
            .handle_return(Point2D::new(100.0, 100.0), &ctx, 10)
            .expect("batch");
        assert_eq!(r.text_blob, "git status");
        assert_eq!(r.classification, InputClassification::Terminal);
        assert!(!agg.has_pending_text());
    }

    #[test]
    fn return_on_empty_returns_none() {
        let ctx = ghostty();
        let mut agg = TypingBatchAggregator::new(5_000);
        assert!(agg.handle_return(Point2D::ZERO, &ctx, 0).is_none());
    }

    #[test]
    fn timeout_cuts_batch() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new(50);
        feed(&mut agg, "hi", &ctx, 0);
        let r = agg.poll_timeout(60).expect("timeout batch");
        assert_eq!(r.text_blob, "hi");
        assert!(agg.poll_timeout(120).is_none());
        // Exact boundary cuts (>= interval).
        feed(&mut agg, "yo", &ctx, 1_000);
        let r = agg.poll_timeout(1_050).expect("boundary batch");
        assert_eq!(r.text_blob, "yo");
    }

    #[test]
    fn append_after_timeout_returns_cut_first() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new(50);
        feed(&mut agg, "hi", &ctx, 0);
        let cut = agg.append("!", Point2D::ZERO, &ctx, 200);
        assert_eq!(cut.len(), 1);
        assert_eq!(cut[0].text_blob, "hi");
        let r = agg.flush_pending(&ctx).expect("rest");
        assert_eq!(r.text_blob, "!");
    }

    #[test]
    fn backspace_edits_buffer() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new(5_000);
        feed(&mut agg, "abc", &ctx, 0);
        agg.backspace(Point2D::ZERO, 1);
        agg.backspace(Point2D::ZERO, 2);
        let r = agg.flush_pending(&ctx).expect("batch");
        assert_eq!(r.text_blob, "a");
    }

    #[test]
    fn control_c_appends_marker_and_finalizes() {
        let ctx = ghostty();
        let mut agg = TypingBatchAggregator::new(5_000);
        feed(&mut agg, "npm x", &ctx, 0);
        agg.backspace(Point2D::ZERO, 1);
        let r = agg.handle_control_c(Point2D::ZERO, &ctx, 2).expect("batch");
        assert_eq!(r.text_blob, "npm  ^C");
        assert_eq!(r.classification, InputClassification::Terminal);
    }

    #[test]
    fn control_c_on_empty_produces_marker() {
        let ctx = ghostty();
        let mut agg = TypingBatchAggregator::new(5_000);
        let r = agg.handle_control_c(Point2D::ZERO, &ctx, 0).expect("batch");
        assert_eq!(r.text_blob, "^C");
    }

    #[test]
    fn empty_app_falls_back_to_terminal() {
        let mut ctx = ctx("");
        ctx.role = Some("AXTextField".to_string());
        let mut agg = TypingBatchAggregator::new(5_000);
        feed(&mut agg, "ls", &ctx, 0);
        let r = agg.flush_pending(&ctx).expect("batch");
        let c = r.context.expect("context");
        assert_eq!(c.app_name, "Terminal");
        assert_eq!(c.window_title, "Terminal");
        assert_eq!(r.classification, InputClassification::Terminal);
    }

    #[test]
    fn window_bounds_produce_center_location() {
        let mut ctx = notes();
        ctx.window_bounds = Some(ElementRect::new(100.0, 200.0, 400.0, 200.0));
        let mut agg = TypingBatchAggregator::new(5_000);
        agg.append("x", Point2D::new(1.0, 2.0), &ctx, 0);
        let r = agg.flush_pending(&ctx).expect("batch");
        assert_eq!(r.location, Point2D::new(300.0, 300.0));
    }

    #[test]
    fn tiny_window_keeps_recorded_location() {
        let mut ctx = notes();
        ctx.window_bounds = Some(ElementRect::new(0.0, 0.0, 10.0, 10.0));
        let mut agg = TypingBatchAggregator::new(5_000);
        agg.append("x", Point2D::new(1.0, 2.0), &ctx, 0);
        let r = agg.flush_pending(&ctx).expect("batch");
        assert_eq!(r.location, Point2D::new(1.0, 2.0));
    }

    fn secure_ctx() -> RawElementContext {
        let mut c = ctx("Safari");
        c.window_title = "Sign In".to_string();
        c.role = Some("AXTextField".to_string());
        c.subrole = Some("AXSecureTextField".to_string());
        c.value = Some("hunter2".to_string());
        c.is_secure = true;
        c.bounding_box = Some(ElementRect::new(10.0, 10.0, 200.0, 30.0));
        c
    }

    #[test]
    fn secure_field_masks_plaintext() {
        let ctx = secure_ctx();
        let mut agg = TypingBatchAggregator::new(5_000);
        feed(&mut agg, "SecretPassword123", &ctx, 0);
        let r = agg.flush_pending(&ctx).expect("batch");
        assert_eq!(r.text_blob, "•".repeat("SecretPassword123".len()));
        assert!(!r.text_blob.contains("Secret"));
        let c = r.context.expect("context");
        assert!(c.is_secure);
        assert_eq!(c.value, None);
    }

    #[test]
    fn secure_field_unmasked_drops_entirely() {
        let ctx = secure_ctx();
        let mut agg = TypingBatchAggregator::new(5_000);
        agg.set_mask_secure(false);
        feed(&mut agg, "hunter2", &ctx, 0);
        assert!(!agg.has_pending_text());
        assert!(agg.flush_pending(&ctx).is_none());
    }

    #[test]
    fn secure_backspace_edits_masked_buffer() {
        let ctx = secure_ctx();
        let mut agg = TypingBatchAggregator::new(5_000);
        feed(&mut agg, "•••••", &ctx, 0);
        agg.backspace(Point2D::ZERO, 1);
        let r = agg.flush_pending(&ctx).expect("batch");
        assert_eq!(r.text_blob, "••••");
    }

    #[test]
    fn focus_change_cuts_before_next_char() {
        // Over-join killer: a bundle/window/role change forces the boundary.
        let plain = ctx("Safari");
        let secure = secure_ctx();
        let mut agg = TypingBatchAggregator::new(5_000);
        feed(&mut agg, "ab", &plain, 0);
        let cut = agg.append("c", Point2D::ZERO, &secure, 1);
        assert_eq!(cut.len(), 1, "focus change must cut");
        assert_eq!(cut[0].text_blob, "ab");
        let tail = agg.append("d", Point2D::ZERO, &secure, 1);
        assert!(tail.is_empty());
        let r = agg.flush_pending(&secure).expect("tail batch");
        // Secure tail is masked; the head never leaks into it.
        assert_eq!(r.text_blob, "••");
    }

    #[test]
    fn axunknown_popup_does_not_cut() {
        let mut a = notes();
        a.role = Some("AXTextField".to_string());
        let mut popup = notes();
        popup.role = Some("AXUnknown".to_string());
        let mut agg = TypingBatchAggregator::new(5_000);
        feed(&mut agg, "ab", &a, 0);
        let cut = agg.append("c", Point2D::ZERO, &popup, 1);
        assert!(cut.is_empty(), "AXUnknown popup must not cut");
        let r = agg.flush_pending(&popup).expect("batch");
        assert_eq!(r.text_blob, "abc");
    }

    #[test]
    fn hysteresis_holds_ambiguous_joins_below_low() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new_smart();
        feed(&mut agg, "hi", &ctx, 0);
        // 599 ms < T_LOW 600: JOIN, no cut even across append.
        let cut = agg.append("!", Point2D::ZERO, &ctx, 599);
        assert!(cut.is_empty());
        assert_eq!(agg.flush_pending(&ctx).expect("batch").text_blob, "hi!");
    }

    #[test]
    fn hysteresis_cuts_at_high() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new_smart();
        feed(&mut agg, "hi", &ctx, 0);
        // 1800 ms >= T_HIGH: CUT.
        let cut = agg.append("!", Point2D::ZERO, &ctx, 1800);
        assert_eq!(cut.len(), 1);
        assert_eq!(cut[0].text_blob, "hi");
    }

    #[test]
    fn hysteresis_ambiguous_holds_without_corroboration() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new_smart();
        feed(&mut agg, "hi", &ctx, 0);
        // 1000 ms sits in (600, 1800): HOLD for same-focus typing.
        assert!(agg.poll_timeout(1000).is_none());
        let cut = agg.append("!", Point2D::ZERO, &ctx, 1000);
        assert!(cut.is_empty());
    }

    #[test]
    fn per_app_thresholds_differ() {
        let agg = TypingBatchAggregator::new_smart();
        let term = ghostty();
        let (low, high) = agg.effective_thresholds(&term);
        assert_eq!((low, high), (900, 2500));
        let editor = notes();
        assert_eq!(agg.effective_thresholds(&editor), (600, 1800));
        let mut url = ctx("Safari");
        url.window_title = "https://example.com".to_string();
        url.placeholder = Some("Address".to_string());
        url.role = Some("AXTextField".to_string());
        assert_eq!(agg.effective_thresholds(&url), (400, 1200));
    }

    #[test]
    fn adaptive_personalizes_thresholds() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new_smart();
        // Slow typist: 1200 ms cadence stays joined (ambiguous HOLD for
        // same-focus typing), while the IKI history personalizes the bounds.
        for t in [0u64, 1200, 2400, 3600] {
            let cut = agg.append("x", Point2D::ZERO, &ctx, t);
            assert!(cut.is_empty());
        }
        let (low, high) = agg.effective_thresholds(&ctx);
        assert_eq!((low, high), (720, 1680));
    }

    #[test]
    fn return_smart_terminal_cuts_multiline_joins() {
        let term = ghostty();
        let mut agg = TypingBatchAggregator::new_smart();
        feed(&mut agg, "git status", &term, 0);
        let r = agg
            .handle_return_smart(Point2D::ZERO, &term, 10, false)
            .expect("terminal cuts");
        assert_eq!(r.text_blob, "git status");

        let mut multi = notes();
        multi.role = Some("AXTextArea".to_string());
        let mut agg = TypingBatchAggregator::new_smart();
        feed(&mut agg, "line1", &multi, 0);
        assert!(
            agg.handle_return_smart(Point2D::ZERO, &multi, 10, false)
                .is_none(),
            "multiline plain Return must JOIN"
        );
        feed(&mut agg, "line2", &multi, 20);
        let r = agg.flush_pending(&multi).expect("joined batch");
        assert_eq!(r.text_blob, "line1\nline2");

        // Cmd+Return always cuts, even in multiline fields.
        let mut agg = TypingBatchAggregator::new_smart();
        feed(&mut agg, "draft", &multi, 0);
        let r = agg
            .handle_return_smart(Point2D::ZERO, &multi, 10, true)
            .expect("Cmd+Return cuts");
        assert_eq!(r.text_blob, "draft");
    }

    #[test]
    fn paste_is_atomic_and_never_cut_inside() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new_smart();
        feed(&mut agg, "ab", &ctx, 0);
        // Burst-rate paste 5 ms later: boundary only if focus changed; the
        // payload itself never splits.
        let cut = agg.handle_paste("XYZ", Point2D::ZERO, &ctx, 5, Some(99));
        assert!(cut.is_empty());
        let r = agg.flush_pending(&ctx).expect("batch");
        assert_eq!(r.text_blob, "abXYZ");

        // Focus change forces the boundary BEFORE the paste.
        let other = ghostty();
        let mut agg = TypingBatchAggregator::new_smart();
        feed(&mut agg, "ab", &ctx, 0);
        let cut = agg.handle_paste("XYZ", Point2D::ZERO, &other, 5, Some(100));
        assert_eq!(cut.len(), 1);
        assert_eq!(cut[0].text_blob, "ab");
        let r = agg.flush_pending(&other).expect("paste batch");
        assert_eq!(r.text_blob, "XYZ");
    }

    #[test]
    fn burst_rate_chars_do_not_cut() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new_smart();
        feed(&mut agg, "a", &ctx, 0);
        // 10 ms later (>15 Hz): must JOIN, not cut.
        let cut = agg.append("b", Point2D::ZERO, &ctx, 10);
        assert!(cut.is_empty());
    }

    #[test]
    fn ime_suspends_gap_timer() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new_smart();
        feed(&mut agg, "hi", &ctx, 0);
        agg.set_composing(true);
        assert!(agg.poll_timeout(5000).is_none());
        let cut = agg.append("x", Point2D::ZERO, &ctx, 100);
        assert!(cut.is_empty(), "IME must suspend the gap timer");
        agg.set_composing(false);
        // IKI history is [0, 100]: p95 100 → high (8*1800+2*100)/10 = 1460.
        let cut = agg.poll_timeout(2000);
        assert!(cut.is_some());
    }

    #[test]
    fn backspace_word_undo_coalesces() {
        let ctx = notes();
        let mut agg = TypingBatchAggregator::new_smart();
        feed(&mut agg, "hello world", &ctx, 0);
        agg.backspace_word(Point2D::ZERO, 10);
        let r = agg.flush_pending(&ctx).expect("batch");
        assert_eq!(r.text_blob, "hello");
        // Trailing spaces are skipped, then one word is removed.
        let mut agg = TypingBatchAggregator::new_smart();
        feed(&mut agg, "hello world   ", &ctx, 0);
        agg.backspace_word(Point2D::ZERO, 10);
        let r = agg.flush_pending(&ctx).expect("batch");
        assert_eq!(r.text_blob, "hello");
    }

    #[test]
    fn secure_paste_masks_plaintext() {
        let sec = secure_ctx();
        let mut agg = TypingBatchAggregator::new_smart();
        let cut = agg.handle_paste("secret", Point2D::ZERO, &sec, 0, Some(7));
        assert!(cut.is_empty());
        let r = agg.flush_pending(&sec).expect("batch");
        assert_eq!(r.text_blob, "••••••");
        assert!(!r.text_blob.contains("secret"));
    }
}
