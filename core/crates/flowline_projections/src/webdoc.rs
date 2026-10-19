//! Web-doc projection — port of `WebDocGenerator.swift`,
//! `WebDocSections.swift`, `WebDocMedia.swift`, `WebDocTheme.swift`,
//! `WebDocIcons.swift` (and the pure URL logic of `OpenInEditorCore.swift`).
//!
//! Pure string generation ONLY: `generate_html` renders the self-contained
//! single-file HTML guide from a [`StepSession`]. Theme CSS is embedded via
//! `include_str!` from `webdoc_theme.css` (ported verbatim from
//! `WebDocTheme.getThemeCSS`, which returns one static stylesheet for all
//! themes — per-theme values are selected at runtime through the
//! `data-theme` attribute).
//!
//! DIVERGENCES from Swift (pinned, documented):
//! - `Step` in `flowline_ir` has no `preferredMedia` yet, so the media
//!   default-view preference branch is omitted: the default view is `gif`
//!   when animated (and the session mode is not static-only), else
//!   `screenshot`, else `zoom`, else `webm`.
//! - Header `RECORDED` timestamp: Swift uses
//!   `session.startedAt.formatted(date:.abbreviated, time:.shortened)` in
//!   the ambient locale/timezone (non-deterministic). This port reuses the
//!   pinned IST rendering from [`crate::markdown::format_recorded`], exactly
//!   like the markdown projection.
//! - `<title>` carries the raw session title (unescaped), mirroring Swift
//!   (`<title>\(session.title) — step·it</title>`).
//! - Floats in `toggleInPlaceZoom(idx, x, y)` render Swift-style (`5.0`,
//!   not Rust's `5`) via [`swift_double`].

use flowline_ir::{ActionType, MediaMode, Step, StepSession, ThemeName};

use crate::key_visual::{self, KeycapStyle, MouseStyle};

// ---------------------------------------------------------------------------
// Escaping / prefixes (WebDocMedia)
// ---------------------------------------------------------------------------

/// Escape `& < > " '` for HTML text/attribute contexts.
///
/// Mirrors `WebDocGenerator.escapeHTML` (replacement order preserved).
pub fn escape_html(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

/// Escape a string for single-quoted JS string literals.
///
/// Mirrors `WebDocGenerator.escapeJS` (replacement order preserved:
/// backslash, single quote, LF → `\n`, drop CR).
pub fn escape_js(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('\'', "\\'")
        .replace('\n', "\\n")
        .replace('\r', "")
}

/// Asset-base-URL prefix for media `src` attributes (`""` → `""`,
/// `"media"` → `"media/"`). Mirrors `assetURLPrefix(assetBaseURL:)`.
pub fn asset_prefix(asset_base_url: &str) -> String {
    if asset_base_url.is_empty() {
        String::new()
    } else if asset_base_url.ends_with('/') {
        asset_base_url.to_string()
    } else {
        format!("{asset_base_url}/")
    }
}

/// Short action label for step chips. Mirrors `actionDisplayName(_:)`.
pub fn action_display_name(action: ActionType) -> &'static str {
    match action {
        ActionType::Click => "Click",
        ActionType::RightClick => "Right-Click",
        ActionType::DoubleClick => "Double-Click",
        ActionType::KeyPress => "Key Press",
        ActionType::Typing => "Typing",
        ActionType::WriteCode => "Code",
        ActionType::AppSwitch => "App Switch",
        ActionType::MouseDrag => "Drag",
        ActionType::Manual => "Action",
    }
}

/// Render an f64 Swift-style (`5.0` stays `"5.0"`, `62.5` stays `"62.5"`).
/// Rust `{}` would print `5` for `5.0`; the values feed
/// `toggleInPlaceZoom(idx, x, y)` where both spellings parse identically,
/// but byte-fidelity with Swift matters for parity tests.
fn swift_double(v: f64) -> String {
    if v.is_finite() && v.fract() == 0.0 {
        format!("{v:.1}")
    } else {
        format!("{v}")
    }
}

// ---------------------------------------------------------------------------
// Icons (WebDocIcons — Lucide/Feather stroke style, 24x24)
// ---------------------------------------------------------------------------

/// Inline SVG icon library. Single source — never paste ad-hoc SVG or emoji.
pub mod icons {
    /// Sun (theme button).
    pub const SUN: &str = "<svg width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><circle cx=\"12\" cy=\"12\" r=\"5\"></circle><line x1=\"12\" y1=\"1\" x2=\"12\" y2=\"3\"></line><line x1=\"12\" y1=\"21\" x2=\"12\" y2=\"23\"></line><line x1=\"4.22\" y1=\"4.22\" x2=\"5.64\" y2=\"5.64\"></line><line x1=\"18.36\" y1=\"18.36\" x2=\"19.78\" y2=\"19.78\"></line><line x1=\"1\" y1=\"12\" x2=\"3\" y2=\"12\"></line><line x1=\"21\" y1=\"12\" x2=\"23\" y2=\"12\"></line><line x1=\"4.22\" y1=\"19.78\" x2=\"5.64\" y2=\"18.36\"></line><line x1=\"18.36\" y1=\"5.64\" x2=\"19.78\" y2=\"4.22\"></line></svg>";
    /// Check (nav indicator, checklist box, footer badge).
    pub const CHECK: &str = "<svg width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\"><polyline points=\"20 6 9 17 4 12\"></polyline></svg>";
    /// Checklist (checklist toggle button).
    pub const CHECKLIST: &str = "<svg width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><polyline points=\"9 11 12 14 22 4\"></polyline><path d=\"M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11\"></path></svg>";
    /// Printer (print/PDF button).
    pub const PRINTER: &str = "<svg width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><polyline points=\"6 9 6 2 18 2 18 9\"></polyline><path d=\"M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2\"></path><rect x=\"6\" y=\"14\" width=\"12\" height=\"8\"></rect></svg>";
    /// Copy (copy buttons).
    pub const COPY: &str = "<svg width=\"11\" height=\"11\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><rect x=\"9\" y=\"9\" width=\"13\" height=\"13\" rx=\"2\" ry=\"2\"></rect><path d=\"M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1\"></path></svg>";
    /// Chevron down (dropdown carets).
    pub const CHEVRON_DOWN: &str = "<svg width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\"><polyline points=\"6 9 12 15 18 9\"></polyline></svg>";
    /// Share-2 trigger (canonical Lucide share icon).
    pub const SHARE2: &str = "<svg width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><circle cx=\"18\" cy=\"5\" r=\"3\"></circle><circle cx=\"6\" cy=\"12\" r=\"3\"></circle><circle cx=\"18\" cy=\"19\" r=\"3\"></circle><line x1=\"8.59\" x2=\"15.42\" y1=\"13.51\" y2=\"17.49\"></line><line x1=\"15.41\" x2=\"8.59\" y1=\"6.51\" y2=\"10.49\"></line></svg>";
    /// Zoom (magnifier for zoom badges).
    pub const ZOOM: &str = "<svg width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\"><circle cx=\"11\" cy=\"11\" r=\"8\"></circle><line x1=\"21\" y1=\"21\" x2=\"16.65\" y2=\"16.65\"></line><line x1=\"11\" y1=\"8\" x2=\"11\" y2=\"14\"></line><line x1=\"8\" y1=\"11\" x2=\"14\" y2=\"11\"></line></svg>";
}

// ---------------------------------------------------------------------------
// Theme CSS (WebDocTheme)
// ---------------------------------------------------------------------------

/// Full web-doc stylesheet, ported verbatim from
/// `WebDocTheme.getThemeCSS(for:)` (a single static stylesheet; per-theme
/// values switch at runtime via the `data-theme` attribute).
pub fn theme_css() -> &'static str {
    include_str!("webdoc_theme.css")
}

// ---------------------------------------------------------------------------
// Settings (PublishingSettings subset used by the web exporter)
// ---------------------------------------------------------------------------

/// Documentation output configuration for the web exporter.
///
/// Mirrors `PublishingSettings` field-for-field (including serde camelCase
/// keys and init defaults) so JSON round-trips stay compatible.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WebPublishSettings {
    /// Default theme (the session's own theme wins in `generate_html`).
    #[serde(default = "default_theme")]
    pub default_theme: ThemeName,
    /// Author name shown in the metadata strip.
    #[serde(default)]
    pub author_name: String,
    /// Company name fallback when `author_name` is empty.
    #[serde(default = "default_company")]
    pub company_name: String,
    /// Whether steps render interactive checklist checkboxes.
    #[serde(default = "default_true")]
    pub enable_interactive_checklists: bool,
    /// PDF paper size (carried for JSON compatibility; unused by HTML).
    #[serde(default = "default_paper")]
    pub pdf_paper_size: String,
    /// Whether the metadata strip shows the RECORDED item.
    #[serde(default = "default_true")]
    pub include_timestamp: bool,
    /// Keystroke visual style.
    #[serde(default)]
    pub keycap_style: KeycapStyle,
    /// Mouse-pointer visual style.
    #[serde(default)]
    pub mouse_style: MouseStyle,
}

fn default_theme() -> ThemeName {
    ThemeName::ModernMinimal
}

fn default_company() -> String {
    "Flowline Docs".to_string()
}

fn default_true() -> bool {
    true
}

fn default_paper() -> String {
    "A4".to_string()
}

