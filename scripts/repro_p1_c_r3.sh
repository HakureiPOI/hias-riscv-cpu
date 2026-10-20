#!/usr/bin/env bash
# Reproduce H01 on 3ed8ec9: earlier observed fault-cause error is masked by
# the initial_arf DETECTED early return.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${P1_C_R3_REPRO_EVIDENCE:-$ROOT/verification/evidence/P1-C-R3/old-repro}"
BUILD="$ROOT/build/p1-c-r3/old-repro"
OLD_COMMIT=3ed8ec9cc70a4145e08d3ebdda41dc805c98d9a7
TIMEOUT="${P1_C_R3_REPRO_TIMEOUT:-120}"
mkdir -p "$BASE" "$BUILD" || exit 1
rm -rf "$BUILD/obj"
BASE="$(cd "$BASE" && pwd)"
BUILD="$(cd "$BUILD" && pwd)"

run_logged() {
  local name="$1"; shift
  local log="$BASE/$name.log"
  local rc
  {
    printf 'command: timeout -k 5s %ss %s\n' "$TIMEOUT" "$*"
    timeout -k 5s "${TIMEOUT}s" "$@" 2>&1
    rc=$?
    printf 'exit: %s\n' "$rc"
  } >"$log" 2>&1
  return "$rc"
}

git -C "$ROOT" show "$OLD_COMMIT:verification/p1c/tb/tb_faults.cpp" >"$BASE/tb_faults_old.cpp"
sed -i "s/0x00002083u/0x30001073u/g" "$BASE/tb_faults_old.cpp"
cp "$ROOT/verification/p1c/old_repro/integer_tb_top_old_repro_r3.sv" \
   "$BUILD/integer_tb_top_old_repro_r3.sv"
if ! run_logged build verilator --cc --exe --build --assert -Wall \
     -Wno-DECLFILENAME -I"$ROOT/rtl/include" --top-module integer_tb_top \
     -Mdir "$BUILD/obj" -CFLAGS -std=c++17 -f "$ROOT/rtl/p1_c.f" \
     "$BUILD/integer_tb_top_old_repro_r3.sv" "$BASE/tb_faults_old.cpp" -o fault_old; then
  printf 'P1-C-R3_OLD_REPRO_FAIL: build\n' >&2
  exit 1
fi
run_logged run "$BUILD/obj/fault_old" +case=jalr_unaligned +negative=initial_arf
rc=$?
if [ "$rc" -eq 1 ] &&
   grep -qF 'P1C_FAULT_NEGATIVE_INITIAL_ARF_DETECTED' "$BASE/run.log" &&
   grep -qF 'fault metadata mismatch' "$BASE/run.log"; then
  printf 'OLD_H01_EARLY_RETURN_MASKED_ERROR_REPRODUCED\n'
  printf 'P1-C-R3_OLD_REPRO_ALL_PASS\n'
  exit 0
fi
printf 'P1-C-R3_OLD_REPRO_FAIL: rc=%s (expected masked DETECTED exit 1)\n' "$rc" >&2
exit 1
