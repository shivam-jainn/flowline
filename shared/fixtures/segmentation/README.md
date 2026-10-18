# Segmentation fixtures

Scenario index for the post-hoc repair eval (false cuts / false joins). The
machine-readable cases live in `../goldens/segmentation.*.json` (schema:
`../contracts/segmentation-eval.schema.json`); this folder documents which
real recording behavior each case reproduces and how to re-capture it.

| Case | Real behavior | How to reproduce in a recording |
| ---- | ------------- | ------------------------------- |
| `think-pause` | Pause mid-sentence while revising a note (debounce cuts one burst in two) | Type a sentence in Notes, pause ~2s, retype the corrected sentence |
| `cross-field-tab` | Fast Tab across form fields | Type a name, Tab within 300ms, type the email |
| `rapid-clicks` | Rapid clicks on distinct buttons | Click Save/Cancel/Apply ~150ms apart |
| `jitter-drag` | Pointer jitter on a slider (two micro-drags, not one gesture) | Wiggle the Music Volume slider twice, 400ms apart |
| `cmd-tab-flap` | Cmd-Tab flap Safari → Terminal → Safari | Cmd-Tab away and back within a second |
| `paste-burst` | Typed note followed by a pasted expansion in the same field | Type a stub, paste the full paragraph within a second |
| `terminal-multi` | Three commands submitted as one terminal batch | Run three long commands back-to-back in Ghostty/zsh |

Repair contract: the coalesce pass fixes over-cuts (`think-pause`,
`paste-burst`) only; the split pass fixes over-joins (`terminal-multi`) only;
the remaining four cases must pass through unchanged (negative guards against
false joins). CI: `tooling/ci/check_segmentation.sh` (`make check-seg`).
