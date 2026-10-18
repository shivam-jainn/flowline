# core/ — Rust workspace (portable core, source of truth for logic)

```
core/
  Cargo.toml              — workspace (members = crates/*, _template excluded)
  crates/
    flowline_ir            — session/events/manifest types + JSON
    flowline_pipeline      — debounce / classify / aggregate / redact / step factory
    flowline_engine        — reducer / state / step gate / enrichment / clips
    flowline_storage       — schema / serialize / migrate
    flowline_ai_gateway    — prompts + multimodal payload builder
    flowline_projections   — markdown / python / js / shell / mcp exporters
    flowline_win_capture   — Windows driver (hooks / inspector / plugin manifest)
    flowline_ffi           — UniFFI + WASM surface over the core (cdylib)
    parity_harness       — shared golden-fixture runner (reads shared/goldens/)
    _template/           — crate scaffold (excluded from workspace)
```

`rust-toolchain.toml` lives at the repo root (pins stable + wasm32 target;
applies to this workspace by ancestor lookup).

Boundaries:

- `unsafe_code = forbid` at the workspace level. No `unsafe` anywhere.
- Each crate has `tests/parity.rs` running the goldens both suites share
  (`shared/goldens/`, schemas in `shared/contracts/`).
- Swift twins in `platform/macos/Sources/` delegate to this core via `FlowlineFFI`
  (UniFFI). Do not fork logic — port it here and delete the twin at parity.
- `flowline_ffi` is the only crate with foreign interfaces (UniFFI/WASM).
  Platform capture stays in `platform/macos/Sources/FlowlineMacCapture` (Swift/macOS)
  and `flowline_win_capture` (Rust/Windows).
- Commands (run from repo root): `make check-rust`, or
  `cargo test --workspace --locked` + `cargo clippy --workspace --all-targets -- --deny warnings`
  with `--manifest-path core/Cargo.toml` (or `cd core/` first).
