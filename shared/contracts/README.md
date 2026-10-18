# shared/contracts — common types as JSON Schema

The single source of truth for every shape that crosses the Swift/Rust
boundary. Both implementations exist to satisfy these files:

| Schema | Swift | Rust | Golden |
| ------ | ----- | ---- | ------ |
| `step-session.schema.json` | `FlowlineIR.StepSession` / `Step` | `flowline_ir::session` | `shared/goldens/session.sample.json` |
| `segmentation-eval.schema.json` | — (Rust-only eval) | `parity_harness::segmentation` | `shared/goldens/segmentation.*.json` |
| `raw-input-event.schema.json` | `FlowlineIR.RawInputEvent` | `flowline_ir::events` | `shared/goldens/events.sample.json(.jsonl)` |
| `plugin-manifest.schema.json` | `FlowlineIR.PluginManifest` | `flowline_ir::manifest` | `shared/goldens/manifest.sample.json` |

Wire rules both sides follow: camelCase keys, RFC 3339 date-time strings,
`kind` as a single-key tagged object, optional fields nullable-or-absent.

Changing a contract means updating Swift + Rust + goldens in the same commit.