impl Default for WebPublishSettings {
    /// Mirrors `PublishingSettings.init` defaults.
    fn default() -> Self {
        Self {
            default_theme: ThemeName::ModernMinimal,
            author_name: String::new(),
            company_name: "Flowline Docs".to_string(),
            enable_interactive_checklists: true,
            pdf_paper_size: "A4".to_string(),
            include_timestamp: true,
            keycap_style: KeycapStyle::Mac3D,
            mouse_style: MouseStyle::Mac3D,
        }
    }
}

/// `data-theme` attribute value. Mirrors Swift `ThemeName.rawValue`
/// (`"modern-minimal"` / `"developer-dark"` / `"enterprise-sop"`).
pub fn theme_attr(theme: ThemeName) -> &'static str {
    match theme {
        ThemeName::ModernMinimal => "modern-minimal",
        ThemeName::DeveloperDark => "developer-dark",
        ThemeName::EnterpriseSop => "enterprise-sop",
    }
}

// ---------------------------------------------------------------------------
// Sections (WebDocSections)
// ---------------------------------------------------------------------------

/// Sidebar step navigation. Mirrors `generateSidebarNav(session:)`.
pub fn generate_sidebar_nav(session: &StepSession) -> String {
    let mut html = String::new();
    for step in &session.steps {
        let label = escape_html(&step.action_description);
        let num = format!("{:02}", step.index);
        let tag = if step.app_name.is_empty() {
            String::new()
        } else {
            format!(
                "<span class=\"nav-tag\">{}</span>",
                escape_html(&step.app_name)
            )
        };
        html.push_str(&format!(
            r###"<a href="#step-card-{i}" class="nav-link" id="nav-item-{i}">
                <span class="nav-indicator">
                    <span class="nav-num">{num}</span>
                    {check}
                </span>
                <span class="nav-body">
                    <span class="nav-label">{label}</span>
                    {tag}
                </span>
            </a>
"###,
            i = step.index,
            check = icons::CHECK
        ));
    }
    html
}

/// Hero metadata strip (author / recorded / steps / format).
/// Mirrors `generateHeaderMetadata(session:settings:)`.
pub fn generate_header_metadata(
    session: &StepSession,
    settings: &WebPublishSettings,
) -> String {
    let author = if settings.author_name.is_empty() {
        if settings.company_name.is_empty() {
            "macOS User".to_string()
        } else {
            settings.company_name.clone()
        }
    } else {
        settings.author_name.clone()
    };
    let mut html = String::from(
        "        <div class=\"metadata-strip\">\n            <div class=\"meta-strip-item\">\n                <span class=\"meta-strip-label\">AUTHOR</span>\n",
    );
    html.push_str(&format!(
        "                <span class=\"meta-strip-val\">{}</span>\n            </div>\n",
        escape_html(&author)
    ));
    if settings.include_timestamp {
        let recorded = crate::markdown::format_recorded(&session.started_at);
        html.push_str(&format!(
            "            <div class=\"meta-strip-item\">\n                <span class=\"meta-strip-label\">RECORDED</span>\n                <span class=\"meta-strip-val\">{recorded}</span>\n            </div>\n"
        ));
    }
    html.push_str(&format!(
        "            <div class=\"meta-strip-item\">\n                <span class=\"meta-strip-label\">STEPS</span>\n                <span class=\"meta-strip-val\">{} verified</span>\n            </div>\n            <div class=\"meta-strip-item\">\n                <span class=\"meta-strip-label\">FORMAT</span>\n                <span class=\"meta-strip-val\">{}</span>\n            </div>\n        </div>\n",
        session.steps.len(),
        session.media_mode.display_name()
    ));
    html
}

/// Step cards stream. Mirrors `generateStepsHTML(session:assetBaseURL:settings:)`.
pub fn generate_steps_html(
    session: &StepSession,
    asset_base_url: &str,
    settings: Option<&WebPublishSettings>,
) -> String {
    let prefix = asset_prefix(asset_base_url);
    let mut html = String::new();
    for step in &session.steps {
        push_step_card(&mut html, session, step, &prefix, settings);
    }
    html
}

