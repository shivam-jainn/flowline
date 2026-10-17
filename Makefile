# StepIt root task runner (turbo equivalent for this Swift+Rust monolith).
#
#   platform/macos   SwiftPM package — everything Swift (app, modules, tests)
#   core/          Cargo workspace — portable Rust core (source of truth)
#   shared/        Language-agnostic contracts, fixtures, goldens
#   tooling/       Builds + gates (ci, toolchain, dev, release)
#
# Run `make` for the default target (build).
.PHONY: all build test ffi check-arch check-rust check-wasm check-phase-r serve demo automate bundle dmg clean test-dev run sign-setup

SWIFT_PKG := platform/macos
RUST_MANIFEST := core/Cargo.toml

all: build

# Rebuilds the Rust FFI artifacts SwiftPM needs (xcframework + UniFFI
# bindings; both gitignored under platform/macos/Generated). Required before
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

# One-time: creates the persistent "StepIt Local Dev" signing identity so
# rebuilds keep TCC grants. Run once, grant permissions once, then rebuilds
# stop wiping them.
sign-setup:
	tooling/release/ensure_local_signing_identity.sh

dmg:
	tooling/release/create_dmg.sh

clean:
	rm -rf $(SWIFT_PKG)/.build core/target dist

# Stale-proof manual test loop: kills any running StepIt menu-bar instance,
# forces a fresh StepIt.app bundle (never reuses the cached .build output),
# then launches it and prints PID/start time so you can confirm it's fresh.
test-dev:
	killall StepIt 2>/dev/null || true
	pkill -f "StepIt.app" 2>/dev/null || true
	sleep 1
	rm -rf $(SWIFT_PKG)/.build/StepIt.app
	tooling/release/bundle_app.sh
	ls -l $(SWIFT_PKG)/.build/StepIt.app/Contents/MacOS/StepIt
	shasum $(SWIFT_PKG)/.build/StepIt.app/Contents/MacOS/StepIt
	open $(SWIFT_PKG)/.build/StepIt.app
	sleep 1
	ps -o pid,lstart,command -p $$(pgrep -x StepIt | head -1) || true

# Relaunch the EXISTING bundle without rebuilding. Use this after granting
# permissions: ad-hoc signatures change on every rebuild, which makes macOS
# drop Screen Recording / Accessibility grants. `test-dev` rebuilds (grant
# invalid); `run` preserves the binary (grant survives).
run:
	killall StepIt 2>/dev/null || true
	pkill -f "StepIt.app" 2>/dev/null || true
	sleep 1
	test -d $(SWIFT_PKG)/.build/StepIt.app || tooling/release/bundle_app.sh
	open $(SWIFT_PKG)/.build/StepIt.app
	sleep 1
	ps -o pid,lstart,command -p $$(pgrep -x StepIt | head -1) || true
