#!/usr/bin/env bash
# P0-01-R1 fault-injection probes.
#
# Each probe deliberately breaks one normal path and requires the runner or the
# total entry to fail in bounded time with the expected watchdog/build message.
# A probe passes only when the real command returns non-zero for the expected
# reason; the outer timeout exists only to catch a broken watchdog.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${P0_01_R1_PROBE_DIR:-$ROOT/verification/evidence/P0-01-R1/probes}"
OUTER_TIMEOUT="${P0_01_R1_OUTER_TIMEOUT:-120}"
mkdir -p "$BASE"

fail=0
pass() { printf 'P0-01_R1_PROBE_PASS: %s\n' "$*"; }
bad() { printf 'P0-01_R1_PROBE_FAIL: %s\n' "$*" >&2; fail=1; }

run_probe() {
  local name="$1" pattern="$2"
  shift 2
  local log="$BASE/$name/run.log"
  local rc start end elapsed
  mkdir -p "$BASE/$name"
  start="$(date +%s)"
  {
    printf 'outer_command: timeout -k 5s %ss %s\n' "$OUTER_TIMEOUT" "$*"
    timeout -k 5s "${OUTER_TIMEOUT}s" "$@" 2>&1
    rc=$?
    end="$(date +%s)"
    elapsed=$((end - start))
    printf 'outer_exit: %s\n' "$rc"
    printf 'elapsed_seconds: %s\n' "$elapsed"
  } >"$log" 2>&1

  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    bad "$name: outer timeout fired; the normal runner did not terminate via its own watchdog (log: ${log#"$ROOT"/})"
    return
  fi
  if [ "$rc" -eq 0 ]; then
    bad "$name: expected non-zero, got 0 (log: ${log#"$ROOT"/})"
    return
  fi
  if ! grep -qF "$pattern" "$log"; then
    bad "$name: missing expected pattern '$pattern' (log: ${log#"$ROOT"/})"
    return
  fi
  pass "$name (outer_exit=$rc, elapsed=${elapsed}s, pattern='$pattern')"
}

# Ensure the simulator exists so the scoreboard probe is self-contained.
SIM="$ROOT/build/rtl-smoke/smoke_sim/obj/smoke_sim"
if [ ! -x "$SIM" ]; then
  P0_01_LOG_DIR="$BASE/prereq/logs" "$ROOT/scripts/run_rtl_smoke.sh" \
    >"$BASE/prereq-run.log" 2>&1
  if [ ! -x "$SIM" ]; then
    bad "cannot build simulator for scoreboard probe (see ${BASE#"$ROOT"/}/prereq-run.log)"
  fi
fi

# V02a: normal RTL simulation hangs; runner watchdog must terminate it.
run_probe rtl-normal-hang "P0-01_WATCHDOG_TIMEOUT" \
  env P0_01_NORMAL_HANG=1 P0_01_NORMAL_TIMEOUT=2 \
  P0_01_LOG_DIR="$BASE/rtl-normal-hang/logs" \
  "$ROOT/scripts/run_rtl_smoke.sh"

# V02b: same hang through the total entry; it must return non-zero, bounded.
run_probe total-entry-rtl-hang "result: FAIL" \
  env P0_01_NORMAL_HANG=1 P0_01_NORMAL_TIMEOUT=2 P0_01_STEP_TIMEOUT=60 \
  P0_01_LOG_DIR="$BASE/total-entry-rtl-hang/logs" \
  "$ROOT/scripts/check_p0_01.sh"

# V02c: Spike normal path hangs; runner watchdog must terminate it.
run_probe spike-normal-hang "P0-01_WATCHDOG_TIMEOUT" \
  env P0_01_SPIKE_NORMAL_HANG=1 P0_01_SPIKE_NORMAL_TIMEOUT=2 \
  P0_01_LOG_DIR="$BASE/spike-normal-hang/logs" \
  "$ROOT/scripts/run_ref_smoke.sh"

# V03: observation command never reaches its target; watchdog must terminate it.
run_probe observe-hang "P0-01_WATCHDOG_TIMEOUT" \
  env P0_01_OBSERVE_HANG=1 P0_01_OBSERVE_TIMEOUT=2 \
  P0_01_LOG_DIR="$BASE/observe-hang/logs" \
  "$ROOT/scripts/run_ref_smoke.sh"

# V04a: build tool returns non-zero although the binary was produced.
run_probe build-fault-runner "P0-01_BUILD_FAIL" \
  env P0_01_BUILD_FAULT=1 P0_01_LOG_DIR="$BASE/build-fault-runner/logs" \
  "$ROOT/scripts/run_rtl_smoke.sh"
if grep -q '^exit: 3$' "$BASE/build-fault-runner/logs/build-smoke.log" 2>/dev/null; then
  pass "build-fault-runner recorded real build exit=3"
else
  bad "build-fault-runner did not record build exit=3"
fi
if [ -x "$ROOT/build/rtl-smoke/smoke_sim/obj/smoke_sim" ]; then
  pass "build-fault-runner produced a binary despite the non-zero build status"
else
  bad "build-fault-runner binary missing; cannot prove 'binary exists but build failed'"
fi

# V04b: build fault must propagate to the total entry.
run_probe total-entry-build-fault "result: FAIL" \
  env P0_01_BUILD_FAULT=1 P0_01_STEP_TIMEOUT=60 \
  P0_01_LOG_DIR="$BASE/total-entry-build-fault/logs" \
  "$ROOT/scripts/check_p0_01.sh"
if grep -q 'P0-01_BUILD_FAIL' "$BASE/total-entry-build-fault/logs/rtl-smoke.log" 2>/dev/null; then
  pass "total-entry-build-fault propagated rtl-smoke build failure"
else
  bad "total-entry-build-fault missing rtl-smoke build failure evidence"
fi

# V05: the negative checker must fail inside the real independent queue
# comparison, reporting the got/expected pair it actually saw.
run_probe checker-scoreboard \
  "P0-01_SCOREBOARD_MISMATCH: output got 0x1111 expected 0xeeee" \
  env P0_01_LOG_DIR="$BASE/checker-scoreboard/logs" \
  "$SIM" +checker_probe

# No child process from the fault probes may survive.
leftovers="$(pgrep -f "$ROOT/build/rtl-smoke/smoke_sim/obj/smoke_sim" 2>/dev/null || true)"
if [ -n "$leftovers" ]; then
  bad "leftover RTL process(es) after probes: $leftovers"
else
  pass "no leftover RTL child process"
fi

if [ "$fail" -eq 0 ]; then
  printf 'P0-01_R1_PROBES_ALL_PASS\n'
  exit 0
fi
printf 'P0-01_R1_PROBES_ALL_FAIL\n' >&2
exit 1
