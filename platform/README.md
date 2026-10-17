# platform/ — per-OS homes

Each OS gets one directory. Cross-platform logic never lives here; it lives
in `apps/desktop` (Swift) or `core/` (Rust). A platform dir only holds what
is genuinely OS-specific.

- `macos/` — the macOS app and all macOS-only Swift (ScreenCaptureKit/AX/Vision
  drivers, SwiftUI/AppKit surfaces). Implementation: `apps/desktop/`.
- `windows/` — roadmap home for the Windows surface. The capture core already
  exists: `core/crates/stepit_win_capture` (+ `x86_64-pc-windows-msvc` gate).