#[allow(clippy::too_many_arguments)]
fn push_step_card(
    html: &mut String,
    session: &StepSession,
    step: &Step,
    prefix: &str,
    settings: Option<&WebPublishSettings>,
) {
    let has_screenshot = step.assets.screenshot.is_some();
    let has_gif = step.assets.gif.is_some();
    let has_webm = step.assets.webm.is_some();
    let has_zoom = step.assets.zoom_crop.is_some();
    let has_media = has_screenshot || has_gif || has_webm || has_zoom;

    // No `preferredMedia` in the Rust IR yet: gif wins when animated and
    // the session is not static-only, else screenshot, else zoom, else webm.
    let default_view: &str = if has_gif && session.media_mode != MediaMode::StaticOnly {
        "gif"
    } else if has_screenshot {
        "screenshot"
    } else if has_zoom {
        "zoom"
    } else {
        "webm"
    };
    let action_name = action_display_name(step.action);
    let win_title = if step.window_title.is_empty() {
        if step.app_name.is_empty() {
            "Application Window".to_string()
        } else {
            step.app_name.clone()
        }
    } else {
        step.window_title.clone()
    };
    let formatted_index = format!("{:02}", step.index);

    let coords_x = step.coordinates.map(|c| c.x).unwrap_or(600.0);
    let coords_y = step.coordinates.map(|c| c.y).unwrap_or(400.0);
    let pct_x = (coords_x / 1200.0 * 100.0).clamp(5.0, 95.0);
    let pct_y = (coords_y / 800.0 * 100.0).clamp(5.0, 95.0);
    let is_terminal_cmd = (step.app_name == "Terminal"
        || step.code_language.as_deref() == Some("bash")
        || step.code_language.as_deref() == Some("zsh"))
        && step.text_blob.is_some();
    let key_style = settings.map(|s| s.keycap_style).unwrap_or(KeycapStyle::Mac3D);
    let pointer_style = settings.map(|s| s.mouse_style).unwrap_or(MouseStyle::Mac3D);

    // Keycap row for key-press / short-typed-text steps.
    let mut keycaps_row = String::new();
    if step.action == ActionType::KeyPress {
        let toks =
            key_visual::tokens_for_step(step.hotkey_combo.as_deref(), step.element_title.as_deref());
        if !toks.is_empty() {
            let caps = key_visual::web_caps_html(&toks, key_style);
            let label = if step.hotkey_combo.as_deref().is_some_and(|c| !c.is_empty()) {
                "Shortcut"
            } else {
                "Key"
            };
            keycaps_row.push_str(&format!(
                "                        <div class=\"keycombo-row\">\n                            <span class=\"keycombo-label\">{label}</span>\n                            <span class=\"keycombo\">{caps}</span>\n                        </div>\n"
            ));
        }
    } else if step.action == ActionType::Typing {
        if let Some(blob) = step.text_blob.as_deref() {
            if let Some(toks) = key_visual::typed_tokens(blob, 12) {
                let caps = key_visual::web_caps_html(&toks, key_style);
                keycaps_row.push_str(&format!(
                    "                        <div class=\"keycombo-row\">\n                            <span class=\"keycombo-label\">Typed</span>\n                            <span class=\"keycombo\">{caps}</span>\n                        </div>\n"
                ));
            }
        }
    }

    // Mouse row for pointer steps.
    let mut mouse_row = String::new();
    if step.action != ActionType::KeyPress && step.action != ActionType::Typing {
        if let Some(label) = key_visual::mouse_label(step.action.raw_value()) {
            mouse_row.push_str(&format!(
                "                        <div class=\"mouse-row {}\">\n                            <span class=\"mouse-ptr\" aria-hidden=\"true\"><svg width=\"11\" height=\"11\" viewBox=\"0 0 24 24\" fill=\"currentColor\" aria-hidden=\"true\"><path d=\"M6 3.5 6 16.6 10.2 13.4 12.3 17.8 14.4 16.9 12.3 12.5 16.4 12.5 Z\"/></svg></span>\n                            <span class=\"mouse-label\">{label}</span>\n                        </div>\n",
                pointer_style.css_class()
            ));
        }
    }

    let checklists_enabled = settings.map(|s| s.enable_interactive_checklists).unwrap_or(true);
    let checklist_html = if checklists_enabled {
        format!(
            "<label class=\"step-check-label\" title=\"Mark step {} completed\"><input type=\"checkbox\" class=\"step-check\" data-step=\"{0}\"><span class=\"custom-checkbox\">{}</span></label>",
            step.index,
            icons::CHECK
        )
    } else {
        String::new()
    };
    let card_class = if checklists_enabled {
        "step-card"
    } else {
        "step-card no-checklist"
    };

    html.push_str(&format!("<article class=\"{card_class}\" id=\"step-card-{i}\">", i = step.index));
    html.push_str("<div class=\"step-header\"><div class=\"step-header-left\">");
    html.push_str(&checklist_html);
    html.push_str("<div class=\"step-header-text\"><div class=\"step-top-meta\">");
    html.push_str(&format!("<span class=\"step-num-tag\">STEP {formatted_index}</span>"));
    html.push_str(&format!("<span class=\"chip action-chip\">{action_name}</span>"));
    if !step.app_name.is_empty() {
        html.push_str(&format!(
            "<span class=\"chip app-chip\">{}</span>",
            escape_html(&step.app_name)
        ));
    }
    html.push_str("</div>");
    html.push_str(&format!(
        "<h2 class=\"step-title\">{}</h2>",
        escape_html(&step.action_description)
    ));
    html.push_str("</div></div></div>");

    // Step Inspector Data Bar.
    html.push_str("\n                <!-- Step Inspector Data Bar -->\n                <div class=\"step-details\">\n                    <div class=\"step-info-bar\">\n");
    if !step.window_title.is_empty() {
        html.push_str(&format!(
            "                        <div class=\"info-pill\">\n                            <span class=\"info-pill-label\">Window</span>\n                            <span class=\"info-pill-val\" title=\"{t}\">{t}</span>\n                        </div>\n",
            t = escape_html(&step.window_title)
        ));
    }
    if let Some(target) = step.element_title.as_deref() {
        html.push_str(&format!(
            "                        <div class=\"info-pill highlight-pill\">\n                            <span class=\"info-pill-label\">Target</span>\n                            <code class=\"info-pill-code\">{t}</code>\n                            <button class=\"copy-micro-btn\" onclick=\"copyText('{j}', this)\" title=\"Copy Target Element\">\n                                {copy}\n                                <span>Copy</span>\n                            </button>\n                        </div>\n",
            t = escape_html(target),
            j = escape_js(target),
            copy = icons::COPY
        ));
    }
    if step.coordinates.is_some() {
        html.push_str(&format!(
            "                        <div class=\"info-pill\">\n                            <span class=\"info-pill-label\">Coordinates</span>\n                            <code class=\"info-pill-code\">({}, {})</code>\n                        </div>\n",
            coords_x as i64,
            coords_y as i64
        ));
    }
    html.push_str("                    </div>\n");
    html.push_str(&keycaps_row);
    html.push_str(&mouse_row);

    // User-note callout.
    if let Some(notes) = step.user_notes.as_deref() {
        if !notes.is_empty() {
            html.push_str(&format!(
                "\n                    <!-- Apple Style User Note Callout -->\n                    <div class=\"step-callout note-callout\">\n                        <div class=\"callout-body\">\n                            <div class=\"callout-title\">Note</div>\n                            <div class=\"callout-text\">{}</div>\n                        </div>\n                    </div>\n",
                escape_html(notes)
            ));
        }
    }

    // Terminal / code-snippet card.
    if let Some(blob) = step.text_blob.as_deref() {
        if !blob.is_empty() {
            let frame_class = if is_terminal_cmd {
                "code-window-frame terminal-window-frame"
            } else {
                "code-window-frame"
            };
            html.push_str("\n                    <!-- macOS Terminal / Code Snippet Card -->\n");
            html.push_str(&format!(
                "                    <div class=\"{frame_class} code-blob-container\">\n                        <div class=\"code-window-titlebar terminal-titlebar code-blob-header\">\n                            <div class=\"traffic-lights\">\n                                <span class=\"traffic-dot close\"></span>\n                                <span class=\"traffic-dot minimize\"></span>\n                                <span class=\"traffic-dot maximize\"></span>\n                            </div>\n"
            ));
            if is_terminal_cmd {
                html.push_str("                            <div class=\"code-window-title terminal-shell-badge code-blob-meta\">\n                                <span class=\"terminal-shell-badge\">zsh — 80×24</span><span class=\"code-lang-tag\">CLI Command</span>\n                            </div>\n");
            } else {
                let label = if step.is_code { "Code Snippet" } else { "Captured Text" };
                html.push_str(&format!(
                    "                            <div class=\"code-window-title code-blob-meta\">\n                                <span class=\"code-label\">{label}</span>"
                ));
                if let Some(lang) = step.code_language.as_deref() {
                    html.push_str(&format!(
                        "<span class=\"code-lang-tag\">{}</span>",
                        escape_html(lang)
                    ));
                }
                html.push_str("\n                            </div>\n");
            }
            let btn_class = if is_terminal_cmd {
                "copy-code-btn copy-cmd-btn"
            } else {
                "copy-code-btn"
            };
            let btn_label = if is_terminal_cmd { "Copy Command" } else { "Copy" };
            html.push_str(&format!(
                "                            <button class=\"{btn_class}\" onclick=\"copyText('{j}', this)\">\n                                {copy}\n                                <span>{btn_label}</span>\n                            </button>\n                        </div>\n",
                j = escape_js(blob),
                copy = icons::COPY
            ));
            if is_terminal_cmd {
                html.push_str(&format!(
                    "                        <div class=\"code-window-body terminal-body\">\n                            <div class=\"terminal-line\"><span class=\"terminal-prompt\">$ </span><span class=\"terminal-cmd\">{}</span></div>\n                        </div>\n",
                    escape_html(blob)
                ));
            } else {
                html.push_str(&format!(
                    "                        <pre class=\"code-window-body code-blob-body\"><code>{}</code></pre>\n",
                    escape_html(blob)
                ));
            }
            html.push_str("                    </div>\n");
        }
    }
    html.push_str("                </div>\n");

    // macOS framed visual media viewport.
    if has_media {
        html.push_str("\n                <!-- macOS Framed Visual Media Viewport -->\n                <div class=\"macos-window-frame\">\n                    <div class=\"macos-titlebar\">\n                        <div class=\"traffic-lights\">\n                            <span class=\"traffic-dot close\"></span>\n                            <span class=\"traffic-dot minimize\"></span>\n                            <span class=\"traffic-dot maximize\"></span>\n                        </div>\n");
        html.push_str(&format!(
            "                        <div class=\"macos-window-title\" title=\"{t}\">\n                            <span>{t}</span>\n                        </div>\n",
            t = escape_html(&win_title)
        ));
        html.push_str("                        \n                        <!-- Apple Segmented Media & Clean Zoom Selector — text-only, no emoji -->\n                        <div class=\"apple-segmented-picker\">\n");
        if has_screenshot {
            let active = if default_view == "screenshot" { " active" } else { "" };
            html.push_str(&format!(
                "                            <button class=\"segment-btn{active}\" data-mode=\"screenshot\" onclick=\"switchMediaView({i}, 'screenshot')\">Overview</button>\n",
                i = step.index
            ));
        }
        if has_zoom {
            let active = if default_view == "zoom" { " active" } else { "" };
            html.push_str(&format!(
                "                            <button class=\"segment-btn{active}\" data-mode=\"zoom\" onclick=\"switchMediaView({i}, 'zoom')\">Zoom (2.4×)</button>\n",
                i = step.index
            ));
        }
        if has_gif {
            let active = if default_view == "gif" { " active" } else { "" };
            html.push_str(&format!(
                "                            <button class=\"segment-btn{active}\" data-mode=\"gif\" onclick=\"switchMediaView({i}, 'gif')\">Animation</button>\n",
                i = step.index
            ));
        }
        if has_webm {
            html.push_str(&format!(
                "                            <button class=\"segment-btn\" data-mode=\"webm\" onclick=\"switchMediaView({i}, 'webm')\">Video</button>\n",
                i = step.index
            ));
        }
        if let Some(shot) = step.assets.screenshot.as_deref() {
            html.push_str(&format!(
                "                            <button class=\"segment-btn lightbox-trigger-btn\" onclick=\"openLightbox('{prefix}{shot}', '{}', {}, {})\" title=\"Open Fullscreen Retina Zoom Lightbox\"><span>Lightbox</span></button>\n",
                escape_js(&step.action_description),
                coords_x as i64,
                coords_y as i64
            ));
        }
        let _ = has_screenshot;
        html.push_str("                        </div>\n                    </div>\n\n                    <div class=\"macos-window-canvas\">\n");
        if let Some(shot) = step.assets.screenshot.as_deref() {
            let hidden = if default_view == "screenshot" { "" } else { " hidden" };
            html.push_str(&format!(
                "                        <div class=\"media-view media-view-screenshot{hidden}\">\n                            <div class=\"media-wrapper zoomable-wrapper\" id=\"zoom-wrapper-{i}\" onclick=\"toggleInPlaceZoom({i}, {px}, {py})\" title=\"Click to toggle clean zoom at target coordinates\">\n                                <img src=\"{prefix}{shot}\" alt=\"{alt}\" loading=\"lazy\" id=\"zoom-img-{i}\" class=\"zoom-target-img\">\n                                <div class=\"zoom-indicator-pill\">\n                                    {zoom}\n                                    <span>Click to Zoom</span>\n                                </div>\n                            </div>\n                        </div>\n",
                i = step.index,
                px = swift_double(pct_x),
                py = swift_double(pct_y),
                alt = escape_html(&step.action_description),
                zoom = icons::ZOOM
            ));
        }
        if let Some(zc) = step.assets.zoom_crop.as_deref() {
            let hidden = if default_view == "zoom" { "" } else { " hidden" };
            html.push_str(&format!(
                "                        <div class=\"media-view media-view-zoom{hidden}\">\n                            <div class=\"media-wrapper zoom-crop-wrapper\">\n                                <img src=\"{prefix}{zc}\" alt=\"2.4x Zoom of {alt}\" loading=\"lazy\">\n                                <div class=\"zoom-crop-badge\">\n                                    {zoom}\n                                    <span>2.4× Focused Live DOM Crop</span>\n                                </div>\n                            </div>\n                        </div>\n",
                alt = escape_html(&step.action_description),
                zoom = icons::ZOOM
            ));
        }
        if let Some(gif) = step.assets.gif.as_deref() {
            let hidden = if default_view == "gif" { "" } else { " hidden" };
            html.push_str(&format!(
                "                        <div class=\"media-view media-view-gif{hidden}\">\n                            <div class=\"media-wrapper\">\n                                <img src=\"{prefix}{gif}\" alt=\"Animated {alt}\" loading=\"lazy\">\n                            </div>\n                        </div>\n",
                alt = escape_html(&step.action_description)
            ));
        }
        if let Some(webm) = step.assets.webm.as_deref() {
            html.push_str(&format!(
                "                        <div class=\"media-view media-view-webm hidden\">\n                            <div class=\"media-wrapper\">\n                                <video src=\"{prefix}{webm}\" autoplay loop muted playsinline controls></video>\n                            </div>\n                        </div>\n"
            ));
        }
        html.push_str("                    </div>\n                </div>\n");
    }
    html.push_str("            </article>\n");
}

