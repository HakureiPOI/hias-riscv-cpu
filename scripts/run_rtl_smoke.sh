#!/usr/bin/env bash
# P0-01 RTL smoke: lint, normal run, and negative probes.
# Every expected failure is checked for both a non-zero exit code and a
# specific message; arbitrary failures still fail the script.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/rtl-smoke"
LOG_DIR="${P0_01_LOG_DIR:-$ROOT/verification/evidence/P0-01-R1/logs}"
VERILATOR="${VERILATOR:-verilator}"
VERILATOR_BUILD="$VERILATOR"
CXXFLAGS="-std=c++17"

# shellcheck source=lib/watchdog.sh
. "$ROOT/scripts/lib/watchdog.sh"

if [ "${P0_01_BUILD_FAULT:-0}" = "1" ]; then
  VERILATOR_REAL="$(command -v "$VERILATOR")"
  export VERILATOR_REAL
  VERILATOR_BUILD="$ROOT/scripts/probes/verilator_build_fail.sh"
fi

if ! mkdir -p "$BUILD" "$LOG_DIR"; then
  printf 'P0-01_RTL_STEP_FAIL: cannot create build/log directories\n' >&2
  exit 1
fi

fail=0
pass() { printf 'P0-01_RTL_STEP_PASS: %s\n' "$*"; }
bad() { printf 'P0-01_RTL_STEP_FAIL: %s\n' "$*" >&2; fail=1; }

lint() {
  local log="$LOG_DIR/lint-smoke.log"
  local rc1 rc2
  printf '== lint ==\n'
  {
    printf '== smoke_buffer ==\n'
    printf 'command: timeout -k 5s %ss %s --lint-only -Wall --assert --top-module smoke_buffer verification/smoke/rtl/smoke_buffer.sv\n' \
      "$P0_01_HOST_TIMEOUT" "$VERILATOR"
    timeout -k 5s "${P0_01_HOST_TIMEOUT}s" "$VERILATOR" --lint-only -Wall --assert \
      --top-module smoke_buffer "$ROOT/verification/smoke/rtl/smoke_buffer.sv" 2>&1
    rc1=$?
    printf 'exit: %s\n' "$rc1"
    if [ "$rc1" -eq 124 ] || [ "$rc1" -eq 137 ]; then
      printf 'P0-01_WATCHDOG_TIMEOUT: host watchdog fired during smoke_buffer lint (exit=%s)\n' "$rc1"
    fi
    printf '== assert_probe ==\n'
    printf 'command: timeout -k 5s %ss %s --lint-only -Wall --assert --top-module assert_probe verification/smoke/rtl/assert_probe.sv\n' \
      "$P0_01_HOST_TIMEOUT" "$VERILATOR"
    timeout -k 5s "${P0_01_HOST_TIMEOUT}s" "$VERILATOR" --lint-only -Wall --assert \
      --top-module assert_probe "$ROOT/verification/smoke/rtl/assert_probe.sv" 2>&1
    rc2=$?
    printf 'exit: %s\n' "$rc2"
    if [ "$rc2" -eq 124 ] || [ "$rc2" -eq 137 ]; then
      printf 'P0-01_WATCHDOG_TIMEOUT: host watchdog fired during assert_probe lint (exit=%s)\n' "$rc2"
    fi
  } >"$log" 2>&1
  if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then
    pass "lint (log: ${log#"$ROOT"/})"
  else
    bad "lint (exit=$rc1/$rc2; see ${log#"$ROOT"/})"
  fi
}

