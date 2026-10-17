# Fixtures

Fixture data for StepIt's tests and fixture-driven demo tooling. **Nothing in this
folder is product code** — it exists so the recorder, the WebKit renderer, and the
demo generators always have a deterministic, license-free UI to operate on.

## `playground-web/`

A self-contained, 10-page static web app ("StepIt Playground") covering the UI
surface the recorder needs to exercise:

| Page | Scenario |
| ---- | -------- |
| `index.html` | Landing / page directory |
| `page1_onboarding.html` | Auth & user onboarding |
| `page2_checkout.html` | E-commerce checkout |
| `page3_analytics.html` | Analytics dashboard |
| `page4_cloud.html` | Cloud server provisioning |
| `page5_media.html` | Audio & media studio |
| `page6_apigateway.html` | Developer API gateway |
| `page7_support.html` | Customer support portal |
| `page8_survey.html` | Product experience survey |
| `page9_datagrid.html` | Enterprise data grid |
| `page10_diagnostics.html` | System diagnostics & health |

Each page is pure HTML/CSS/JS (no build step, no external requests) and exposes
stable element IDs (`btn-submit-onboarding`, `btn-qty-plus-1`, …) that tests and
automation target.

## How it is consumed

- **`platform/macos/Sources/StepItFixtures/`** — `FixtureLocator` resolves this tree and
  `PlaygroundPageRenderer` renders pages offscreen via WebKit for automated
  captures. Lookup order: `STEPIT_FIXTURES_DIR` env var → walk up from the
  working directory → walk up from the source file → app bundle resources.
- **CLI** — `swift run stepit serve [port]` serves `playground-web/` over HTTP;
  `swift run stepit demo` and `swift run stepit automate` build demo sessions
  from these pages.
- **Tests** — `platform/macos/Tests/StepItTests/Fixtures/` and `platform/macos/Tests/StepItTests/StepItTests.swift`
  assert page integrity, DOM interaction, and full end-to-end sessions against
  this tree.

## Rules

- Fixtures are append-mostly: page file names and element IDs are part of the
  test contract, so renaming requires updating `FixtureLocator` consumers and the
  test vectors.
- Keep fixtures dependency-free (no CDNs, no fonts, no network) so tests run
  offline and deterministic.
