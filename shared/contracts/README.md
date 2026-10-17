# shared/contracts — common types as JSON Schema

The single source of truth for every shape that crosses the Swift/Rust
boundary. Both implementations exist to satisfy these files:

| Schema | Swift | Rust | Golden |
| ------ | ----- | ---- | ------ |
| `step-session.schema.json` | `StepItIR.StepSession` / `Step` | `stepit_ir::session` | `shared/goldens/session.sample.json` |
| `raw-input-event.schema.json` | `StepItIR.RawInputEvent` | `stepit_ir::events` | `shared/goldens/events.sample.json(.jsonl)` |
| `plugin-manifest.schema.json` | `StepItIR.PluginManifest` | `stepit_ir::manifest` | `shared/goldens/manifest.sample.json` |

Wire rules both sides follow: camelCase keys, RFC 3339 date-time strings,
`kind` as a single-key tagged object, optional fields nullable-or-absent.

Changing a contract means updating Swift + Rust + goldens in the same commit.