// ---------------------------------------------------------------------------
// Document (WebDocGenerator)
// ---------------------------------------------------------------------------

/// Generate the self-contained single-file HTML guide with default settings
/// and no asset-base URL (mirrors `exportWeb`: `assetBaseURL: ""`).
pub fn generate_html(session: &StepSession) -> String {
    generate_html_with_settings(session, &WebPublishSettings::default(), "")
}

/// Full generation entry point.
/// Mirrors `WebDocGenerator.generateHTML(session:settings:assetBaseURL:)`.
pub fn generate_html_with_settings(
    session: &StepSession,
    settings: &WebPublishSettings,
    asset_base_url: &str,
) -> String {
    let css = theme_css();
    let steps_html = generate_steps_html(session, asset_base_url, Some(settings));
    let sidebar_nav = generate_sidebar_nav(session);
    let header_metadata = generate_header_metadata(session, settings);

    let mut html = String::with_capacity(css.len() + steps_html.len() + 65_536);
    // Head.
    html.push_str("<!DOCTYPE html>\n<html lang=\"en\" data-theme=\"");
    html.push_str(theme_attr(session.theme));
    html.push_str("\" data-keycap=\"");
    html.push_str(settings.keycap_style.html_value());
    html.push_str("\" data-mouse=\"");
    html.push_str(settings.mouse_style.html_value());
    html.push_str(
        "\">\n<head>\n    <meta charset=\"UTF-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n    <title>",
    );
    html.push_str(&session.title);
    html.push_str(
        " — step·it</title>\n    <meta name=\"description\" content=\"Step-by-step verified workflow guide generated by step·it for macOS.\">\n    <link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">\n    <link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin>\n    <link href=\"https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap\" rel=\"stylesheet\">\n    <style>\n",
    );
    html.push_str(css);
    html.push_str("\n    </style>\n</head>\n<body>\n");

    // Progress bar + sticky header.
    html.push_str(
        "    <!-- Top Hairline Progress Bar -->\n    <div id=\"progress-bar-container\">\n        <div id=\"progress-bar\"></div>\n    </div>\n\n    <!-- Apple / Airbnb Minimalist Sticky Header -->\n    <header class=\"site-header\">\n        <div class=\"header-left\">\n            <a href=\"#top\" class=\"brand-lockup\" title=\"step·it for macOS\">\n                <svg class=\"brand-logo-svg\" viewBox=\"0 0 110 28\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">\n                    <rect x=\"0\" y=\"14\" width=\"5.5\" height=\"14\" rx=\"2.5\" fill=\"currentColor\" opacity=\"0.35\"/>\n                    <rect x=\"8\" y=\"7\" width=\"5.5\" height=\"21\" rx=\"2.5\" fill=\"currentColor\" opacity=\"0.7\"/>\n                    <rect x=\"16\" y=\"0\" width=\"5.5\" height=\"28\" rx=\"2.5\" fill=\"currentColor\"/>\n                    <circle cx=\"27\" cy=\"5\" r=\"2.5\" fill=\"#0071e3\"/>\n                    <text x=\"36\" y=\"20\" font-family=\"-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Circular', 'Inter', sans-serif\" font-size=\"19\" font-weight=\"800\" letter-spacing=\"-0.04em\" fill=\"currentColor\">step<tspan fill=\"#0071e3\">·</tspan>it</text>\n                </svg>\n            </a>\n            <span class=\"header-crumb-sep\">/</span>\n",
    );
    html.push_str(&format!(
        "            <span class=\"header-title\" title=\"{t}\">{t}</span>\n        </div>\n",
        t = escape_html(&session.title)
    ));
    html.push_str(&format!(
        "\n        <div class=\"header-center\">\n            <div class=\"header-progress-pill\">\n                <div class=\"mini-progress-track\">\n                    <div id=\"mini-progress-bar\"></div>\n                </div>\n                <span id=\"step-completion-badge-header\" class=\"header-progress-text\">0 of {n} completed</span>\n            </div>\n        </div>\n",
        n = session.steps.len()
    ));

    // Theme selector.
    let active_min = if session.theme == ThemeName::ModernMinimal { " active" } else { "" };
    let active_dark = if session.theme == ThemeName::DeveloperDark { " active" } else { "" };
    let active_sop = if session.theme == ThemeName::EnterpriseSop { " active" } else { "" };
    html.push_str(&format!(
        "\n        <div class=\"header-actions\">\n            <!-- Theme Selector Dropdown -->\n            <div class=\"theme-selector-container\">\n                <button id=\"theme-selector-btn\" class=\"action-btn theme-btn\" title=\"Switch Theme (T)\" aria-haspopup=\"true\" aria-expanded=\"false\">\n                    {sun}\n                    <span id=\"theme-btn-label\" class=\"btn-text\">{label}</span>\n                    {caret}\n                </button>\n                <div id=\"theme-dropdown-menu\" class=\"theme-menu-popover hidden\">\n                    <button class=\"theme-option{active_min}\" data-theme-val=\"modern-minimal\">\n                        <span class=\"theme-color-dot minimal-dot\"></span>\n                        <span class=\"theme-opt-name\">Modern Minimalist</span>\n                    </button>\n                    <button class=\"theme-option{active_dark}\" data-theme-val=\"developer-dark\">\n                        <span class=\"theme-color-dot dark-dot\"></span>\n                        <span class=\"theme-opt-name\">Developer Dark</span>\n                    </button>\n                    <button class=\"theme-option{active_sop}\" data-theme-val=\"enterprise-sop\">\n                        <span class=\"theme-color-dot sop-dot\"></span>\n                        <span class=\"theme-opt-name\">Enterprise SOP</span>\n                    </button>\n                </div>\n            </div>\n",
        sun = icons::SUN,
        caret = icons::CHEVRON_DOWN,
        label = session.theme.display_name()
    ));

    // Checklist toggle, share menu, print button (static chrome).
    html.push_str(&format!(
        "\n            <!-- Checklist Mode Toggle -->\n            <button id=\"toggle-checklist-btn\" class=\"action-btn\" title=\"Toggle Checklist Mode (C)\">\n                {checklist}\n                <span class=\"btn-text\">Checklist</span>\n            </button>\n",
        checklist = icons::CHECKLIST
    ));
    html.push_str(SHARE_MENU_HTML);
    html.push_str(&format!(
        "\n            <!-- Print / PDF Button -->\n            <button onclick=\"window.print()\" class=\"action-btn primary-action\" title=\"Print or Save as PDF (⌘P)\">\n                {printer}\n                <span class=\"btn-text\">Print PDF</span>\n            </button>\n        </div>\n    </header>\n",
        printer = icons::PRINTER
    ));

    // Print header, layout, sidebar, hero.
    html.push_str(
        "\n    <!-- Dedicated Print Header (Print Only) -->\n    <div class=\"print-header\">\n        <svg class=\"brand-logo-svg print-logo\" viewBox=\"0 0 110 28\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">\n            <rect x=\"0\" y=\"14\" width=\"5.5\" height=\"14\" rx=\"2.5\" fill=\"#1d1d1f\" opacity=\"0.35\"/>\n            <rect x=\"8\" y=\"7\" width=\"5.5\" height=\"21\" rx=\"2.5\" fill=\"#1d1d1f\" opacity=\"0.7\"/>\n            <rect x=\"16\" y=\"0\" width=\"5.5\" height=\"28\" rx=\"2.5\" fill=\"#1d1d1f\"/>\n            <circle cx=\"27\" cy=\"5\" r=\"2.5\" fill=\"#0071e3\"/>\n            <text x=\"36\" y=\"20\" font-family=\"-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif\" font-size=\"19\" font-weight=\"800\" letter-spacing=\"-0.04em\" fill=\"#1d1d1f\">step<tspan fill=\"#0071e3\">·</tspan>it</text>\n        </svg>\n        <div class=\"print-meta-right\">\n            <span>Verified Workflow Documentation</span>\n        </div>\n    </div>\n\n    <div class=\"layout-container\" id=\"top\">\n        <!-- Minimalist Left Navigation Rail -->\n        <aside class=\"sidebar-nav\">\n            <div class=\"sidebar-header\">\n                <span class=\"sidebar-title\">WORKFLOW STEPS</span>\n",
    );
    html.push_str(&format!(
        "                <span id=\"step-completion-badge\" class=\"step-count-pill\">0 / {n}</span>\n            </div>\n            <nav class=\"steps-menu\">\n{sidebar_nav}            </nav>\n            <div class=\"sidebar-footer\">\n                <div class=\"sidebar-shortcut-hint\">\n                    <kbd>J</kbd> <kbd>K</kbd> to jump · <kbd>T</kbd> theme\n                </div>\n                <div class=\"sidebar-brand-note\">\n                    Documented with <strong>step·it</strong>\n                </div>\n            </div>\n        </aside>\n",
        n = session.steps.len()
    ));
    html.push_str(
        "\n        <!-- Main Guide Content Area -->\n        <main class=\"main-content\">\n            <!-- Minimalist Editorial Hero Section -->\n            <section class=\"doc-hero\">\n                <div class=\"hero-top-row\">\n                    <div class=\"hero-badge\">\n                        <span class=\"badge-dot\"></span>\n                        <span>Verified Workflow</span>\n                    </div>\n",
    );
    html.push_str(&format!(
        "                    <span class=\"hero-subline\">• {n} steps total</span>\n                </div>\n",
        n = session.steps.len()
    ));
    html.push_str(&format!(
        "                <h1 class=\"hero-title\">{}</h1>\n",
        escape_html(&session.title)
    ));
    if let Some(summary) = session.summary.as_deref() {
        if !summary.is_empty() {
            html.push_str(&format!(
                "                <p class=\"doc-summary\">{}</p>\n",
                escape_html(summary)
            ));
        }
    }
    html.push_str(&header_metadata);
    html.push_str(
        "            </section>\n\n            <!-- Steps Stream -->\n            <section class=\"steps-flow\">\n",
    );
    html.push_str(&steps_html);
    html.push_str("            </section>\n");

    // Closure card.
    html.push_str(&format!(
        "\n            <!-- Apple / Airbnb Minimalist Closure Card -->\n            <footer class=\"doc-footer\">\n                <div class=\"footer-card\">\n                    <div class=\"footer-badge-icon\">\n                        <svg width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\"><polyline points=\"20 6 9 17 4 12\"></polyline></svg>\n                    </div>\n                    <h3 class=\"footer-title\">Workflow Complete</h3>\n                    <p class=\"footer-desc\">All {n} steps have been reviewed and verified in this guide.</p>\n                    <div class=\"footer-actions\">\n                        <button class=\"primary-btn\" onclick=\"window.scrollTo({{top: 0, behavior: 'smooth'}})\">\n                            <span>Back to Top</span>\n                            <svg width=\"13\" height=\"13\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\"><polyline points=\"18 15 12 9 6 15\"></polyline></svg>\n                        </button>\n                    </div>\n                </div>\n            </footer>\n        </main>\n    </div>\n",
        n = session.steps.len()
    ));

    // Interactive script (static JS with the session id spliced in, mirroring
    // Swift's single interpolation `const sessionId = "\(session.id)";`).
    html.push_str("\n    <!-- Interactive Logic (Persistence, Segment Switcher, Keyboard Nav) -->\n    <script>\n");
    html.push_str(INTERACTIVE_JS_BEFORE_ID);
    html.push_str(&session.id);
    html.push_str(INTERACTIVE_JS_AFTER_ID);
    html.push_str("\n    </script>\n");

    // Lightbox modal.
    html.push_str(
        "\n    <!-- Fullscreen Interactive Zoom Lightbox Modal -->\n    <div id=\"lightbox-modal\" class=\"lightbox-modal hidden\" onclick=\"if(event.target === this) closeLightbox()\">\n        <div class=\"lightbox-dialog\">\n            <div class=\"lightbox-header\">\n                <span id=\"lightbox-title\" class=\"lightbox-title\">Workflow Step Inspection</span>\n                <div class=\"lightbox-actions\">\n                    <div class=\"lightbox-zoom-bar\">\n                        <button class=\"lightbox-btn\" onclick=\"adjustLightboxZoom(-0.3)\">−</button>\n                        <span id=\"lightbox-zoom-level\">100%</span>\n                        <button class=\"lightbox-btn\" onclick=\"adjustLightboxZoom(0.3)\">+</button>\n                        <button class=\"lightbox-btn reset-btn\" onclick=\"resetLightboxZoom()\">Reset</button>\n                    </div>\n                    <button class=\"lightbox-close-btn\" onclick=\"closeLightbox()\" title=\"Close (Esc)\" aria-label=\"Close\"><svg width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\"><line x1=\"18\" y1=\"6\" x2=\"6\" y2=\"18\"></line><line x1=\"6\" y1=\"6\" x2=\"18\" y2=\"18\"></line></svg></button>\n                </div>\n            </div>\n            <div class=\"lightbox-canvas\" id=\"lightbox-canvas\">\n                <img id=\"lightbox-img\" src=\"\" alt=\"Fullscreen Inspection\">\n            </div>\n            <div class=\"lightbox-footer\">\n                <span id=\"lightbox-coords-tag\" class=\"lightbox-tag\"></span>\n                <span class=\"lightbox-hint\">Tip: Click + / − to zoom &bull; Click and drag to pan &bull; Press Esc to close</span>\n            </div>\n        </div>\n    </div>\n</body>\n</html>\n",
    );
    html
}

