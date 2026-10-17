//! Markdown projection — byte-identical port of
//! `Sources/StepItPublishing/MarkdownExporter.swift::exportMarkdown`.

use crate::StepSession;

/// Mirror of `MarkdownExporter.exportMarkdown(session:relativeAssetPrefix:)`.
pub fn export_markdown(session: &StepSession, relative_asset_prefix: &str) -> String {
    // Swift: `if let synth = ..., !synth.trimmingCharacters(in: .whitespaces).isEmpty`
    // NOTE: `.whitespaces` excludes newlines, so mirror that (not full trim).
    if let Some(synth) = &session.synthesized_markdown {
        if !trim_swift_whitespaces(synth).is_empty() {
            return synth.clone();
        }
    }

    let mut md = format!("# {}\n\n", session.title);

    if let Some(summary) = &session.summary {
        if !summary.is_empty() {
            md.push_str(&format!("> {summary}\n\n"));
        }
    }

    md.push_str("| Recorded | Steps | Theme | Mode |\n");
    md.push_str("| :--- | :--- | :--- | :--- |\n");
    md.push_str(&format!(
        "| {} | {} | {} | {} |\n\n",
        format_recorded(&session.started_at),
        session.steps.len(),
        session.theme.display_name(),
        session.media_mode.display_name(),
    ));
    md.push_str("---\n\n");

    md.push_str("## Table of Contents\n\n");
    for step in &session.steps {
        md.push_str(&format!(
            "- [Step {}: {}](#step-{}-{})\n",
            step.index,
            step.action_description,
            step.index,
            toc_anchor(&step.action_description),
        ));
    }
    md.push_str("\n---\n\n");

    md.push_str("## Workflow Steps\n\n");
    for step in &session.steps {
        md.push_str(&format!("### Step {}: {}\n\n", step.index, step.action_description));

        if !step.app_name.is_empty() {
            md.push_str(&format!("- **Application**: `{}`\n", step.app_name));
        }
        if !step.window_title.is_empty() {
            md.push_str(&format!("- **Window**: *{}*\n", step.window_title));
        }
        if let Some(role) = &step.element_role {
            let title_desc = match &step.element_title {
                Some(t) => format!(" (`{t}`)"),
                None => String::new(),
            };
            md.push_str(&format!("- **Target Element**: {role}{title_desc}\n"));
        }
        if let Some(combo) = &step.hotkey_combo {
            md.push_str(&format!("- **Shortcut**: `{combo}`\n"));
        }
        if let Some(directory) = &step.working_directory {
            md.push_str(&format!("- **Working Directory**: `{directory}`\n"));
        }
        if step.is_redacted == Some(true) {
            md.push_str("- **Redacted**: 🛡️ sensitive data blurred offline\n");
        }
        if let Some(coords) = &step.coordinates {
            // Swift `Int(...)` truncates toward zero; Rust `as` does the same.
            md.push_str(&format!(
                "- **Coordinates**: ({}, {})\n",
                coords.x as i64,
                coords.y as i64
            ));
        }
        if let Some(notes) = &step.user_notes {
            if !notes.is_empty() {
                md.push_str(&format!("\n> **Note**: {notes}\n"));
            }
        }

        if let Some(text) = &step.text_blob {
            if !text.is_empty() {
                // Swift: `step.code_language ?? (step.is_code ? "bash" : "")`
                let lang: &str = match &step.code_language {
                    Some(l) => l,
                    None => {
                        if step.is_code {
                            "bash"
                        } else {
                            ""
                        }
                    }
                };
                md.push_str(&format!("\n```{lang}\n{text}\n```\n"));
            }
        }

        md.push('\n');

        // Swift: empty -> "", trailing "/" kept, else append "/".
        let prefix = if relative_asset_prefix.is_empty() {
            String::new()
        } else if relative_asset_prefix.ends_with('/') {
            relative_asset_prefix.to_string()
        } else {
            format!("{relative_asset_prefix}/")
        };

        // Prefer GIF if animated, else screenshot (Swift if/else-if).
        if let Some(gif) = &step.assets.gif {
            md.push_str(&format!(
                "![{}]({prefix}{gif})\n\n",
                step.action_description
            ));
        } else if let Some(screenshot) = &step.assets.screenshot {
            md.push_str(&format!(
                "![{}]({prefix}{screenshot})\n\n",
                step.action_description
            ));
        }
        if let Some(zoom_crop) = &step.assets.zoom_crop {
            md.push_str(&format!(
                "🔍 *[View 2.4× Focused DOM Zoom Crop]({prefix}{zoom_crop})*\n\n"
            ));
        }
    }

    md.push_str("---\n\n");
    md.push_str("_Documented with [step·it](https://github.com/stepit/stepit) for macOS._\n");
    md
}

