#!/usr/bin/env bash
# make dev-debug — you run the app, we capture the numbers.
#
#   make dev-debug [DURATION=0] [TRACE=0]
#
# Builds the DEBUG bundle, turns on FlowlinePerfLogging, launches the app,
# and captures the unified log (subsystem com.flowline.app) to a
# timestamped file under docs/traces/. Ctrl-C stops capture + prints a
# summary. DURATION=N stops automatically after N seconds. TRACE=1 also
# takes an xctrace Time Profiler recording (needs Xcode CLI tools;
# skipped gracefully when unavailable).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TRACES_DIR="${ROOT_DIR}/docs/traces"
APP_DIR="${ROOT_DIR}/platform/macos/.build/Flowline.app"
DURATION="${DURATION:-0}"
WANT_TRACE="${TRACE:-0}"

mkdir -p "${TRACES_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${TRACES_DIR}/${STAMP}-gutter.log"
TRACE_FILE="${TRACES_DIR}/${STAMP}-gutter.trace"
SUMMARY_FILE="${TRACES_DIR}/${STAMP}-gutter-summary.txt"

summarize() {
    {
        echo "file: ${LOG_FILE}"
        echo "begins:  $(grep -c 'begin id=' "${LOG_FILE}" || true)"
        echo "flips:   $(grep -c 'target from=' "${LOG_FILE}" || true)"
        echo "drops:   $(grep -c 'dropped=true' "${LOG_FILE}" || true)"
        echo "nudges:  $(grep -c 'nudge dx=' "${LOG_FILE}" || true)"
        echo "resolves: $(grep -c 'resolve .*ms gaps=' "${LOG_FILE}" || true)"
        grep -o 'resolve [0-9.]*ms' "${LOG_FILE}" | grep -o '[0-9.]*' | sort -n | awk '{a[NR]=$1} END {if (NR>0) {printf "resolve p50: %.2fms  p95: %.2fms  max: %.2fms  n=%d\n", a[int(NR*0.5)+1], a[int(NR*0.95)+1], a[NR], NR} else {print "resolve p50/p95: no samples"}}'
        echo "slow resolves (>8ms): $(grep -o 'resolve [0-9.]*ms' "${LOG_FILE}" | grep -o '[0-9.]*' | awk '$1>8' | wc -l | tr -d ' ')"
    } | tee "${SUMMARY_FILE}"
    echo ""
    echo "done. paste this into your report:"
    echo "  log:     ${LOG_FILE}"
    echo "  summary: ${SUMMARY_FILE}"
}

echo "— Flowline dev-debug —"

# 1. Fresh DEBUG bundle (same path as `make dev`, no clean).
pkill -x Flowline 2>/dev/null || true
sleep 1
CONFIG=debug "${ROOT_DIR}/tooling/release/bundle_app.sh" >/dev/null
echo "bundle: ${APP_DIR}"

# 2. Enable perf logging for the app domain + launch arg belt-and-braces.
defaults write com.flowline.macos FlowlinePerfLogging -bool YES
echo "perf logging: ON (defaults com.flowline.macos FlowlinePerfLogging=YES)"
echo "log:    ${LOG_FILE}"

# 3. Start unified-log capture BEFORE launch so beginDrag isn't missed.
#    --info --debug needed: FlowPerfLog emits at .debug level.
log stream --predicate 'subsystem == "com.flowline.app"' --info --debug --style compact > "${LOG_FILE}" 2>&1 &
LOG_PID=$!
echo "capture pid: ${LOG_PID}"

stop_capture() {
    kill "${LOG_PID}" 2>/dev/null || true
    wait "${LOG_PID}" 2>/dev/null || true
    if [ -n "${TRACE_PID:-}" ]; then kill "${TRACE_PID}" 2>/dev/null || true; fi
}
trap 'stop_capture; summarize; exit 0' INT TERM

# 4. Launch. NOTE: the binary is a CLI multicall — bare flags are parsed
# as subcommands ("Unknown command" -> instant exit). The first arg MUST
# be `app` (main.swift: GUI iff argv[1] == "app" or no args); Cocoa still
# registers `-FlowlinePerfLogging YES` into NSUserDefaults either way.
open "${APP_DIR}" --args app -FlowlinePerfLogging YES
for i in 1 2 3 4 5; do
    APP_PID="$(pgrep -x Flowline | head -1 || true)"
    [ -n "${APP_PID}" ] && break
    sleep 1
done
if [ -z "${APP_PID:-}" ]; then
    echo "ERROR: Flowline did not start. Bundle binary check:"
    "${APP_DIR}/Contents/MacOS/Flowline" app -FlowlinePerfLogging YES 2>&1 | head -n 5 || true
    exit 1
fi
echo "app pid: ${APP_PID}"
echo "note: empty session store -> no window on launch (Dock icon + menu remain)."
echo "      click the Dock icon or use File -> Start Recording; drags need a session with steps."
echo ""
echo "Do your drags now — 5 slow passes + 2 fast flicks + 1 edge-hold."
if [ "${DURATION}" != "0" ]; then
    echo "Auto-stopping after ${DURATION}s."
else
    echo "Then Ctrl-C here to stop + summarize."
fi

# 5. Optional Instruments trace (Time Profiler, attach by pid).
TRACE_PID=""
if [ "${WANT_TRACE}" = "1" ]; then
    if command -v xctrace >/dev/null 2>&1 && [ -n "${APP_PID}" ]; then
        echo "trace:  ${TRACE_FILE}"
        xctrace record --template 'Time Profiler' --output "${TRACE_FILE}" --attach "${APP_PID}" >/dev/null 2>&1 &
        TRACE_PID=$!
    else
        echo "trace:  SKIPPED (need xctrace + running app; GUI fallback: Product > Profile > SwiftUI)"
    fi
fi

# 6. Wait: fixed duration or until Ctrl-C (trap handles the latter).
if [ "${DURATION}" != "0" ]; then
    sleep "${DURATION}"
    stop_capture
    trap - INT TERM
    summarize
else
    while true; do sleep 86400; done
fi