// ---------------------------------------------------------------------------
// Static header chrome: share dropdown (official brand rows, whole-row click)
// ---------------------------------------------------------------------------

/// Share-dropdown popover. Fully static in Swift; ported verbatim.
const SHARE_MENU_HTML: &str = r###"
            <!-- Share Dropdown (copyable link rows, whole-row click-to-copy) -->
            <div class="share-selector-container">
                <button id="share-selector-btn" class="action-btn share-btn" title="Share this guide" aria-haspopup="menu" aria-expanded="false" aria-controls="share-dropdown-menu">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="18" cy="5" r="3"></circle><circle cx="6" cy="12" r="3"></circle><circle cx="18" cy="19" r="3"></circle><line x1="8.59" x2="15.42" y1="13.51" y2="17.49"></line><line x1="15.41" x2="8.59" y1="6.51" y2="10.49"></line></svg>
                    <span class="btn-text">Share</span>
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true"><polyline points="6 9 12 15 18 9"></polyline></svg>
                </button>
                <div id="share-dropdown-menu" class="share-menu-popover hidden" role="menu" aria-label="Share this guide">
                    <div class="share-menu-header">Share this guide</div>
                    <button class="share-option" role="menuitem" data-share="link" aria-label="Copy page link">
                        <span class="share-icon-tile brand-tile-link" aria-hidden="true">
                            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"></path><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"></path></svg>
                        </span>
                        <span class="share-text">
                            <span class="share-title">Copy link</span>
                            <span class="share-sub">Page URL for browser or chat</span>
                        </span>
                        <span class="share-trailing" aria-hidden="true">
                            <svg class="icon-copy" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"></rect><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"></path></svg>
                            <svg class="icon-check" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"></path></svg>
                        </span>
                    </button>
                    <button class="share-option" role="menuitem" data-share="slack" aria-label="Copy link for Slack">
                        <span class="share-icon-tile brand-tile-slack" aria-hidden="true">
                            <svg width="16" height="16" viewBox="0 0 24 24"><path fill="#36C5F0" d="M8.834 5.042a2.528 2.528 0 0 1-2.521-2.52A2.528 2.528 0 0 1 8.834 0a2.528 2.528 0 0 1 2.521 2.522v2.52H8.834zM8.834 6.313a2.528 2.528 0 0 1 2.521 2.521 2.528 2.528 0 0 1-2.521 2.521H2.522A2.528 2.528 0 0 1 0 8.834a2.528 2.528 0 0 1 2.522-2.521h6.312z"/><path fill="#2EB67D" d="M18.956 8.834a2.528 2.528 0 0 1 2.522-2.521A2.528 2.528 0 0 1 24 8.834a2.528 2.528 0 0 1-2.522 2.521h-2.522V8.834zM17.688 8.834a2.528 2.528 0 0 1-2.523 2.521 2.527 2.527 0 0 1-2.52-2.521V2.522A2.527 2.527 0 0 1 15.165 0a2.528 2.528 0 0 1 2.523 2.522v6.312z"/><path fill="#E01E5A" d="M5.042 15.165a2.528 2.528 0 0 1-2.52 2.523A2.528 2.528 0 0 1 0 15.165a2.527 2.527 0 0 1 2.522-2.52h2.52v2.52zM6.313 15.165a2.527 2.527 0 0 1 2.521-2.52 2.527 2.527 0 0 1 2.521 2.52v6.313A2.528 2.528 0 0 1 8.834 24a2.528 2.528 0 0 1-2.521-2.522v-6.313z"/><path fill="#ECB22E" d="M15.165 18.956a2.528 2.528 0 0 1 2.523 2.522A2.528 2.528 0 0 1 15.165 24a2.527 2.527 0 0 1-2.52-2.522v-2.522h2.52zM15.165 17.688a2.527 2.527 0 0 1-2.52-2.523 2.526 2.526 0 0 1 2.52-2.52h6.313A2.527 2.527 0 0 1 24 15.165a2.528 2.528 0 0 1-2.522 2.523h-6.313z"/></svg>
                        </span>
                        <span class="share-text">
                            <span class="share-title">Slack</span>
                            <span class="share-sub">Copy link for Slack channel</span>
                        </span>
                        <span class="share-trailing" aria-hidden="true">
                            <svg class="icon-copy" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"></rect><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"></path></svg>
                            <svg class="icon-check" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"></path></svg>
                        </span>
                    </button>
                    <button class="share-option" role="menuitem" data-share="teams" aria-label="Copy link for Microsoft Teams">
                        <span class="share-icon-tile brand-tile-teams" aria-hidden="true">
                            <svg width="16" height="16" viewBox="0 0 16 16"><path fill="#7B83EB" d="M9.186 4.797a2.42 2.42 0 1 0-2.86-2.448h1.178c.929 0 1.682.753 1.682 1.682Zm-4.295 7.738h2.613c.929 0 1.682-.753 1.682-1.682V5.58h2.783a.7.7 0 0 1 .682.716v4.294a4.197 4.197 0 0 1-4.093 4.293c-1.618-.04-3-.99-3.667-2.35Zm10.737-9.372a1.674 1.674 0 1 1-3.349 0 1.674 1.674 0 0 1 3.349 0m-2.238 9.488-.12-.002a5.2 5.2 0 0 0 .381-2.07V6.306a1.7 1.7 0 0 0-.15-.725h1.792c.39 0 .707.317.707.707v3.765a2.6 2.6 0 0 1-2.598 2.598z"/><path fill="#464EB8" d="M.682 3.349h6.822c.377 0 .682.305.682.682v6.822a.68.68 0 0 1-.682.682H.682A.68.68 0 0 1 0 10.853V4.03c0-.377.305-.682.682-.682Zm5.206 2.596v-.72h-3.59v.72h1.357V9.66h.87V5.945z"/></svg>
                        </span>
                        <span class="share-text">
                            <span class="share-title">Teams</span>
                            <span class="share-sub">Copy title + link for Teams</span>
                        </span>
                        <span class="share-trailing" aria-hidden="true">
                            <svg class="icon-copy" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"></rect><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"></path></svg>
                            <svg class="icon-check" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"></path></svg>
                        </span>
                    </button>
                    <button class="share-option" role="menuitem" data-share="notion" aria-label="Copy Markdown for Notion">
                        <span class="share-icon-tile brand-tile-notion" aria-hidden="true">
                            <svg width="16" height="16" viewBox="0 0 24 24"><path fill="currentColor" d="M4.459 4.208c.746.606 1.026.56 2.428.466l13.215-.793c.28 0 .047-.28-.046-.326L17.86 1.968c-.42-.326-.981-.7-2.055-.607L3.01 2.295c-.466.046-.56.28-.374.466zm.793 3.08v13.904c0 .747.373 1.027 1.214.98l14.523-.84c.841-.046.935-.56.935-1.167V6.354c0-.606-.233-.933-.748-.887l-15.177.887c-.56.047-.747.327-.747.933zm14.337.745c.093.42 0 .84-.42.888l-.7.14v10.264c-.608.327-1.168.514-1.635.514-.748 0-.935-.234-1.495-.933l-4.577-7.186v6.952L12.21 19s0 .84-1.168.84l-3.222.186c-.093-.186 0-.653.327-.746l.84-.233V9.854L7.822 9.76c-.094-.42.14-1.026.793-1.073l3.456-.233 4.764 7.279v-6.44l-1.215-.139c-.093-.514.28-.887.747-.933zM1.936 1.035l13.31-.98c1.634-.14 2.055-.047 3.082.7l4.249 2.986c.7.513.934.653.934 1.213v16.378c0 1.026-.373 1.634-1.68 1.726l-15.458.934c-.98.047-1.448-.093-1.962-.747l-3.129-4.06c-.56-.747-.793-1.306-.793-1.96V2.667c0-.839.374-1.54 1.447-1.632z"/></svg>
                        </span>
                        <span class="share-text">
                            <span class="share-title">Notion</span>
                            <span class="share-sub">Copy Markdown for Notion</span>
                        </span>
                        <span class="share-trailing" aria-hidden="true">
                            <svg class="icon-copy" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"></rect><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"></path></svg>
                            <svg class="icon-check" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"></path></svg>
                        </span>
                    </button>
                    <div class="share-separator" aria-hidden="true"></div>
                    <button class="share-option" role="menuitem" data-share="email" aria-label="Share via Gmail">
                        <span class="share-icon-tile brand-tile-gmail" aria-hidden="true">
                            <svg width="16" height="16" viewBox="52 42 88 66"><path fill="#4285F4" d="M58 108h14V74L52 59v43c0 3.32 2.69 6 6 6"/><path fill="#34A853" d="M120 108h14c3.32 0 6-2.69 6-6V59l-20 15"/><path fill="#FBBC04" d="M120 48v26l20-15v-8c0-7.42-8.47-11.65-14.4-7.2"/><path fill="#EA4335" d="M72 74V48l24 18 24-18v26L96 92"/><path fill="#C5221F" d="M52 51v8l20 15V48l-5.6-4.2c-5.94-4.45-14.4-.22-14.4 7.2"/></svg>
                        </span>
                        <span class="share-text">
                            <span class="share-title">Email</span>
                            <span class="share-sub">Open Mail with link</span>
                        </span>
                        <span class="share-trailing" aria-hidden="true">
                            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17 17 7"></path><path d="M7 7h10v10"></path></svg>
                        </span>
                    </button>
                </div>
            </div>
            <span id="share-live-region" class="sr-only" role="status" aria-live="polite"></span>
