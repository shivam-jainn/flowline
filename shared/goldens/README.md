# shared/goldens — golden corpus (both suites assert here)

Moved from `core/goldens/` (ex-`Rust/goldens/`). Language-neutral test data:
Rust loads it via `parity_harness::load_golden`, Swift via the DataLine
support helpers. Canonical form is sorted-keys compact JSON.

Files: session, events (.json + .jsonl), manifest, steps.factory, classify,
debounce, redaction, gateway.payload samples, plus the markdown projection.
The matching JSON Schemas live in `shared/contracts/`.

## `segmentation.*.json` — post-hoc repair eval (false cuts / false joins)

Seven self-contained eval cases for the coalesce (over-cut) + split
(over-join) passes (`flowline_pipeline::{coalesce,split,postpass}`,
`flowline_engine::postpass`) and the harness metrics
(`parity_harness::segmentation`). Schema:
`shared/contracts/segmentation-eval.schema.json`.

| Case | Failure reproduced | Expected repair |
| ---- | ------------------ | --------------- |
| `segmentation.think-pause` | Think-pause over-cut (1.8s pause, same field, revision overlap) | coalesce 2 → 1 (`coalesced:think-pause`) |
| `segmentation.cross-field-tab` | Cross-field fast Tab (300ms, different fields) | no merge (element gate) |
| `segmentation.rapid-clicks` | Rapid distinct clicks (150–200ms, distinct targets) | no merge (textless: 1 vote) |
| `segmentation.jitter-drag` | Jitter-drag on one slider (400ms apart) | no merge (textless: 1 vote) |
| `segmentation.cmd-tab-flap` | Cmd-Tab flap across bundles | no merge (bundle gate) |
| `segmentation.paste-burst` | Paste-burst over-cut (typed note + paste, clipboard chain) | coalesce 2 → 1 (superset wins) |
| `segmentation.terminal-multi` | Terminal multi-command over-join (606 chars, 3 prompts) | split 1 → 3 (`split:terminal-prompts`) |

Each file pins the reference segmentation, the pre-repair segmentation, the
input steps + raw-log evidence, the expected post-repair segmentation and
pass counts, and the metric baselines (`falseCutRate`, `falseJoinRate`, `f1`;
all `0/0/1` post-repair). The CI gate (`tooling/ci/check_segmentation.sh`)
fails on any +2pp regression vs these baselines. Metrics: `false_cut_rate`
(spurious cuts / predicted cuts), `false_join_rate` (missed cuts / true
cuts), boundary F1, plus Beeferman `Pk` and Pevzner–Hearst `WindowDiff`
(`k = round(mean ref length / 2)`). Non-text steps score as
`<action:element>` units (see `segment_text`).