build_sim() {
  local top="$1" tb="$2" out="$3" log="$4"
  local rc
  if ! rm -rf "$BUILD/$out"; then
    {
      printf 'command: rm -rf %s/%s\n' "$BUILD" "$out"
      printf 'exit: 1\n'
      printf 'P0-01_BUILD_FAIL: cleanup failed; refusing to reuse stale artifacts\n'
    } >"$log" 2>&1
    return 1
  fi
  if ! mkdir -p "$BUILD/$out/obj"; then
    {
      printf 'command: mkdir -p %s/%s/obj\n' "$BUILD" "$out"
      printf 'exit: 1\n'
      printf 'P0-01_BUILD_FAIL: cannot create build directory\n'
    } >"$log" 2>&1
    return 1
  fi
  {
    printf 'command: timeout -k 5s %ss %s --cc --exe --build --assert --top-module %s -Mdir %s/%s/obj -CFLAGS %s verification/smoke/rtl/%s.sv %s -o %s\n' \
      "$P0_01_HOST_TIMEOUT" "$VERILATOR_BUILD" "$top" "$BUILD" "$out" "$CXXFLAGS" "$top" "$tb" "$out"
    timeout -k 5s "${P0_01_HOST_TIMEOUT}s" "$VERILATOR_BUILD" --cc --exe --build --assert \
      --top-module "$top" -Mdir "$BUILD/$out/obj" -CFLAGS "$CXXFLAGS" \
      "$ROOT/verification/smoke/rtl/$top.sv" "$ROOT/$tb" -o "$out" 2>&1
    rc=$?
    printf 'exit: %s\n' "$rc"
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
      printf 'P0-01_WATCHDOG_TIMEOUT: host watchdog fired during build of %s (exit=%s)\n' "$top" "$rc"
    fi
  } >"$log" 2>&1
  if [ "$rc" -ne 0 ]; then
    printf 'P0-01_BUILD_FAIL: %s build returned exit=%s (log: %s)\n' \
      "$top" "$rc" "${log#"$ROOT"/}" >&2
    return 1
  fi
  if [ ! -x "$BUILD/$out/obj/$out" ]; then
    printf 'P0-01_BUILD_FAIL: %s returned 0 but artifact is missing (log: %s)\n' \
      "$top" "${log#"$ROOT"/}" >&2
    return 1
  fi
  return 0
}

# run_case <name> <expect_rc> <expect_msg> <timeout_s> <command...>
run_case() {
  local name="$1" expect_rc="$2" expect_msg="$3" tmo="$4"
  shift 4
  local log="$LOG_DIR/$name.log"
  local rc
  P0_01_HOST_TIMEOUT="$tmo" run_guarded "$log" "$@"
  rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    printf 'P0-01_WATCHDOG_TIMEOUT: %s exceeded %ss (exit=%s)\n' "$name" "$tmo" "$rc"
  fi
  if [ "$rc" = "$expect_rc" ] && grep -qF "$expect_msg" "$log"; then
    pass "$name (exit=$rc, expected message present)"
  else
    bad "$name (exit=$rc, expected exit=$expect_rc, message '$expect_msg'; see ${log#"$ROOT"/})"
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

build_smoke_ok=0
if ! build_sim smoke_buffer verification/smoke/rtl/tb_smoke.cpp smoke_sim "$LOG_DIR/build-smoke.log"; then
  bad "build smoke_buffer simulator (see ${LOG_DIR#"$ROOT"/}/build-smoke.log)"
else
  pass "build smoke_buffer simulator"
  build_smoke_ok=1
fi

build_probe_ok=0
if ! build_sim assert_probe verification/smoke/rtl/tb_assert_probe.cpp probe_sim "$LOG_DIR/build-probe.log"; then
  bad "build assertion probe simulator (see ${LOG_DIR#"$ROOT"/}/build-probe.log)"
else
  pass "build assertion probe simulator"
  build_probe_ok=1
fi

if [ "$build_smoke_ok" -eq 1 ] && [ -x "$BUILD/smoke_sim/obj/smoke_sim" ]; then
  normal_args=()
  if [ "${P0_01_NORMAL_HANG:-0}" = "1" ]; then
    normal_args=(+hang +no_cycle_limit)
  fi
  run_case normal-rtl 0 "P0-01_RTL_SMOKE_PASS" "${P0_01_NORMAL_TIMEOUT:-$P0_01_HOST_TIMEOUT}" \
    "$BUILD/smoke_sim/obj/smoke_sim" "${normal_args[@]}"
  run_case checker-probe 1 "P0-01_SCOREBOARD_MISMATCH" "$P0_01_HOST_TIMEOUT" \
    "$BUILD/smoke_sim/obj/smoke_sim" +checker_probe
  run_case timeout-probe 1 "P0-01_TIMEOUT" "$P0_01_HOST_TIMEOUT" \
    "$BUILD/smoke_sim/obj/smoke_sim" +hang +max_cycles=100
  run_case watchdog-rtl-probe 124 "P0-01_WATCHDOG_TIMEOUT" 2 \
    "$BUILD/smoke_sim/obj/smoke_sim" +hang +no_cycle_limit
fi

if [ "$build_probe_ok" -eq 1 ] && [ -x "$BUILD/probe_sim/obj/probe_sim" ]; then
  run_case assertion-probe 134 "P0-01_NEGATIVE_PROBE_ASSERTION_FIRED" \
    "$P0_01_HOST_TIMEOUT" "$BUILD/probe_sim/obj/probe_sim"
fi

if [ "$fail" -eq 0 ]; then
  printf 'P0-01_RTL_SMOKE_ALL_PASS\n'
  exit 0
fi
printf 'P0-01_RTL_SMOKE_ALL_FAIL\n' >&2
exit 1
