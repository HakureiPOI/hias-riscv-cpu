#!/usr/bin/env bash
# Reproduce b42794c arbiter identity/lock defects with the R1 arbiter TB.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${P1_D_R1_REPRO_EVIDENCE:-$ROOT/verification/evidence/P1-D-R1/old-repro}"
BUILD="$ROOT/build/p1-d-r1/old-repro"
OLD=b42794cbe2e704251b277fc65a3a0f6c73ad6622
TIMEOUT="${P1_D_R1_REPRO_TIMEOUT:-120}"
mkdir -p "$BASE" "$BUILD" || exit 1
BASE="$(cd "$BASE" && pwd)"; BUILD="$(cd "$BUILD" && pwd)"
run_logged(){ local name="$1"; shift; local log="$BASE/$name.log"; local rc; { printf 'command: timeout -k 5s %ss %s\n' "$TIMEOUT" "$*"; timeout -k 5s "${TIMEOUT}s" "$@" 2>&1; rc=$?; printf 'exit: %s\n' "$rc"; } >"$log" 2>&1; return "$rc"; }
git -C "$ROOT" show "$OLD:rtl/core/p1_bus_arbiter.sv" >"$BASE/old_arbiter.sv"
if ! run_logged build verilator --cc --exe --build --assert -Wall -Wno-DECLFILENAME -I"$ROOT/rtl/include" --top-module arbiter_tb_top -Mdir "$BUILD/obj" -CFLAGS -std=c++17 "$ROOT/rtl/include/core_config_pkg.sv" "$ROOT/rtl/include/core_types_pkg.sv" "$BASE/old_arbiter.sv" "$ROOT/verification/p1d/tb/arbiter_tb_top.sv" "$ROOT/verification/p1d/tb/tb_arbiter.cpp" -o arb_old; then printf 'P1-D-R1_OLD_REPRO_FAIL: build\n' >&2; exit 1; fi
run_logged run "$BUILD/obj/arb_old"
rc=$?
if [ "$rc" -eq 1 ] && grep -qF 'P1D_ARB_FAIL' "$BASE/run.log"; then
  printf 'OLD_P1D_F01_ARB_IDENTITY_REPRODUCED\n'
  printf 'P1-D-R1_OLD_REPRO_ALL_PASS\n'
  exit 0
fi
printf 'P1-D-R1_OLD_REPRO_FAIL: rc=%s\n' "$rc" >&2
exit 1
