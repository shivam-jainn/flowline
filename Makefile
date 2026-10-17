# StepIt root task runner (turbo equivalent for this Swift+Rust monolith).
#
#   platform/macos   SwiftPM package — everything Swift (app, modules, tests)
#   core/          Cargo workspace — portable Rust core (source of truth)
#   shared/        Language-agnostic contracts, fixtures, goldens
#   tooling/       Builds + gates (ci, toolchain, dev, release)
#
# Run `make` for the default target (build).
.PHONY: all build test ffi check-arch check-rust check-wasm check-phase-r serve demo automate bundle dmg clean test-dev dev run sign-setup doctor

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

# One-time check: reports whether an Apple-issued development identity exists
# (the only signing that keeps TCC grants across rebuilds). Prints the free
# 2-minute Xcode setup when missing.
sign-setup:
	tooling/release/ensure_local_signing_identity.sh

dmg:
	tooling/release/create_dmg.sh

clean:
	rm -rf $(SWIFT_PKG)/.build core/target dist

# Stale-proof manual test loop: kills any running StepIt menu-bar instance,
# forces a fresh release StepIt.app bundle (never reuses the cached .build
# output), then launches it and prints PID/start time so you can confirm
# it's fresh. Needs re-granting TCC afterwards unless signed with an
# Apple-issued identity (see sign-setup).
test-dev:
	pkill -x StepIt 2>/dev/null || true
	sleep 1
	rm -rf $(SWIFT_PKG)/.build/StepIt.app
	tooling/release/bundle_app.sh
	ls -l $(SWIFT_PKG)/.build/StepIt.app/Contents/MacOS/StepIt
	shasum $(SWIFT_PKG)/.build/StepIt.app/Contents/MacOS/StepIt
	open $(SWIFT_PKG)/.build/StepIt.app
	sleep 1
	ps -o pid,lstart,command -p $$(pgrep -x StepIt | head -1) || true

# Fast dev loop — the closest thing to hot reload for a TCC-gated recorder:
# incremental DEBUG build (seconds after the first one), re-bundle, relaunch.
# No clean, no release optimization, no shasum noise. A relaunch is always
# required anyway (macOS applies Screen Recording only to fresh processes),
# so edit → make dev → test is the whole cycle.
dev:
	pkill -x StepIt 2>/dev/null || true
	sleep 1
	CONFIG=debug tooling/release/bundle_app.sh
	open $(SWIFT_PKG)/.build/StepIt.app

# Relaunch the EXISTING bundle without rebuilding. Use this after granting
# permissions: any rebuild re-signs the binary, and without an Apple-issued
# identity macOS drops Screen Recording / Accessibility grants on re-sign.
run:
	pkill -x StepIt 2>/dev/null || true
	sleep 1
	test -d $(SWIFT_PKG)/.build/StepIt.app || tooling/release/bundle_app.sh
	open $(SWIFT_PKG)/.build/StepIt.app
	sleep 1
	ps -o pid,lstart,command -p $$(pgrep -x StepIt | head -1) || true

# One-shot diagnosis for "permissions show granted but the app says denied":
# binary hash vs running process, signing identity, team cert. The classic
# trap: Settings still shows the toggle ON for a binary hash macOS no longer
# recognizes (any ad-hoc rebuild), while CGPreflight/AXIsProcessTrusted
# correctly report denied for the CURRENT binary.
doctor:
	@echo "— StepIt doctor —"
	@echo "binary:  $$(stat -f '%Sm' $(SWIFT_PKG)/.build/StepIt.app/Contents/MacOS/StepIt 2>/dev/null || echo MISSING)  hash=$$(shasum $(SWIFT_PKG)/.build/StepIt.app/Contents/MacOS/StepIt 2>/dev/null | cut -c1-12 || echo none)"
	@pgrep -x StepIt >/dev/null && ps -o pid,lstart -p $$(pgrep -x StepIt | head -1) || echo "running: no StepIt process"
	@echo "signing: $$(codesign -dv $(SWIFT_PKG)/.build/StepIt.app 2>&1 | grep -E 'flags|TeamIdentifier' | tr '\n' ' ')"
	@security find-identity -v -p codesigning 2>/dev/null | grep -qE "Apple Development|Mac Developer" && echo "team cert: YES (rebuilds keep grants)" || echo "team cert: NONE (every rebuild kills grants — run: make sign-setup)"
	@echo "rule: grant in Settings must happen for THIS binary hash, then relaunch WITHOUT rebuilding (make run)."
