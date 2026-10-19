#!/usr/bin/env bash
# P0-01 RTL smoke: lint, normal run, and three negative probes.
# Every expected failure is checked for both a non-zero exit code and a
# specific message; arbitrary failures still fail the script.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/rtl-smoke"
LOG_DIR="$ROOT/verification/evidence/P0-01/logs"
VERILATOR="${VERILATOR:-verilator}"
CXXFLAGS="-std=c++17"
mkdir -p "$BUILD" "$LOG_DIR"

fail=0
pass() { printf 'P0-01_RTL_STEP_PASS: %s\n' "$*"; }
bad() { printf 'P0-01_RTL_STEP_FAIL: %s\n' "$*" >&2; fail=1; }

lint() {
  local log="$LOG_DIR/lint-smoke.log"
  printf '== lint ==\n'
  {
    printf 'command: %s --lint-only -Wall --assert --top-module smoke_buffer verification/smoke/rtl/smoke_buffer.sv\n' "$VERILATOR"
    "$VERILATOR" --lint-only -Wall --assert --top-module smoke_buffer \
      "$ROOT/verification/smoke/rtl/smoke_buffer.sv" 2>&1
    printf 'exit: %s\n' "$?"
    printf 'command: %s --lint-only -Wall --assert --top-module assert_probe verification/smoke/rtl/assert_probe.sv\n' "$VERILATOR"
    "$VERILATOR" --lint-only -Wall --assert --top-module assert_probe \
      "$ROOT/verification/smoke/rtl/assert_probe.sv" 2>&1
    printf 'exit: %s\n' "$?"
  } >"$log" 2>&1
  if grep -q '^exit: 0$' "$log" && [ "$(grep -c '^exit: 0$' "$log")" -eq 2 ]; then
    pass "lint (log: verification/evidence/P0-01/logs/lint-smoke.log)"
  else
    bad "lint (see verification/evidence/P0-01/logs/lint-smoke.log)"
  fi
}

build_sim() {
  local top="$1" tb="$2" out="$3" log="$4"
  rm -rf "$BUILD/$out"
  mkdir -p "$BUILD/$out/obj"
  {
    printf 'command: %s --cc --exe --build --assert --top-module %s -Mdir %s/%s/obj -CFLAGS %s verification/smoke/rtl/%s.sv %s -o %s\n' \
      "$VERILATOR" "$top" "$BUILD" "$out" "$CXXFLAGS" "$top" "$tb" "$out"
    "$VERILATOR" --cc --exe --build --assert --top-module "$top" \
      -Mdir "$BUILD/$out/obj" -CFLAGS "$CXXFLAGS" \
      "$ROOT/verification/smoke/rtl/$top.sv" "$ROOT/$tb" -o "$out" 2>&1
    printf 'exit: %s\n' "$?"
  } >"$log" 2>&1
  [ -x "$BUILD/$out/obj/$out" ]
}

run_case() {
  local name="$1" expect_rc="$2" expect_msg="$3"
  shift 3
  local log="$LOG_DIR/$name.log"
  {
    printf 'command: %s\n' "$*"
    "$@" 2>&1
    printf 'exit: %s\n' "$?"
  } >"$log" 2>&1
  local rc
  rc="$(awk -F': ' '/^exit: / {v=$2} END {print v}' "$log")"
  if [ "$rc" = "$expect_rc" ] && grep -qF "$expect_msg" "$log"; then
    pass "$name (exit=$rc, expected message present)"
  else
    bad "$name (exit=$rc, expected exit=$expect_rc, message '$expect_msg'; see verification/evidence/P0-01/logs/$name.log)"
  fi
}

lint

if [ "${1:-}" = "--lint-only" ]; then
  if [ "$fail" -eq 0 ]; then
    printf 'P0-01_LINT_ALL_PASS\n'
    exit 0
  fi
  printf 'P0-01_LINT_ALL_FAIL\n' >&2
  exit 1
fi

if ! build_sim smoke_buffer verification/smoke/rtl/tb_smoke.cpp smoke_sim "$LOG_DIR/build-smoke.log"; then
  bad "build smoke_buffer simulator (see verification/evidence/P0-01/logs/build-smoke.log)"
else
  pass "build smoke_buffer simulator"
fi

if ! build_sim assert_probe verification/smoke/rtl/tb_assert_probe.cpp probe_sim "$LOG_DIR/build-probe.log"; then
  bad "build assertion probe simulator (see verification/evidence/P0-01/logs/build-probe.log)"
else
  pass "build assertion probe simulator"
fi

if [ -x "$BUILD/smoke_sim/obj/smoke_sim" ]; then
  run_case normal-rtl 0 "P0-01_RTL_SMOKE_PASS" \
    "$BUILD/smoke_sim/obj/smoke_sim"
  run_case checker-probe 1 "P0-01_CHECKER_PROBE_DETECTED" \
    "$BUILD/smoke_sim/obj/smoke_sim" +checker_probe
  run_case timeout-probe 1 "P0-01_TIMEOUT" \
    "$BUILD/smoke_sim/obj/smoke_sim" +hang +max_cycles=100
  run_case host-timeout-probe 124 "P0-01_TIMEOUT_PROBE" \
    timeout 5s "$BUILD/smoke_sim/obj/smoke_sim" +hang +no_cycle_limit
fi

if [ -x "$BUILD/probe_sim/obj/probe_sim" ]; then
  run_case assertion-probe 134 "P0-01_NEGATIVE_PROBE_ASSERTION_FIRED" \
    "$BUILD/probe_sim/obj/probe_sim"
fi

if [ "$fail" -eq 0 ]; then
  printf 'P0-01_RTL_SMOKE_ALL_PASS\n'
  exit 0
fi
printf 'P0-01_RTL_SMOKE_ALL_FAIL\n' >&2
exit 1
