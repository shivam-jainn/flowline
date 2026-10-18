# shared/ — the shared packages (turborepo `packages/` equivalent)

Language-agnostic data both toolchains consume. No code here — only
contracts, fixtures, goldens, and brand assets. The arch gate (`tooling/ci/check_architecture.sh`,
rule 10) fails the build on any `.swift`/`.rs` under `shared/`.

```
shared/
  contracts/   JSON Schemas = the common types both implementations must honor.
               Swift (Codable) and Rust (serde) are independent implementations
               of these shapes; the schemas are the tiebreaker in any dispute.
  fixtures/    Deterministic fixture data (playground-web). Nothing compiled.
  goldens/     Golden corpus both suites assert against (parity_harness + Swift tests).
  assets/brand/ Canonical Share-menu brand marks (SVG + manifest.json).
               Single source of truth for logos inlined by the WebDoc HTML
               export. See assets/brand/README.md. SVG/data only — no code.
```

Rules:

- Schemas are versioned by the repo, not per language. Changing a schema
  means updating Swift + Rust + goldens together.
- Fixtures are append-mostly (file names and element IDs are test contracts).
- Goldens are byte-compare inputs: canonical JSON (sorted keys, compact).
  Regenerate deliberately, review the diff, never hand-edit to make red green.
