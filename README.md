# ⚡️ StepIt

> **Effortless step-by-step workflow capture & AI synthesis for macOS.**
> Native Swift. Privacy-first. Multi-provider AI Gateway. 1-click publishing to interactive web docs, print-ready PDFs, and Markdown.

StepIt records user workflows across any macOS app and turns them into human documentation
(interactive web site, PDF guide, Markdown) today — and machine-executable automation scripts
on the roadmap.

## Quick start

```bash
swift build                        # build the package (or `make build`)
swift test                         # run the test suite (or `make test`)
swift run stepit app               # launch the menu bar + floating HUD app
swift run stepit serve             # serve the 10-page fixture web app on :8080
swift run stepit demo              # build the demo guide from fixture captures
Scripts/ci/check_architecture.sh   # architecture & layout gate (or `make check-arch`)
```

Requirements: macOS 14+, Xcode 15+ toolchain (Swift 5.9+), and `DEVELOPER_DIR` pointed at a
full Xcode install when running `swift test` (Command Line Tools alone does not ship XCTest).

## Repository layout

```
docs/                Product & architecture documentation (PLAN.md, phase plans, research/)
Fixtures/            Fixture data for tests & demo tooling (playground-web, README)
Scripts/
  ci/                Boundary & layout gates
  dev/               Developer CLIs (taskctl, devpulse, fetch_cli)
  release/           App bundling, DMG creation, DMG artwork
Sources/
  StepIt/            macOS app (SwiftUI/AppKit) + CLI entry points
  StepItCore/        Portable domain core (engine, pipeline, driver SPI, publishing)
  StepItFixtures/    Fixture-driven demo tooling (WebKit page renderer, demo generators)
Tests/StepItTests/   Unit & integration tests (mirrors Sources/)
```

**Boundary rules:** `StepItCore` stays UI-free and platform-neutral outside `Drivers/macOS`;
`StepItFixtures` is the only home for fixture-driven tooling; `Fixtures/` is data, never compiled.
`Scripts/ci/check_architecture.sh` enforces the core rules on every change.

## Documentation

- **[docs/PLAN.md](docs/PLAN.md)** — vision, decoupled architecture, roadmap, and target layout.
- **[docs/roadmap.md](docs/roadmap.md)** — build order + exit gates (Phase 0 TDD framework first, then Phases 1–22).
- **[docs/phase1-plan.md](docs/phase1-plan.md)** — Phase 1 execution plan (driver SPI, `RecorderWorkflowEngine`, `MockCaptureDriver`).
- **[docs/phase6-plan.md](docs/phase6-plan.md)** — Phase 6 execution plan (view-layer post-recording UI rehaul on macOS Tahoe Liquid Glass; exporter/schema work merged into Phases 3–4).
- **[docs/data-line-plan.md](docs/data-line-plan.md)** — Phases 7–22 execution plan (data supply line for AI labs: capture policy, verification, QA, dataset packaging; one phase per domain).
- **[docs/research/README.md](docs/research/README.md)** — deep-dive research notes (architecture roadmap, capture & automation, market teardown).
- **[Fixtures/README.md](Fixtures/README.md)** — what the fixture tree is and how it is consumed.
