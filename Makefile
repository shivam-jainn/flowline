# StepIt root task runner (turbo equivalent for this Swift+Rust monolith).
#
#   apps/desktop   SwiftPM package — everything Swift (app, modules, tests)
#   core/          Cargo workspace — portable Rust core (source of truth)
#   shared/        Language-agnostic contracts, fixtures, goldens
#   tooling/       Builds + gates (ci, toolchain, dev, release)
#
# Run `make` for the default target (build).
.PHONY: all build test ffi check-arch check-rust check-wasm check-phase-r serve demo automate bundle dmg clean

SWIFT_PKG := apps/desktop
RUST_MANIFEST := core/Cargo.toml

all: build

# Rebuilds the Rust FFI artifacts SwiftPM needs (xcframework + UniFFI
# bindings; both gitignored under apps/desktop/Generated). Required before
# build/test on a clean checkout; CI runs this first.
ffi:
	tooling/toolchain/build-rust-ffi.sh

build: ffi
	swift build --package-path $(SWIFT_PKG)

test: ffi
	swift test --package-path $(SWIFT_PKG)

check-arch:
	tooling/ci/check_architecture.sh

check-rust:
	tooling/ci/check_rust.sh

check-wasm:
	tooling/ci/check_wasm.sh

check-phase-r:
	tooling/ci/check_phase_r.sh

serve:
	swift run --package-path $(SWIFT_PKG) stepit serve

demo:
	swift run --package-path $(SWIFT_PKG) stepit demo

automate:
	swift run --package-path $(SWIFT_PKG) stepit automate

bundle:
	tooling/release/bundle_app.sh

dmg:
	tooling/release/create_dmg.sh

clean:
	rm -rf $(SWIFT_PKG)/.build core/target dist
