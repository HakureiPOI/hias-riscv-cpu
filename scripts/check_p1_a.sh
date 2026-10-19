#!/usr/bin/env bash
# P1-A total entry: skeleton, RAM/bridge, token joint supplement, regression.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${P1_A_EVIDENCE:-$ROOT/verification/evidence/P1-A}"
LOG_DIR="$BASE/logs"
BUILD="$ROOT/build/p1-a"
VERILATOR="${VERILATOR:-verilator}"
STEP_TIMEOUT="${P1_A_STEP_TIMEOUT:-120}"

# shellcheck source=lib/watchdog.sh
. "$ROOT/scripts/lib/watchdog.sh"

mkdir -p "$LOG_DIR" "$BUILD" || {
  printf 'P1-A_STEP_FAIL: cannot create directories\n' >&2
  exit 1
}

fail=0
pass() { printf 'P1-A_STEP_PASS: %s\n' "$*"; }
bad() { printf 'P1-A_STEP_FAIL: %s\n' "$*" >&2; fail=1; }

run_logged() {
  local name="$1"; shift
  local log="$LOG_DIR/$name.log"
  local rc
  {
    printf 'command: timeout -k 5s %ss %s\n' "$STEP_TIMEOUT" "$*"
    timeout -k 5s "${STEP_TIMEOUT}s" "$@" 2>&1
    rc=$?
    printf 'exit: %s\n' "$rc"
  } >"$log" 2>&1
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    printf 'P1-A_WATCHDOG_TIMEOUT: %s exceeded %ss (exit=%s)\n' \
      "$name" "$STEP_TIMEOUT" "$rc"
  fi
  return "$rc"
}

run_expected() {
  local name="$1" want_rc="$2" pattern="$3"; shift 3
  local log="$LOG_DIR/$name.log"
  local rc
  {
    printf 'command: %s\n' "$*"
    "$@" 2>&1
    rc=$?
    printf 'exit: %s\n' "$rc"
  } >"$log" 2>&1
  if [ "$rc" != "$want_rc" ]; then
    bad "$name (exit=$rc, expected $want_rc; see ${log#"$ROOT"/})"
    return
  fi
  if ! grep -qF "$pattern" "$log"; then
    bad "$name missing expected message '$pattern' (see ${log#"$ROOT"/})"
    return
  fi
  pass "$name (exit=$rc, expected message present)"
}

# V01: lint the complete P1-A file list.
if run_logged lint "$VERILATOR" --lint-only -Wall --assert \
     -I"$ROOT/rtl/include" --top-module p1_soc_top -f "$ROOT/rtl/p1_a.f"; then
  pass "P1-A RTL lint"
else
  bad "P1-A RTL lint (see ${LOG_DIR#"$ROOT"/}/lint.log)"
fi

# V01: idle skeleton must not fabricate memory requests or retire/trap events.
rm -rf "$BUILD/soc"
mkdir -p "$BUILD/soc/obj"
if run_logged soc-build "$VERILATOR" --cc --exe --build --assert \
     -I"$ROOT/rtl/include" --top-module soc_idle_tb_top \
     -Mdir "$BUILD/soc/obj" -CFLAGS -std=c++17 \
     "$ROOT/rtl/include/core_config_pkg.sv" "$ROOT/rtl/include/core_types_pkg.sv" \
     "$ROOT/rtl/core/p1_core_skeleton.sv" "$ROOT/rtl/soc/ram_128k.sv" \
     "$ROOT/rtl/soc/ram_bridge.sv" "$ROOT/rtl/soc/p1_soc_top.sv" \
     "$ROOT/verification/p1a/tb/soc_idle_tb_top.sv" \
     "$ROOT/verification/p1a/tb/tb_soc_idle.cpp" -o soc_idle_tb; then
  pass "idle skeleton build"
  if run_logged soc-run "$BUILD/soc/obj/soc_idle_tb"; then
    if grep -q 'P1-A_CORE_IDLE_PASS' "$LOG_DIR/soc-run.log"; then
      pass "idle skeleton: no fake request/retire/trap"
    else
      bad "idle skeleton missing PASS marker"
    fi
  else
    bad "idle skeleton run (see ${LOG_DIR#"$ROOT"/}/soc-run.log)"
  fi
else
  bad "idle skeleton build (see ${LOG_DIR#"$ROOT"/}/soc-build.log)"
