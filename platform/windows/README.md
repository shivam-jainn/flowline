# platform/windows — roadmap

No Windows surface ships yet. Staging area for when it does.

Already done (portable, OS-neutral):

- `core/crates/stepit_win_capture` — hooks, inspector, plugin manifest.
- Gate: `cargo check -p stepit_win_capture --target x86_64-pc-windows-msvc`
  (runs in `tooling/ci/check_phase_r.sh` and CI).
- Registry wiring resolves the Windows driver in the composition root
  (see `platform/macos/Sources/StepItCaptureAPI/DriverRegistry.swift`).

When a Windows UI/bundling story lands, it starts here — not in `core/`
(logic) and not in `platform/macos/` (macOS Swift).
