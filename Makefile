# Flowline root task runner (turbo equivalent for this Swift+Rust monolith).
#
#   platform/macos   SwiftPM package — everything Swift (app, modules, tests)
#   core/          Cargo workspace — portable Rust core (source of truth)
#   shared/        Language-agnostic contracts, fixtures, goldens
#   tooling/       Builds + gates (ci, toolchain, dev, release)
#
# Run `make` for the default target (build).
.PHONY: all build test ffi check-arch check-rust check-wasm check-phase-r check-seg serve demo automate bundle dmg clean test-dev dev dev-debug run sign-setup doctor reset-tcc

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

check-seg:
	tooling/ci/check_segmentation.sh

serve:
	swift run --package-path $(SWIFT_PKG) flowline serve

demo:
	swift run --package-path $(SWIFT_PKG) flowline demo

automate:
	swift run --package-path $(SWIFT_PKG) flowline automate

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

# Stale-proof manual test loop: kills any running Flowline menu-bar instance,
# forces a fresh release Flowline.app bundle (never reuses the cached .build
# output), then launches it and prints PID/start time so you can confirm
# it's fresh. Needs re-granting TCC afterwards unless signed with an
# Apple-issued identity (see sign-setup).
test-dev:
	pkill -x Flowline 2>/dev/null || true
	sleep 1
	rm -rf $(SWIFT_PKG)/.build/Flowline.app
	tooling/release/bundle_app.sh
	ls -l $(SWIFT_PKG)/.build/Flowline.app/Contents/MacOS/Flowline
	shasum $(SWIFT_PKG)/.build/Flowline.app/Contents/MacOS/Flowline
	open $(SWIFT_PKG)/.build/Flowline.app
	sleep 1
	ps -o pid,lstart,command -p $$(pgrep -x Flowline | head -1) || true

# Fast dev loop — the closest thing to hot reload for a TCC-gated recorder:
# incremental DEBUG build (seconds after the first one), re-bundle, relaunch.
# No clean, no release optimization, no shasum noise. A relaunch is always
# required anyway (macOS applies Screen Recording only to fresh processes),
# so edit → make dev → test is the whole cycle.
dev:
	pkill -x Flowline 2>/dev/null || true
	sleep 1
	CONFIG=debug tooling/release/bundle_app.sh
	open $(SWIFT_PKG)/.build/Flowline.app

# Perf-capture loop for gutter DnD jitter: you drag, it captures.
# Builds DEBUG, enables FlowlinePerfLogging, streams the unified log
# (subsystem com.flowline.app) to docs/traces/<stamp>-gutter.log.
# Ctrl-C stops + prints begins/flips/drops/nudges + resolve p50/p95/max.
#   make dev-debug [DURATION=60] [TRACE=1]
dev-debug:
	tooling/dev/dev-debug.sh

# Relaunch the EXISTING bundle without rebuilding. Use this after granting
# permissions: any rebuild re-signs the binary, and without an Apple-issued
# identity macOS drops Screen Recording / Accessibility grants on re-sign.
run:
	pkill -x Flowline 2>/dev/null || true
	sleep 1
	test -d $(SWIFT_PKG)/.build/Flowline.app || tooling/release/bundle_app.sh
	open $(SWIFT_PKG)/.build/Flowline.app
	sleep 1
	ps -o pid,lstart,command -p $$(pgrep -x Flowline | head -1) || true

# Nuclear option for scrambled TCC state (stale/duplicate entries): wipes both
# grants for OUR bundle id only, then relaunch and grant once on the current
# binary. Note this INCREASES Settings trips — it never reduces them.
reset-tcc:
	tccutil reset ScreenCapture com.flowline.macos
	tccutil reset Accessibility com.flowline.macos

# One-shot diagnosis for "permissions show granted but the app says denied":
# binary hash vs running process, signing identity, team cert. The classic
# trap: Settings still shows the toggle ON for a binary hash macOS no longer
# recognizes (any ad-hoc rebuild), while CGPreflight/AXIsProcessTrusted
# correctly report denied for the CURRENT binary.
doctor:
	@echo "— Flowline doctor —"
	@echo "binary:  $$(stat -f '%Sm' $(SWIFT_PKG)/.build/Flowline.app/Contents/MacOS/Flowline 2>/dev/null || echo MISSING)  hash=$$(shasum $(SWIFT_PKG)/.build/Flowline.app/Contents/MacOS/Flowline 2>/dev/null | cut -c1-12 || echo none)"
	@pgrep -x Flowline >/dev/null && ps -o pid,lstart -p $$(pgrep -x Flowline | head -1) || echo "running: no Flowline process"
	@echo "signing: $$(codesign -dv $(SWIFT_PKG)/.build/Flowline.app 2>&1 | grep -E 'flags|TeamIdentifier' | tr '\n' ' ')"
	@echo "DR:      $$(codesign -dr - $(SWIFT_PKG)/.build/Flowline.app 2>&1 | tail -1)"
	@TEAM=$$(codesign -dv $(SWIFT_PKG)/.build/Flowline.app 2>&1 | sed -n 's/^TeamIdentifier=//p'); DR=$$(codesign -dr - $(SWIFT_PKG)/.build/Flowline.app 2>&1 | tail -1); if [ "$$TEAM" != "not set" ] && [ -n "$$TEAM" ]; then echo "grant stability: STABLE ($$TEAM) — rebuilds keep grants"; elif echo "$$DR" | grep -q "certificate root"; then echo "grant stability: DR-STABLE (local self-signed — better than ad-hoc, not TeamID-guaranteed; make sign-setup for the Apple-cert fix)"; else echo "grant stability: AD-HOC — dies on every rebuild (make sign-setup ends this)"; fi
	@security find-identity -v -p codesigning 2>/dev/null | grep -qE "Apple Development|Mac Developer" && echo "team cert: YES (rebuilds keep grants)" || (security find-certificate -c "Flowline Development" >/dev/null 2>&1 && echo "team cert: LOCAL-ONLY (DR-stable fallback — run: make sign-setup for guaranteed stability)" || echo "team cert: NONE (every rebuild kills grants — run: make sign-setup)")
	@echo "rule: grant in Settings must happen for THIS binary hash, then relaunch WITHOUT rebuilding (make run)."
	@echo "note: 'flowline status' from a terminal reflects the TERMINAL context — the in-app window is the real verdict."