"###;

// ---------------------------------------------------------------------------
// Interactive script (ported verbatim; single splice point: session id)
// ---------------------------------------------------------------------------

/// JS before `const sessionId = "…"`.
const INTERACTIVE_JS_BEFORE_ID: &str = r###"        const sessionId = ""###;

/// JS after the session id through `</script>`-exclusive tail.
const INTERACTIVE_JS_AFTER_ID: &str = r###"";
        const checkboxes = document.querySelectorAll('.step-check');
        const badgeSidebar = document.getElementById('step-completion-badge');
        const badgeHeader = document.getElementById('step-completion-badge-header');
        const progressBar = document.getElementById('progress-bar');
        const miniProgressBar = document.getElementById('mini-progress-bar');

        // Theme Management (Modern Minimalist / Developer Dark / Enterprise SOP)
        const themeDisplayNames = {
            'modern-minimal': 'Modern Minimalist',
            'developer-dark': 'Developer Dark',
            'enterprise-sop': 'Enterprise SOP'
        };
        const allThemes = ['modern-minimal', 'developer-dark', 'enterprise-sop'];

        function initTheme() {
            const savedTheme = localStorage.getItem('flowline_theme');
            const docTheme = document.documentElement.getAttribute('data-theme') || 'modern-minimal';
            const active = (savedTheme && allThemes.includes(savedTheme)) ? savedTheme : docTheme;
            setTheme(active);
        }

        function setTheme(themeVal) {
            if (!allThemes.includes(themeVal)) themeVal = 'modern-minimal';
            document.documentElement.setAttribute('data-theme', themeVal);
            localStorage.setItem('flowline_theme', themeVal);
            
            const label = document.getElementById('theme-btn-label');
            if (label) {
                label.textContent = themeDisplayNames[themeVal] || 'Theme';
            }
            
            document.querySelectorAll('.theme-option').forEach(btn => {
                btn.classList.toggle('active', btn.dataset.themeVal === themeVal);
            });
            
            const menu = document.getElementById('theme-dropdown-menu');
            if (menu) menu.classList.add('hidden');
        }

        function cycleTheme() {
            const current = document.documentElement.getAttribute('data-theme') || 'modern-minimal';
            const idx = allThemes.indexOf(current);
            const next = allThemes[(idx + 1) % allThemes.length];
            setTheme(next);
        }

        const themeBtn = document.getElementById('theme-selector-btn');
        const themeMenu = document.getElementById('theme-dropdown-menu');
        if (themeBtn && themeMenu) {
            themeBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                themeMenu.classList.toggle('hidden');
            });
            document.querySelectorAll('.theme-option').forEach(opt => {
                opt.addEventListener('click', (e) => {
                    e.stopPropagation();
                    setTheme(opt.dataset.themeVal);
                });
            });
            document.addEventListener('click', () => {
                themeMenu.classList.add('hidden');
            });
        }

        // Checklist State Persistence
        function loadChecklist() {
            const saved = JSON.parse(localStorage.getItem('flowline_' + sessionId) || '{}');
            checkboxes.forEach(cb => {
                const stepIdx = cb.dataset.step;
                if (saved[stepIdx]) {
                    cb.checked = true;
                    document.getElementById('step-card-' + stepIdx)?.classList.add('step-completed');
                    document.getElementById('nav-item-' + stepIdx)?.classList.add('nav-done');
                }
            });
            updateProgress();
        }

        function updateProgress() {
            const total = checkboxes.length;
            const checked = document.querySelectorAll('.step-check:checked').length;
            const text = `${checked} of ${total} completed`;
            if (badgeSidebar) badgeSidebar.textContent = `${checked} / ${total}`;
            if (badgeHeader) badgeHeader.textContent = text;
            
            if (total > 0) {
                const pct = (checked / total) * 100;
                if (progressBar) progressBar.style.width = pct + '%';
                if (miniProgressBar) miniProgressBar.style.width = pct + '%';
            }
        }

        checkboxes.forEach(cb => {
            cb.addEventListener('change', () => {
                const stepIdx = cb.dataset.step;
                const card = document.getElementById('step-card-' + stepIdx);
                const nav = document.getElementById('nav-item-' + stepIdx);
                
                if (cb.checked) {
                    card?.classList.add('step-completed');
                    nav?.classList.add('nav-done');
                } else {
                    card?.classList.remove('step-completed');
                    nav?.classList.remove('nav-done');
                }
                
                const saved = JSON.parse(localStorage.getItem('flowline_' + sessionId) || '{}');
                saved[stepIdx] = cb.checked;
                localStorage.setItem('flowline_' + sessionId, JSON.stringify(saved));
                updateProgress();
            });
        });

        // Toggle Checklist Mode
        let checklistModeActive = false;
        document.getElementById('toggle-checklist-btn')?.addEventListener('click', function() {
            checklistModeActive = !checklistModeActive;
            document.body.classList.toggle('checklist-mode-active', checklistModeActive);
            this.classList.toggle('active', checklistModeActive);
        });

        // Apple Segmented Picker (Static vs Animation vs Video)
        function switchMediaView(stepIndex, mode) {
            const card = document.getElementById('step-card-' + stepIndex);
            if (!card) return;
            
            const views = card.querySelectorAll('.media-view');
            views.forEach(v => v.classList.add('hidden'));
            
            const targetView = card.querySelector('.media-view-' + mode);
            if (targetView) targetView.classList.remove('hidden');
            
            const btns = card.querySelectorAll('.segment-btn');
            btns.forEach(b => b.classList.remove('active'));
            const activeBtn = card.querySelector(`[data-mode="${mode}"]`);
            if (activeBtn) activeBtn.classList.add('active');
        }

        // Copy Text Tooltip
        function copyText(text, btnElement) {
            navigator.clipboard.writeText(text).then(() => {
                const originalHTML = btnElement.innerHTML;
                btnElement.classList.add('copied');
                btnElement.innerHTML = `
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"></polyline></svg>
                    <span>Copied</span>
                `;
                setTimeout(() => {
                    btnElement.innerHTML = originalHTML;
                    btnElement.classList.remove('copied');
                }, 2000);
            });
        }

        // Share dropdown (official brand rows, whole-row click-to-copy)
        function sharePayload(kind) {
            const url = window.location.href;
            const title = document.title.replace(/ — step·it$/, '');
            if (kind === 'notion') return `[${title}](${url})`;
            if (kind === 'teams') return `${title}\n${url}`;
            return url;
        }

        async function copyShareText(text) {
            try {
                await navigator.clipboard.writeText(text);
                return true;
            } catch (err) {
                const ta = document.createElement('textarea');
                ta.value = text;
                ta.setAttribute('readonly', '');
                ta.style.position = 'fixed';
                ta.style.left = '-9999px';
                ta.style.fontSize = '16px';
                document.body.appendChild(ta);
                ta.select();
                try { ta.setSelectionRange(0, ta.value.length); } catch (e) {}
                let ok = false;
                try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
                document.body.removeChild(ta);
                return ok;
            }
        }

        function announceShare(message) {
            const live = document.getElementById('share-live-region');
            if (!live) return;
            live.textContent = '';
            setTimeout(() => { live.textContent = message; }, 30);
            setTimeout(() => { if (live.textContent === message) live.textContent = ''; }, 2000);
        }

        const shareBtn = document.getElementById('share-selector-btn');
        const shareMenu = document.getElementById('share-dropdown-menu');
        function setShareOpen(open) {
            if (!shareBtn || !shareMenu) return;
            shareMenu.classList.toggle('hidden', !open);
            shareBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
        }
        if (shareBtn && shareMenu) {
            shareBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                document.getElementById('theme-dropdown-menu')?.classList.add('hidden');
                setShareOpen(shareMenu.classList.contains('hidden'));
                if (!shareMenu.classList.contains('hidden')) {
                    shareMenu.querySelector('.share-option')?.focus();
                }
            });
            document.addEventListener('click', (e) => {
                if (!shareMenu.classList.contains('hidden') && !shareMenu.contains(e.target) && e.target !== shareBtn && !shareBtn.contains(e.target)) {
                    setShareOpen(false);
                }
            });
            document.addEventListener('keydown', (e) => {
                if (e.key === 'Escape' && !shareMenu.classList.contains('hidden')) {
                    setShareOpen(false);
                    shareBtn.focus();
                }
            });
            shareMenu.addEventListener('keydown', (e) => {
                const options = Array.from(shareMenu.querySelectorAll('.share-option'));
                const idx = options.indexOf(document.activeElement);
                if (e.key === 'ArrowDown') { e.preventDefault(); (options[idx + 1] || options[0])?.focus(); }
                else if (e.key === 'ArrowUp') { e.preventDefault(); (options[idx - 1] || options[options.length - 1])?.focus(); }
            });
            shareMenu.querySelectorAll('.share-option').forEach(opt => {
                opt.addEventListener('click', async (e) => {
                    e.stopPropagation();
                    const kind = opt.dataset.share;
                    if (kind === 'email') {
                        const url = window.location.href;
                        const title = document.title.replace(/ — step·it$/, '');
                        window.location.href = 'mailto:?subject=' + encodeURIComponent(title) + '&body=' + encodeURIComponent(title + '\n' + url);
                        setShareOpen(false);
                        return;
                    }
                    const ok = await copyShareText(sharePayload(kind));
                    if (ok) {
                        opt.classList.add('copied');
                        announceShare('Copied: ' + (opt.getAttribute('aria-label') || 'share link'));
                        setTimeout(() => opt.classList.remove('copied'), 2000);
                    } else {
                        announceShare('Copy failed — select the address bar to copy manually');
                    }
                });
            });
        }

        // Keyboard Navigation (J / K / T / C)
        document.addEventListener('keydown', (e) => {
            if (['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) return;
            
            const cards = Array.from(document.querySelectorAll('.step-card'));
            if (!cards.length) return;
            
            const scrollPos = window.scrollY + 140;
            let currentIdx = cards.findIndex(c => c.offsetTop <= scrollPos && (c.offsetTop + c.offsetHeight) > scrollPos);
            if (currentIdx === -1) currentIdx = 0;

            if (e.key === 'j' || e.key === 'J' || e.key === 'ArrowDown') {
                e.preventDefault();
                const nextIdx = Math.min(cards.length - 1, currentIdx + 1);
                cards[nextIdx].scrollIntoView({ behavior: 'smooth', block: 'start' });
            } else if (e.key === 'k' || e.key === 'K' || e.key === 'ArrowUp') {
                e.preventDefault();
                const prevIdx = Math.max(0, currentIdx - 1);
                cards[prevIdx].scrollIntoView({ behavior: 'smooth', block: 'start' });
            } else if (e.key === 't' || e.key === 'T') {
                cycleTheme();
            } else if (e.key === 'c' || e.key === 'C') {
                document.getElementById('toggle-checklist-btn')?.click();
            }
        });

        // Active Step Highlighting on Scroll
        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    const id = entry.target.id;
                    const stepIdx = id.replace('step-card-', '');
                    document.querySelectorAll('.nav-link').forEach(l => l.classList.remove('active'));
                    document.getElementById('nav-item-' + stepIdx)?.classList.add('active');
                }
            });
        }, { rootMargin: '-15% 0px -65% 0px' });

        document.querySelectorAll('.step-card').forEach(card => observer.observe(card));

        // Clean In-Place Zoom Toggle
        function toggleInPlaceZoom(stepIndex, pctX, pctY) {
            const wrapper = document.getElementById('zoom-wrapper-' + stepIndex);
            const img = document.getElementById('zoom-img-' + stepIndex);
            if (!wrapper || !img) return;
            
            const isZoomed = wrapper.classList.toggle('is-zoomed');
            if (isZoomed) {
                img.style.transformOrigin = `${pctX}% ${pctY}%`;
                img.style.transform = 'scale(2.3)';
                const pill = wrapper.querySelector('.zoom-indicator-pill span');
                if (pill) pill.textContent = 'Reset Zoom';
            } else {
                img.style.transform = 'none';
                const pill = wrapper.querySelector('.zoom-indicator-pill span');
                if (pill) pill.textContent = 'Click to Zoom';
            }
        }

        // Fullscreen Interactive Lightbox Modal
        let currentLightboxScale = 1.0;
        function openLightbox(src, title, x, y) {
            const modal = document.getElementById('lightbox-modal');
            const img = document.getElementById('lightbox-img');
            const titleEl = document.getElementById('lightbox-title');
            const coordsEl = document.getElementById('lightbox-coords-tag');
            if (!modal || !img) return;
            
            currentLightboxScale = 1.0;
            img.src = src;
            img.style.transform = 'none';
            if (titleEl) titleEl.textContent = title;
            if (coordsEl) coordsEl.textContent = (x > 0 && y > 0) ? `Target Focus Coordinates: (${x}, ${y})` : '';
            
            modal.classList.remove('hidden');
            document.body.style.overflow = 'hidden';
        }

        function closeLightbox() {
            const modal = document.getElementById('lightbox-modal');
            if (modal) {
                modal.classList.add('hidden');
                document.body.style.overflow = '';
            }
        }

        function adjustLightboxZoom(delta) {
            const img = document.getElementById('lightbox-img');
            const label = document.getElementById('lightbox-zoom-level');
            if (!img) return;
            
            currentLightboxScale = Math.max(0.5, Math.min(4.0, currentLightboxScale + delta));
            img.style.transform = `scale(${currentLightboxScale.toFixed(2)})`;
            if (label) label.textContent = `${Math.round(currentLightboxScale * 100)}%`;
        }

        function resetLightboxZoom() {
            const img = document.getElementById('lightbox-img');
            const label = document.getElementById('lightbox-zoom-level');
            if (!img) return;
            currentLightboxScale = 1.0;
            img.style.transform = 'none';
            if (label) label.textContent = '100%';
        }

        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') closeLightbox();
        });

        document.addEventListener('DOMContentLoaded', () => {
            initTheme();
            loadChecklist();
        });
