//! `TypingBatchAggregator` port (`Sources/StepItPipeline/TypingBatchAggregator.swift`).
//!
//! Synchronous state machine: the Swift `async` context provider and timer
//! task become explicit `ctx: &RawElementContext` arguments and injected
//! `now_millis: u64` timestamps. No clock, no RNG.
//!
//! Semantics mirrored verbatim:
//! - secure-field keystrokes never enter the buffer raw (bullets when masking
//!   is on, dropped when off);
//! - Return finalizes immediately; Control-C appends `^C` / ` ^C` and finalizes;
//! - flush drops whitespace-only buffers;
//! - inactivity past `debounce_interval_millis` cuts the batch on the next
//!   ingestion (or via [`TypingBatchAggregator::poll_timeout`]);
//! - finalization normalizes empty/`"Unknown App"` app names to `"Terminal"`,
//!   falls window title back to the app name, strips secure values, classifies,
//!   and centers on the window when it is larger than 50×50.

use crate::classify::{InputClassification, classify};
use stepit_ir::{Point2D, RawElementContext};

/// Apply the typing-batch context fallbacks (`TypingBatchAggregator.makeResult`):
/// unknown/empty app becomes `"Terminal"`, empty window title becomes the app
/// name, and secure values never ride along. Shared with `stepit_engine`
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
    buffer: String,
    last_location: Point2D,
    last_activity_millis: Option<u64>,
    pending_context: Option<RawElementContext>,
    mask_secure: bool,
}

impl TypingBatchAggregator {
    pub fn new(debounce_interval_millis: u64) -> Self {
        Self {
            debounce_interval_millis,
            buffer: String::new(),
            last_location: Point2D::ZERO,
            last_activity_millis: None,
            pending_context: None,
            mask_secure: true,
        }
    }

    pub fn set_mask_secure(&mut self, mask: bool) {
        self.mask_secure = mask;
    }

    pub fn has_pending_text(&self) -> bool {
        !self.buffer.trim().is_empty()
    }

    fn is_timed_out(&self, now_millis: u64) -> bool {
        match self.last_activity_millis {
            Some(last) => now_millis.saturating_sub(last) >= self.debounce_interval_millis,
            None => false,
        }
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

    /// Completed batches cut by a timeout boundary *before* this keystroke.
    /// Mirrors one `append(char:at:)` (context probed per keystroke).
    pub fn append(
        &mut self,
        ch: &str,
        location: Point2D,
        ctx: &RawElementContext,
        now_millis: u64,
    ) -> Vec<TypingBatchResult> {
        let mut done = Vec::new();
        if let Some(r) = self.take_timed_out(now_millis) {
            done.push(r);
        }
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

    pub fn backspace(&mut self, location: Point2D, now_millis: u64) -> Vec<TypingBatchResult> {
        let mut done = Vec::new();
        if let Some(r) = self.take_timed_out(now_millis) {
            done.push(r);
        }
        if !self.buffer.is_empty() {
            self.buffer.pop();
        }
        self.last_location = location;
        self.last_activity_millis = Some(now_millis);
        done
    }

    /// Enter / Return finalizes the command / line immediately.
    pub fn handle_return(
        &mut self,
        location: Point2D,
        ctx: &RawElementContext,
        now_millis: u64,
    ) -> Option<TypingBatchResult> {
        let _ = now_millis;
        self.last_activity_millis = None;
        self.pending_context = None;
        let text = std::mem::take(&mut self.buffer);
        if text.trim().is_empty() {
            return None;
        }
        Some(make_result(&text, location, ctx))
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

    use stepit_ir::ElementRect;

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
    fn focus_change_mid_batch_masks_tail() {
        let plain = ctx("Safari");
        let secure = secure_ctx();
        let mut agg = TypingBatchAggregator::new(5_000);
        feed(&mut agg, "ab", &plain, 0);
        feed(&mut agg, "cd", &secure, 1);
        let r = agg.flush_pending(&secure).expect("batch");
        assert_eq!(r.text_blob, "ab••");
    }
}