fi

# V02/V03: RAM and single-transaction bridge.
rm -rf "$BUILD/ram"
mkdir -p "$BUILD/ram/obj"
if run_logged ram-build "$VERILATOR" --cc --exe --build --assert \
     -I"$ROOT/rtl/include" --top-module ram_bridge_tb_top \
     -Mdir "$BUILD/ram/obj" -CFLAGS -std=c++17 \
     "$ROOT/rtl/include/core_config_pkg.sv" "$ROOT/rtl/include/core_types_pkg.sv" \
     "$ROOT/rtl/soc/ram_128k.sv" "$ROOT/rtl/soc/ram_bridge.sv" \
     "$ROOT/verification/p1a/tb/ram_bridge_tb_top.sv" \
     "$ROOT/verification/p1a/tb/tb_ram_bridge.cpp" -o ram_tb; then
  pass "RAM/bridge build"
  if run_logged ram-run "$BUILD/ram/obj/ram_tb"; then
    if grep -q 'P1-A_RAM_TB_PASS' "$LOG_DIR/ram-run.log"; then
      pass "RAM/bridge directed and seeded random tests"
    else
      bad "RAM/bridge missing PASS marker"
    fi
  else
    bad "RAM/bridge run (see ${LOG_DIR#"$ROOT"/}/ram-run.log)"
  fi
  run_expected ram-mismatch-probe 1 "P1-A_RAM_TB_NEGATIVE_MISMATCH_DETECTED" \
    "$BUILD/ram/obj/ram_tb" +mismatch
  run_expected ram-timeout-probe 124 "P1-A_RAM_TB_TIMEOUT_PROBE" \
    timeout 5s "$BUILD/ram/obj/ram_tb" +hang
else
  bad "RAM/bridge build (see ${LOG_DIR#"$ROOT"/}/ram-build.log)"
fi

# V03: cancelled token + generation wrap joint supplement.
rm -rf "$BUILD/token"
mkdir -p "$BUILD/token/obj"
if run_logged token-build "$VERILATOR" --cc --exe --build --assert \
     -I"$ROOT/rtl/include" --top-module interface_fixture \
     -Mdir "$BUILD/token/obj" -CFLAGS -std=c++17 \
     "$ROOT/verification/spec/interface/interface_fixture.sv" \
     "$ROOT/verification/p1a/tb/tb_token_joint.cpp" -o token_joint; then
  pass "token joint build"
  if run_logged token-run "$BUILD/token/obj/token_joint"; then
    if grep -q 'P1-A_TOKEN_JOINT_PASS' "$LOG_DIR/token-run.log"; then
      pass "cancelled token + wrap drain joint test"
    else
      bad "token joint missing PASS marker"
    fi
  else
    bad "token joint run (see ${LOG_DIR#"$ROOT"/}/token-run.log)"
  fi
else
  bad "token joint build (see ${LOG_DIR#"$ROOT"/}/token-build.log)"
fi

# V05: keep the frozen P0 regression, writing nested evidence under this round.
if run_logged regression-p0-02 env \
     P0_02_EVIDENCE="$BASE/regression/p0-02" \
     make -C "$ROOT" check-p0-02; then
  if grep -q 'P0-02_CHECK_ALL_PASS' "$LOG_DIR/regression-p0-02.log"; then
    pass "P0-02 regression (including P0-01/R1)"
  else
    bad "P0-02 regression missing PASS marker"
  fi
else
  bad "P0-02 regression (see ${LOG_DIR#"$ROOT"/}/regression-p0-02.log)"
fi

{
  printf 'P1-A check summary\n'
  printf 'date_utc: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'git_head: %s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  printf 'git_branch: %s\n' "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  printf 'log_dir: %s\n' "${LOG_DIR#"$ROOT"/}"
  printf 'git_status:\n'
  git -C "$ROOT" status --short | sed 's/^/  /'
  if [ "$fail" -eq 0 ]; then
    printf 'result: PASS\n'
  else
    printf 'result: FAIL\n'
  fi
} >"$LOG_DIR/summary.log"

cat "$LOG_DIR/summary.log"
if [ "$fail" -eq 0 ]; then
  printf 'P1-A_CHECK_ALL_PASS\n'
  exit 0
fi
printf 'P1-A_CHECK_ALL_FAIL\n' >&2
exit 1