"###;

// ---------------------------------------------------------------------------
// Open-in-editor deep links (OpenInEditorCore — pure URL-string logic)
// ---------------------------------------------------------------------------

/// Canonical bundle identifiers, in lookup-preference order per target.
/// Mirrors `EditorBundleIDs`.
pub mod editor_bundle_ids {
    /// Cursor.
    pub const CURSOR: &str = "com.todesktop.230313mzl4w4u92";
    /// VS Code.
    pub const VSCODE: &str = "com.microsoft.VSCode";
    /// VS Code Insiders.
    pub const VSCODE_INSIDERS: &str = "com.microsoft.VSCodeInsiders";
    /// Xcode.
    pub const XCODE: &str = "com.apple.dt.Xcode";
    /// Zed.
    pub const ZED: &str = "dev.zed.Zed";
    /// Sublime Text 4.
    pub const SUBLIME: &str = "com.sublimetext.4";
    /// Finder.
    pub const FINDER: &str = "com.apple.finder";
    /// Panova Nova (verified but unwired — no editor target uses it yet).
    pub const NOVA: &str = "com.panic.Nova";
}

/// URL schemes used for deep links (`<scheme>://…`).
/// Mirrors `EditorURLSchemes`.
pub mod editor_url_schemes {
    /// Cursor.
    pub const CURSOR: &str = "cursor";
    /// VS Code.
    pub const VSCODE: &str = "vscode";
    /// VS Code Insiders.
    pub const VSCODE_INSIDERS: &str = "vscode-insiders";
    /// Zed.
    pub const ZED: &str = "zed";
    /// Sublime Text.
    pub const SUBLIME: &str = "sublimetext";
}

