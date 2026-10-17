# shared/goldens — golden corpus (both suites assert here)

Moved from `core/goldens/` (ex-`Rust/goldens/`). Language-neutral test data:
Rust loads it via `parity_harness::load_golden`, Swift via the DataLine
support helpers. Canonical form is sorted-keys compact JSON.

Files: session, events (.json + .jsonl), manifest, steps.factory, classify,
debounce, redaction, gateway.payload samples, plus the markdown projection.
The matching JSON Schemas live in `shared/contracts/`.
