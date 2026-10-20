#!/usr/bin/env bash
# P1-B total entry: fetch/decode lint, decode unit, real RAM integration,
# controlled negative/timeout probes, and P1-A (including P0) regression.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${P1_B_EVIDENCE:-$ROOT/verification/evidence/P1-B}"
LOG_DIR="$BASE/logs"
BUILD="$ROOT/build/p1-b"
VERILATOR="${VERILATOR:-verilator}"
HOST_TIMEOUT="${P1_B_HOST_TIMEOUT:-600}"
KILL_AFTER="${P1_B_KILL_AFTER:-5}"

if ! [[ "$HOST_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || ! [[ "$KILL_AFTER" =~ ^[1-9][0-9]*$ ]]; then
  printf 'P1-B_CONFIG_ERROR: invalid host timeout/kill-after\n' >&2
  exit 2
fi

mkdir -p "$LOG_DIR" "$BUILD" || {
  printf 'P1-B_STEP_FAIL: cannot create directories\n' >&2
  exit 1
}

fail=0
pass() { printf 'P1-B_STEP_PASS: %s\n' "$*"; }
bad() { printf 'P1-B_STEP_FAIL: %s\n' "$*" >&2; fail=1; }

run_logged() {
  local name="$1"; shift
  local log="$LOG_DIR/$name.log"
  local rc
  {
    printf 'command: timeout -k %ss %ss %s\n' "$KILL_AFTER" "$HOST_TIMEOUT" "$*"
    timeout -k "${KILL_AFTER}s" "${HOST_TIMEOUT}s" "$@" 2>&1
    rc=$?
    printf 'exit: %s\n' "$rc"
  } >"$log" 2>&1
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    printf 'P1-B_WATCHDOG_TIMEOUT: %s exceeded %ss (exit=%s)\n' \
      "$name" "$HOST_TIMEOUT" "$rc"
  fi
  return "$rc"
}

run_expected() {
  local name="$1" want_rc="$2" pattern="$3"; shift 3
  local log="$LOG_DIR/$name.log"
  local rc start end elapsed
  start="$(date +%s)"
  {
    printf 'command: timeout -k %ss %ss %s\n' "$KILL_AFTER" "$HOST_TIMEOUT" "$*"
    timeout -k "${KILL_AFTER}s" "${HOST_TIMEOUT}s" "$@" 2>&1
    rc=$?
    end="$(date +%s)"
    elapsed=$((end - start))
    printf 'elapsed_seconds: %s\n' "$elapsed"
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
  pass "$name (exit=$rc, elapsed=${elapsed}s, expected message present)"
}

# V01: lint the production frontend file list and the integration wrapper.
if run_logged lint "$VERILATOR" --lint-only -Wall --assert \
     -I"$ROOT/rtl/include" --top-module p1_frontend_top -f "$ROOT/rtl/p1_b.f"; then
  pass "P1-B frontend lint"
else
  bad "P1-B frontend lint (see ${LOG_DIR#"$ROOT"/}/lint.log)"
fi
if run_logged lint-tb "$VERILATOR" --lint-only -Wall --assert \
     -I"$ROOT/rtl/include" --top-module frontend_tb_top \
     "$ROOT/rtl/include/core_config_pkg.sv" "$ROOT/rtl/include/core_types_pkg.sv" \
     "$ROOT/rtl/soc/ram_128k.sv" "$ROOT/rtl/soc/ram_bridge.sv" \
     "$ROOT/rtl/frontend/p1_decode.sv" "$ROOT/rtl/frontend/p1_fetch.sv" \
     "$ROOT/rtl/frontend/p1_frontend_core.sv" \
     "$ROOT/verification/p1b/tb/frontend_tb_top.sv"; then
  pass "P1-B integration wrapper lint"
else
  bad "P1-B integration wrapper lint (see ${LOG_DIR#"$ROOT"/}/lint-tb.log)"
fi

# V01: standalone decoder against the independent 76-case table.
rm -rf "$BUILD/decode"
mkdir -p "$BUILD/decode/obj"
if run_logged decode-build "$VERILATOR" --cc --exe --build --assert \
     -I"$ROOT/rtl/include" --top-module decode_tb_top \
     -Mdir "$BUILD/decode/obj" -CFLAGS -std=c++17 \
     "$ROOT/rtl/include/core_config_pkg.sv" "$ROOT/rtl/include/core_types_pkg.sv" \
     "$ROOT/rtl/frontend/p1_decode.sv" \
     "$ROOT/verification/p1b/tb/decode_tb_top.sv" \
     "$ROOT/verification/p1b/tb/tb_decode.cpp" -o decode_tb; then
  pass "decode unit build"
  if run_logged decode-run "$BUILD/decode/obj/decode_tb"; then
    if grep -qF 'P1-B_DECODE_PASS cases=76' "$LOG_DIR/decode-run.log"; then
      pass "decode units (76 independent expectations)"
    else
      bad "decode unit missing PASS marker"
    fi
  else
    bad "decode unit run (see ${LOG_DIR#"$ROOT"/}/decode-run.log)"
  fi
  run_expected decode-mismatch-probe 1 \
    "P1-B_DECODE_NEGATIVE_MISMATCH_DETECTED" \
    "$BUILD/decode/obj/decode_tb" +mismatch
else
  bad "decode unit build (see ${LOG_DIR#"$ROOT"/}/decode-build.log)"
fi

# V02/V03: integrated fetch/decode with the accepted RAM/bridge. GEN_W=2
# forces generation wrap within the 76-case image.
rm -rf "$BUILD/frontend"
mkdir -p "$BUILD/frontend/obj"
if run_logged frontend-build "$VERILATOR" --cc --exe --build --assert \
     -I"$ROOT/rtl/include" --top-module frontend_tb_top -GGEN_W=2 \
     -Mdir "$BUILD/frontend/obj" -CFLAGS "-std=c++17 -DP1B_GEN_W=2" \
     "$ROOT/rtl/include/core_config_pkg.sv" "$ROOT/rtl/include/core_types_pkg.sv" \
     "$ROOT/rtl/soc/ram_128k.sv" "$ROOT/rtl/soc/ram_bridge.sv" \
     "$ROOT/rtl/frontend/p1_decode.sv" "$ROOT/rtl/frontend/p1_fetch.sv" \
     "$ROOT/rtl/frontend/p1_frontend_core.sv" \
     "$ROOT/verification/p1b/tb/frontend_tb_top.sv" \
     "$ROOT/verification/p1b/tb/tb_frontend.cpp" -o frontend_tb; then
  pass "integrated frontend build"
  if run_logged frontend-run "$BUILD/frontend/obj/frontend_tb"; then
    if grep -qF 'P1-B_FRONTEND_PASS' "$LOG_DIR/frontend-run.log" &&
       grep -qF 'P1-B_FRONTEND_BASIC_PASS cases=76' "$LOG_DIR/frontend-run.log" &&
       grep -qF 'P1-B_FRONTEND_WRAP_PASS gen_w=2' "$LOG_DIR/frontend-run.log" &&
       grep -qF 'P1-B_FRONTEND_RANDOM_PASS seeds=3 accepted=1020' "$LOG_DIR/frontend-run.log"; then
      pass "integrated fetch/decode image, wrap, redirects and 1020 random accepts"
    else
      bad "integrated frontend missing required PASS markers"
    fi
  else
    bad "integrated frontend run (see ${LOG_DIR#"$ROOT"/}/frontend-run.log)"
  fi
  run_expected frontend-mismatch-probe 1 \
    "P1-B_FRONTEND_NEGATIVE_MISMATCH_DETECTED" \
    "$BUILD/frontend/obj/frontend_tb" +mismatch
  run_expected frontend-timeout-probe 124 "P1-B_FRONTEND_TIMEOUT_PROBE" \
    timeout -k 2s 3s "$BUILD/frontend/obj/frontend_tb" +hang
  run_expected frontend-timeout-ignore-term-probe 137 "P1-B_FRONTEND_TIMEOUT_PROBE" \
    timeout -k 2s 3s "$BUILD/frontend/obj/frontend_tb" +hang_ignore_term
else
  bad "integrated frontend build (see ${LOG_DIR#"$ROOT"/}/frontend-build.log)"
fi

# V05: keep P1-A (with nested P0) evidence under this round.
if run_logged regression-p1-a env \
     P1_A_EVIDENCE="$BASE/regression/P1-A" \
     P1_A_HOST_TIMEOUT="${P1_B_P1A_HOST_TIMEOUT:-600}" \
     make -C "$ROOT" check-p1-a; then
  if grep -qF 'P1-A_CHECK_ALL_PASS' "$LOG_DIR/regression-p1-a.log"; then
    pass "P1-A regression (including P0)"
  else
    bad "P1-A regression missing PASS marker"
  fi
else
  bad "P1-A regression (see ${LOG_DIR#"$ROOT"/}/regression-p1-a.log)"
fi

{
  printf 'P1-B check summary\n'
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
  printf 'P1-B_CHECK_ALL_PASS\n'
  exit 0
fi
printf 'P1-B_CHECK_ALL_FAIL\n' >&2
exit 1