/// Swift `.trimmingCharacters(in: .whitespaces)`: Unicode whitespace EXCEPT
/// newlines (U+000A, U+000D and friends are in `.newlines`, not `.whitespaces`).
fn trim_swift_whitespaces(s: &str) -> &str {
    s.trim_matches(|c: char| c.is_whitespace() && c != '\n' && c != '\r')
}

/// Swift TOC anchor: lowercase, `" "` -> `"-"`, strip `"` and `'`.
/// NOTE: only ASCII space is replaced (not tabs/other whitespace), matching
/// `replacingOccurrences(of: " ", ...)`.
fn toc_anchor(description: &str) -> String {
    description
        .to_lowercase()
        .replace(' ', "-")
        .replace(['"', '\''], "")
}

/// Render the `Recorded` cell.
///
/// DIVERGENCE (pinned, documented): Swift uses `session.started_at.formatted()`
/// — `Date.FormatStyle` with the ambient locale/timezone, i.e.
/// non-deterministic across machines. The golden
/// (`shared/goldens/markdown.sample.md`) was captured under an en-IN/IST
/// environment: `2026-03-01T10:00:00Z` renders as `1/3/2026, 3:30 PM`
/// (D/M/YYYY order, UTC+05:30, 12-hour clock, unpadded day/month/hour,
/// zero-padded minutes, and — matching Apple's `time(.shortened)` style — a
/// NARROW NO-BREAK SPACE U+202F before AM/PM, not an ASCII space). This port
/// pins exactly that rendering deterministically so parity holds everywhere.
pub fn format_recorded(iso_started_at: &str) -> String {
    const IST_OFFSET_SECS: i64 = 5 * 3600 + 30 * 60;
    let epoch = parse_iso8601_z(iso_started_at);
    let local = epoch + IST_OFFSET_SECS;
    let days = local.div_euclid(86_400);
    let secs_of_day = local.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    let hh24 = secs_of_day / 3600;
    let mm = (secs_of_day % 3600) / 60;
    let (hh12, ampm) = match hh24 {
        0 => (12, "AM"),
        1..=11 => (hh24, "AM"),
        12 => (12, "PM"),
        _ => (hh24 - 12, "PM"),
    };
    format!("{d}/{m}/{y}, {hh12}:{mm:02}\u{202f}{ampm}")
}

/// Parse `YYYY-MM-DDTHH:MM:SS[.frac]Z` (also tolerates a missing `Z`) to
/// Unix epoch seconds. Panics on malformed input — fixtures are trusted.
fn parse_iso8601_z(s: &str) -> i64 {
    let s = s.strip_suffix('Z').unwrap_or(s);
    let (date, time) = s.split_once('T').expect("ISO8601 must contain 'T'");
    let mut d = date.split('-');
    let year: i64 = d.next().expect("year").parse().expect("year int");
    let month: i64 = d.next().expect("month").parse().expect("month int");
    let day: i64 = d.next().expect("day").parse().expect("day int");
    let time = time.split(['+', '-']).next().unwrap_or(time); // ignore +HH:MM tail if any
    let mut t = time.split(':');
    let hour: i64 = t.next().expect("hour").parse().expect("hour int");
    let min: i64 = t.next().expect("min").parse().expect("min int");
    let sec_part = t.next().expect("sec");
    let sec: i64 = sec_part
        .split('.')
        .next()
        .expect("sec")
        .parse()
        .expect("sec int");
    days_from_civil(year, month, day) * 86_400 + hour * 3600 + min * 60 + sec
}

/// Howard Hinnant's days-from-civil (1970-01-01 == day 0).
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// Inverse of [`days_from_civil`]: days since 1970-01-01 -> (y, m, d).
fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}
