#!/usr/bin/env bash
# P1-B-R1 total entry: JAL anchor, decode units, default/forced-wrap frontend,
# normal/negative/injection probes, old-version reproduction, and P1-A/P0.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${P1_B_EVIDENCE:-$ROOT/verification/evidence/P1-B-R1}"
LOG_DIR="$BASE/logs"
INJECT_DIR="$BASE/injection"
BUILD="$ROOT/build/p1-b-r1"
VERILATOR="${VERILATOR:-verilator}"
HOST_TIMEOUT="${P1_B_HOST_TIMEOUT:-600}"
KILL_AFTER="${P1_B_KILL_AFTER:-5}"
INJECT="${P1_B_INJECT:-}"

if ! [[ "$HOST_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || ! [[ "$KILL_AFTER" =~ ^[1-9][0-9]*$ ]]; then
  printf 'P1-B-R1_CONFIG_ERROR: invalid host timeout/kill-after\n' >&2
  exit 2
fi
case "$INJECT" in
  ""|directed|random0) ;;
  *) printf 'P1-B-R1_CONFIG_ERROR: invalid P1_B_INJECT=%s\n' "$INJECT" >&2; exit 2 ;;
esac

mkdir -p "$LOG_DIR" "$INJECT_DIR" "$BUILD" || {
  printf 'P1-B-R1_STEP_FAIL: cannot create directories\n' >&2
  exit 1
}

fail=0
pass() { printf 'P1-B-R1_STEP_PASS: %s\n' "$*"; }
bad() { printf 'P1-B-R1_STEP_FAIL: %s\n' "$*" >&2; fail=1; }

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
    printf 'P1-B-R1_WATCHDOG_TIMEOUT: %s exceeded %ss (exit=%s)\n' \
      "$name" "$HOST_TIMEOUT" "$rc"
  fi
  return "$rc"
}

