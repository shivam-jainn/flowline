# ⚡️ Flowline

> **Effortless step-by-step workflow capture & AI synthesis for macOS.**
> Native Swift. Privacy-first. Multi-provider AI Gateway. 1-click publishing to interactive web docs, print-ready PDFs, and Markdown.

Flowline records user workflows across any macOS app and turns them into human documentation
(interactive web site, PDF guide, Markdown) today — and machine-executable automation scripts
on the roadmap.

## Quick start

```bash
make build                       # ffi first, then swift build (use this, not bare `swift build`)
make test                        # ffi first, then swift test
swift run --package-path platform/macos flowline app     # menu bar + floating HUD app
swift run --package-path platform/macos flowline serve   # 10-page fixture web app on :8080
swift run --package-path platform/macos flowline demo    # demo guide from fixture captures
make check-arch                  # architecture & layout gate
make check-rust                  # cargo test + clippy
make check-phase-r               # full 5-stage gate (swift → arch → rust → windows → wasm)
```

Requirements: macOS 14+, Xcode 15+ toolchain (Swift 5.9+), and `DEVELOPER_DIR` pointed at a
full Xcode install when running `swift test` (Command Line Tools alone does not ship XCTest).
Rust via `rust-toolchain.toml` (stable + wasm32 target); `make ffi` also needs
`uniffi-bindgen` (`cargo install uniffi --features cli`) and Xcode CLT.

## Repository layout

One language per workspace, shared data in the middle, `make` as the task runner:

```
platform/
  macos/             SwiftPM package — ALL Swift lives here.
                     Sources/ (app, 10 library modules), Tests/,
                     Generated/ (FFI outputs, gitignored), Assets/
  windows/           Roadmap signpost (Rust driver already in core/)
core/                Cargo workspace — ALL Rust lives here.
                     crates/flowline_{ir,pipeline,engine,storage,ai_gateway,projections,ffi,win_capture}/
shared/              Language-agnostic data both toolchains consume (no code).
  contracts/         JSON Schemas = the common types (session, event, manifest)
  fixtures/          Deterministic fixture data (playground-web)
  goldens/           Golden corpus both suites assert against
tooling/             Builds + gates (toolchain/, ci/, dev/, release/)
dist/                Release artifacts (gitignored)
```

| Concern | Home | Consumed by |
| ------- | ---- | ----------- |
| Swift app + modules + tests | `platform/macos/` | `swift build --package-path platform/macos` |
| Rust core + parity tests | `core/` | `cargo test --manifest-path core/Cargo.toml` |
| Common types | `shared/contracts/` | Swift Codable + Rust serde (both must honor) |
| Fixtures / goldens | `shared/fixtures/`, `shared/goldens/` | `FixtureLocator`, `parity_harness` |
| Gates | `tooling/ci/` | `make check-*`, `.github/workflows/ci.yml` |

**Boundary rules:** portable Swift modules (`Flowline{IR,Pipeline,Engine,Storage,CaptureAPI}`)
stay Foundation-only; AppKit lives only in `FlowlineMacCapture`; WebKit/PDFKit stay in
`FlowlinePublishing/PDFGenerator.swift`; `shared/` is data-only (no `.swift`/`.rs`);
no Swift under `core/`, no Rust under `platform/`. `tooling/ci/check_architecture.sh`
enforces all of this — run `make check-arch` before every commit.

## Documentation

- **[docs/PLAN.md](docs/PLAN.md)** — vision, decoupled architecture, roadmap, and target layout.
- **[docs/roadmap/](docs/roadmap/)** — build order + per-phase exit gates (start at `index.md`).
- **[platform/macos/README.md](platform/macos/README.md)** — the Swift package at a glance.
- **[core/README.md](core/README.md)** — the Rust workspace at a glance.
- **[shared/README.md](shared/README.md)** — contracts, fixtures, goldens conventions.
- **[platform/README.md](platform/README.md)** — where per-OS code goes.
- **[tooling/README.md](tooling/README.md)** — builds, gates, dev CLIs, release scripts.