/// How a deep-link URL is shaped for one editor.
/// Mirrors `DeepLinkStyle`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeepLinkStyle {
    /// `<scheme>://file<path>[:line[:column]]` (Cursor, VS Code, Zed).
    PathSuffix,
    /// `sublimetext://open?url=file://<path>[&line=L][&column=C]`.
    SublimeOpenQuery,
    /// No usable scheme: runtime uses a direct launch / reveal instead.
    None,
}

/// Launch data for one editor, keyed by the app's `EditorTarget.rawValue`.
/// Mirrors `EditorLaunchInfo`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EditorLaunchInfo {
    /// Matches the app's `EditorTarget.rawValue` (`"cursor"`, …).
    pub raw_value: &'static str,
    /// Bundle ids tried in order by install detection.
    pub bundle_identifiers: &'static [&'static str],
    /// App names for the full-path fallback lookup.
    pub application_names: &'static [&'static str],
    /// Default deep-link scheme, or `None` when style is [`DeepLinkStyle::None`].
    pub url_scheme: Option<&'static str>,
    /// Install variant with a different scheme (VS Code Insiders), if any.
    pub insiders_bundle_id: Option<&'static str>,
    /// Scheme for the insiders variant, if any.
    pub insiders_scheme: Option<&'static str>,
    /// Deep-link shape.
    pub deep_link_style: DeepLinkStyle,
}

/// Launch info for every supported editor, in canonical button order.
/// Mirrors `allEditorLaunchInfos`.
pub static ALL_EDITOR_LAUNCH_INFOS: &[EditorLaunchInfo] = &[
    EditorLaunchInfo {
        raw_value: "cursor",
        bundle_identifiers: &[editor_bundle_ids::CURSOR],
        application_names: &["Cursor"],
        url_scheme: Some(editor_url_schemes::CURSOR),
        insiders_bundle_id: None,
        insiders_scheme: None,
        deep_link_style: DeepLinkStyle::PathSuffix,
    },
    EditorLaunchInfo {
        raw_value: "vscode",
        bundle_identifiers: &[
            editor_bundle_ids::VSCODE,
            editor_bundle_ids::VSCODE_INSIDERS,
        ],
        application_names: &["Visual Studio Code", "Visual Studio Code - Insiders"],
        url_scheme: Some(editor_url_schemes::VSCODE),
        insiders_bundle_id: Some(editor_bundle_ids::VSCODE_INSIDERS),
        insiders_scheme: Some(editor_url_schemes::VSCODE_INSIDERS),
        deep_link_style: DeepLinkStyle::PathSuffix,
    },
    EditorLaunchInfo {
        raw_value: "xcode",
        bundle_identifiers: &[editor_bundle_ids::XCODE],
        application_names: &["Xcode"],
        url_scheme: None,
        insiders_bundle_id: None,
        insiders_scheme: None,
        deep_link_style: DeepLinkStyle::None,
    },
    EditorLaunchInfo {
        raw_value: "zed",
        bundle_identifiers: &[editor_bundle_ids::ZED],
        application_names: &["Zed"],
        url_scheme: Some(editor_url_schemes::ZED),
        insiders_bundle_id: None,
        insiders_scheme: None,
        deep_link_style: DeepLinkStyle::PathSuffix,
    },
    EditorLaunchInfo {
        raw_value: "sublime",
        bundle_identifiers: &[editor_bundle_ids::SUBLIME],
        application_names: &["Sublime Text"],
        url_scheme: Some(editor_url_schemes::SUBLIME),
        insiders_bundle_id: None,
        insiders_scheme: None,
        deep_link_style: DeepLinkStyle::SublimeOpenQuery,
    },
    EditorLaunchInfo {
        raw_value: "finder",
        bundle_identifiers: &[editor_bundle_ids::FINDER],
        application_names: &["Finder"],
        url_scheme: None,
        insiders_bundle_id: None,
        insiders_scheme: None,
        deep_link_style: DeepLinkStyle::None,
    },
];

/// Launch info for an editor raw value, or `None` when unknown.
/// Mirrors `editorLaunchInfo(forRawValue:)`.
pub fn editor_launch_info(raw_value: &str) -> Option<&'static EditorLaunchInfo> {
    ALL_EDITOR_LAUNCH_INFOS
        .iter()
        .find(|info| info.raw_value == raw_value)
}

/// Scheme to use for `info`, accounting for per-install variants (VS Code
/// Insiders → `vscode-insiders://`). Mirrors `resolvedURLScheme(for:bundleIdentifier:)`.
pub fn resolved_url_scheme(
    info: &EditorLaunchInfo,
    bundle_identifier: Option<&str>,
) -> Option<&'static str> {
    if let (Some(insiders), Some(scheme)) = (info.insiders_bundle_id, info.insiders_scheme) {
        if bundle_identifier == Some(insiders) {
            return Some(scheme);
        }
    }
    info.url_scheme
}

/// Percent-encode a filesystem path the way Swift's
/// `path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)`
/// does: unreserved + `$&'()*+,;=:@/` + `/` pass through, every other byte
/// (including `%` itself and non-ASCII UTF-8 bytes) becomes `%XX`.
pub fn percent_encode_path(path: &str) -> String {
    const ALLOWED: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/";
    let mut out = String::with_capacity(path.len());
    for b in path.bytes() {
        if ALLOWED.contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// Builds a deep-link URL that opens `file_path` in the editor described by
/// `info`, optionally at `line`/`column` (1-based). Returns `None` when the
/// editor has no deep-link style (`.none`) or the path is empty.
///
/// Rules (mirroring `deepLinkURL(for:fileURL:line:column:bundleIdentifier:)`,
/// covered by Swift tests):
/// - Non-positive lines/columns are dropped; a column without a line is dropped.
/// - `.pathSuffix`: `<scheme>://file<path>[:line[:column]]`.
/// - `.sublimeOpenQuery`: `sublimetext://open?url=file://<path>[&line=L][&column=C]`.
///
/// DIVERGENCE: Swift takes a `URL` and returns `nil` for non-file URLs;
/// without a URL type here the caller passes a filesystem path and an
/// empty path maps to `None`.
pub fn deep_link_url(
    info: &EditorLaunchInfo,
    file_path: &str,
    line: Option<i64>,
    column: Option<i64>,
    bundle_identifier: Option<&str>,
) -> Option<String> {
    if file_path.is_empty() {
        return None;
    }
    let scheme = resolved_url_scheme(info, bundle_identifier)?;
    let clean_line = line.filter(|l| *l >= 1);
    let clean_column = clean_line.and(column).filter(|c| *c >= 1);
    let encoded = percent_encode_path(file_path);
    match info.deep_link_style {
        DeepLinkStyle::PathSuffix => {
            let mut url = format!("{scheme}://file{encoded}");
            if let Some(l) = clean_line {
                url.push_str(&format!(":{l}"));
                if let Some(c) = clean_column {
                    url.push_str(&format!(":{c}"));
                }
            }
            Some(url)
        }
        DeepLinkStyle::SublimeOpenQuery => {
            let mut url = format!("{scheme}://open?url=file://{encoded}");
            if let Some(l) = clean_line {
                url.push_str(&format!("&line={l}"));
            }
            if let Some(c) = clean_column {
                url.push_str(&format!("&column={c}"));
            }
            Some(url)
        }
        DeepLinkStyle::None => None,
    }
}

/// User-facing toast for the reveal-in-Finder fallback path.
/// Mirrors `finderFallbackToast(displayName:)`.
pub fn finder_fallback_toast(display_name: &str) -> String {
    format!("{display_name} isn't installed — revealed the file in Finder instead.")
}
