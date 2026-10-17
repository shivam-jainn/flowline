# tooling/

Builds and gates for the monolith. One purpose per directory. All scripts
run from the repo root and resolve their own location
(`ROOT_DIR=.../../..`), so do not `cd` before invoking.

```
tooling/
  toolchain/ Cross-toolchain builds. build-rust-ffi.sh — cargo build
             (stepit_ffi, release) + uniffi-bindgen Swift bindings +
             xcodebuild xcframework. Rebuilds everything under
             platform/macos/Generated/ (gitignored). Entry point: `make ffi`.
  ci/       Gates. Every file exits non-zero on violation.
            check_architecture.sh — module boundaries (imports,
              singletons, WebKit/PDFKit/AppKit confinement, fixture
              conventions, Swift/Rust/shared separation). See header.
            check_rust.sh         — cargo test --workspace + clippy.
            check_wasm.sh         — wasm-pack build + node test.
            check_phase_r.sh      — full 5-stage gate (ffi → swift →
              arch → rust → windows-target → wasm).
  dev/      Local developer CLIs (taskctl, devpulse, fetch_cli).
  release/  App bundling + DMG creation (bundle_app.sh, create_dmg.sh).
```

Rules:

- `toolchain/` writes only to gitignored paths (`platform/macos/Generated/`, `core/target/`).
- `ci/` never writes; it only checks and exits 1 with a `❌` line.
- `dev/` and `release/` may write to `dist/` (gitignored).
- No absolute home-directory paths in any script (enforced by the arch gate).
- New scripts get `set -euo pipefail`, a `ROOT_DIR` preamble, and a
  one-line `Usage:` comment. Executable bit on (`chmod +x`).
