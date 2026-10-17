# Generated — UniFFI / XCFramework outputs (never committed)

Everything in this directory except this README and `.gitkeep` files is
rebuilt by `make ffi` (`tooling/toolchain/build-rust-ffi.sh`, run from the
repo root):

```
platform/macos/Generated/
  StepItFFI/stepit_ffi.swift            — uniffi-bindgen Swift bindings
  stepit_ffiFFI.xcframework/            — staticlib + headers for SwiftPM
  FFIHeaders/stepit_ffiFFI.h + module.modulemap — staging dir for xcodebuild
```

`platform/macos/Package.swift` consumes them as:

- `.binaryTarget(name: "stepit_ffiFFI", path: "Generated/stepit_ffiFFI.xcframework")`
- `.target(name: "StepItFFI", path: "Generated/StepItFFI")`

Fresh clone flow: `make build` (runs `ffi` first) — never bare `swift build`
on a clean checkout, or the binaryTarget path is missing.
`tooling/ci/check_phase_r.sh` always runs the FFI build first.