run_expected() {
  local name="$1" want_rc="$2" pattern="$3"; shift 3
  local log="$INJECT_DIR/$name.log"
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

# V01: lint production and integration wrapper.
if run_logged lint "$VERILATOR" --lint-only -Wall --assert \
     -I"$ROOT/rtl/include" --top-module p1_frontend_top -f "$ROOT/rtl/p1_b.f"; then
  pass "P1-B-R1 frontend lint"
else
  bad "P1-B-R1 frontend lint"
fi
if run_logged lint-tb "$VERILATOR" --lint-only -Wall --assert \
     -I"$ROOT/rtl/include" --top-module frontend_tb_top \
     "$ROOT/rtl/include/core_config_pkg.sv" "$ROOT/rtl/include/core_types_pkg.sv" \
     "$ROOT/rtl/soc/ram_128k.sv" "$ROOT/rtl/soc/ram_bridge.sv" \
     "$ROOT/rtl/frontend/p1_decode.sv" "$ROOT/rtl/frontend/p1_fetch.sv" \
     "$ROOT/rtl/frontend/p1_frontend_core.sv" \
     "$ROOT/verification/p1b/tb/frontend_tb_top.sv"; then
  pass "P1-B-R1 integration wrapper lint"
else
  bad "P1-B-R1 integration wrapper lint"
fi

# V01: locked toolchain anchor for JAL.
mkdir -p "$BUILD/jal"
if run_logged jal-anchor-as riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 \
     -o "$BUILD/jal/jal_anchor.o" "$ROOT/verification/p1b/spec/jal_anchor.s"; then
  if run_logged jal-anchor-objdump riscv64-unknown-elf-objdump -d -M no-aliases \
       "$BUILD/jal/jal_anchor.o"; then
    if run_logged jal-anchor-objcopy riscv64-unknown-elf-objcopy -O binary \
         "$BUILD/jal/jal_anchor.o" "$BUILD/jal/jal_anchor.bin"; then
      if run_logged jal-anchor-binary-objdump riscv64-unknown-elf-objdump -D \
           -b binary -m riscv:rv32 -M no-aliases "$BUILD/jal/jal_anchor.bin"; then
        if grep -qF '000010ef' "$LOG_DIR/jal-anchor-binary-objdump.log" &&
           grep -qF '000012ef' "$LOG_DIR/jal-anchor-binary-objdump.log" &&
           grep -qF 'jal' "$LOG_DIR/jal-anchor-binary-objdump.log"; then
          pass "F01 JAL assembler/objdump anchor"
        else
          bad "F01 JAL anchor missing canonical words"
        fi
      else
        bad "F01 binary objdump failed"
      fi
    else
      bad "F01 objcopy failed"
    fi
  else
    bad "F01 assembler objdump failed"
  fi
else
  bad "F01 assembler failed"
fi

# V01: standalone decoder, 92 independent expectations + fixed JAL anchors.
rm -rf "$BUILD/decode"
mkdir -p "$BUILD/decode/obj"
if run_logged decode-build "$VERILATOR" --cc --exe --build --assert -Wall \
     -I"$ROOT/rtl/include" --top-module decode_tb_top \
     -Mdir "$BUILD/decode/obj" -CFLAGS -std=c++17 \
     "$ROOT/rtl/include/core_config_pkg.sv" "$ROOT/rtl/include/core_types_pkg.sv" \
     "$ROOT/rtl/frontend/p1_decode.sv" \
     "$ROOT/verification/p1b/tb/decode_tb_top.sv" \
     "$ROOT/verification/p1b/tb/tb_decode.cpp" -o decode_tb; then
  pass "decode unit build"
  if run_logged decode-run "$BUILD/decode/obj/decode_tb"; then
    if grep -qF 'P1-B_DECODE_PASS cases=92' "$LOG_DIR/decode-run.log"; then
      pass "decode units (92 independent expectations + JAL anchors)"
    else
      bad "decode unit missing PASS marker"
    fi
  else
    bad "decode unit run"
  fi
  run_expected decode-mismatch-probe 1 \
    "P1-B_DECODE_NEGATIVE_MISMATCH_DETECTED" \
    "$BUILD/decode/obj/decode_tb" +mismatch
else
  bad "decode unit build"
fi

build_frontend() {
  local tag="$1" gw="$2"; shift 2
  local dir="$BUILD/frontend-$tag"
  rm -rf "$dir"; mkdir -p "$dir/obj"
  run_logged "frontend-$tag-build" "$VERILATOR" --cc --exe --build --assert -Wall \
    -I"$ROOT/rtl/include" --top-module frontend_tb_top -GGEN_W="$gw" \
    -Mdir "$dir/obj" -CFLAGS "-std=c++17 -DP1B_GEN_W=$gw" \
    "$ROOT/rtl/include/core_config_pkg.sv" "$ROOT/rtl/include/core_types_pkg.sv" \
    "$ROOT/rtl/soc/ram_128k.sv" "$ROOT/rtl/soc/ram_bridge.sv" \
    "$ROOT/rtl/frontend/p1_decode.sv" "$ROOT/rtl/frontend/p1_fetch.sv" \
    "$ROOT/rtl/frontend/p1_frontend_core.sv" \
    "$ROOT/verification/p1b/tb/frontend_tb_top.sv" \
    "$ROOT/verification/p1b/tb/tb_frontend.cpp" -o frontend_tb
}

build_frontend default 8
build_frontend wrap 2

frontend_args=()
if [ "$INJECT" = "directed" ]; then frontend_args+=(+inject_directed); fi
if [ "$INJECT" = "random0" ]; then frontend_args+=(+inject_random0); fi

run_frontend() {
  local tag="$1" gw="$2"; shift 2
  local dir="$BUILD/frontend-$tag"
  if run_logged "frontend-$tag-run" "$dir/obj/frontend_tb" "$@"; then
    if grep -qF 'P1-B_FRONTEND_PASS' "$LOG_DIR/frontend-$tag-run.log" &&
       grep -qF "P1-B_FRONTEND_BASIC_PASS cases=92" "$LOG_DIR/frontend-$tag-run.log" &&
       grep -qF "P1-B_FRONTEND_WRAP_PASS gen_w=$gw" "$LOG_DIR/frontend-$tag-run.log" &&
       grep -qF 'P1-B_FRONTEND_RANDOM_PASS seeds=3 accepted=1020' \
         "$LOG_DIR/frontend-$tag-run.log"; then
      pass "integrated frontend $tag (image, wrap, redirects, 1020 accepts)"
    else
      bad "integrated frontend $tag missing required markers"
    fi
  else
    bad "integrated frontend $tag run (see ${LOG_DIR#"$ROOT"/}/frontend-$tag-run.log)"
  fi
}

if [ "${#frontend_args[@]}" -gt 0 ]; then
  run_frontend default 8 "${frontend_args[@]}"
else
  run_frontend default 8
fi
run_frontend wrap 2

# Expected-failure probes. These never turn into a successful total entry.
run_expected frontend-mismatch-probe 1 \
  "P1-B_FRONTEND_NEGATIVE_MISMATCH_DETECTED" \
  "$BUILD/frontend-default/obj/frontend_tb" +mismatch
run_expected frontend-inject-directed-probe 1 \
  "P1-B_FRONTEND_INJECTED_FAIL" \
  "$BUILD/frontend-default/obj/frontend_tb" +inject_directed
run_expected frontend-inject-random0-probe 1 \
  "P1-B_FRONTEND_INJECTED_FAIL" \
  "$BUILD/frontend-default/obj/frontend_tb" +inject_random0
run_expected frontend-timeout-probe 124 "P1-B_FRONTEND_TIMEOUT_PROBE" \
  timeout -k 2s 3s "$BUILD/frontend-default/obj/frontend_tb" +hang
run_expected frontend-timeout-ignore-term-probe 137 "P1-B_FRONTEND_TIMEOUT_PROBE" \
  timeout -k 2s 3s "$BUILD/frontend-default/obj/frontend_tb" +hang_ignore_term

# V02/V03: reproduce F01/F02/F03 on the original implementation.
if run_logged old-repro env \
     P1_B_R1_REPRO_EVIDENCE="$BASE/old-repro" \
     "$ROOT/scripts/repro_p1_b_r1.sh"; then
  if grep -qF 'P1-B-R1_OLD_REPRO_ALL_PASS' "$LOG_DIR/old-repro.log"; then
    pass "old-version F01/F02/F03 reproduction"
  else
    bad "old-version reproduction missing marker"
  fi
else
  bad "old-version F01/F02/F03 reproduction"
fi

# V04: keep P1-A (with nested P0) evidence under this round.
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
  bad "P1-A regression"
fi

{
  printf 'P1-B-R1 check summary\n'
  printf 'date_utc: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'git_head: %s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  printf 'git_branch: %s\n' "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  printf 'log_dir: %s\n' "${LOG_DIR#"$ROOT"/}"
  printf 'inject: %s\n' "${INJECT:-none}"
  printf 'git_status:\n'
  git -C "$ROOT" status --short | sed 's/^/  /'
  if [ "$fail" -eq 0 ]; then printf 'result: PASS\n'; else printf 'result: FAIL\n'; fi
} >"$LOG_DIR/summary.log"

cat "$LOG_DIR/summary.log"
if [ "$fail" -eq 0 ]; then printf 'P1-B-R1_CHECK_ALL_PASS\n'; exit 0; fi
printf 'P1-B-R1_CHECK_ALL_FAIL\n' >&2
exit 1
