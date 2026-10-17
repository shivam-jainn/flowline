# StepIt developer entry points. Run `make` for the default target (build).
.PHONY: all build test check-arch ffi check-rust check-wasm check-phase-r serve demo automate bundle dmg clean

all: build

# Rebuilds the Rust FFI artifacts SwiftPM needs (xcframework + UniFFI
# bindings; both gitignored). Required before build/test on a clean
# checkout; CI (Scripts/ci/check_phase_r.sh) runs this first.
ffi:
	Scripts/build-rust-ffi.sh

build: ffi
	swift build

test: ffi
	swift test

check-arch:
	Scripts/ci/check_architecture.sh

check-rust:
	Scripts/ci/check_rust.sh

check-wasm:
	Scripts/ci/check_wasm.sh

check-phase-r:
	Scripts/ci/check_phase_r.sh

serve:
	swift run stepit serve

demo:
	swift run stepit demo

automate:
	swift run stepit automate

bundle:
	Scripts/release/bundle_app.sh

dmg:
	Scripts/release/create_dmg.sh

clean:
	rm -rf .build dist
