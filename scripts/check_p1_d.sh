#!/usr/bin/env bash
# P1-D total entry: Load/Store, shared bus, data faults, Spike differential,
# negative probes and P1-C/P1-B/P1-A/P0 regression.
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${P1_D_EVIDENCE:-$ROOT/verification/evidence/P1-D}"
LOG_DIR="$BASE/logs"; SOFT_DIR="$BASE/software"; FAULT_DIR="$BASE/faults"
INJECT_DIR="$BASE/injection"; BUILD="$ROOT/build/p1-d"
VERILATOR="${VERILATOR:-verilator}"; SPIKE="${SPIKE:-spike}"
CROSS="${CROSS_PREFIX:-riscv64-unknown-elf-}"
HOST_TIMEOUT="${P1_D_HOST_TIMEOUT:-1200}"; KILL_AFTER="${P1_D_KILL_AFTER:-5}"
INJECT="${P1_D_INJECT:-}"; PROBE_EXTRA="${P1_D_PROBE_EXTRA:-0}"
case "$INJECT" in ""|pc|instr|rd|next_pc|missing|duplicate|token|pc_extra) ;; *) printf 'P1-D_CONFIG_ERROR: invalid P1_D_INJECT\n' >&2; exit 2;; esac
mkdir -p "$LOG_DIR" "$SOFT_DIR" "$FAULT_DIR" "$INJECT_DIR" "$BUILD" || exit 1
fail=0
pass(){ printf 'P1-D_STEP_PASS: %s\n' "$*"; }
bad(){ printf 'P1-D_STEP_FAIL: %s\n' "$*" >&2; fail=1; }
run_logged(){ local name="$1"; shift; local log="$LOG_DIR/$name.log"; local rc; { printf 'command: timeout -k %ss %ss %s\n' "$KILL_AFTER" "$HOST_TIMEOUT" "$*"; timeout -k "${KILL_AFTER}s" "${HOST_TIMEOUT}s" "$@" 2>&1; rc=$?; printf 'exit: %s\n' "$rc"; } >"$log" 2>&1; return "$rc"; }
run_expected(){ local name="$1" want="$2" pat="$3"; shift 3; local log="$INJECT_DIR/$name.log"; local rc; { printf 'command: timeout -k %ss %ss %s\n' "$KILL_AFTER" "$HOST_TIMEOUT" "$*"; timeout -k "${KILL_AFTER}s" "${HOST_TIMEOUT}s" "$@" 2>&1; rc=$?; printf 'exit: %s\n' "$rc"; } >"$log" 2>&1; if [ "$rc" != "$want" ] || ! grep -qF "$pat" "$log"; then bad "$name (rc=$rc want=$want, see ${log#"$ROOT"/})"; else pass "$name (exit=$rc)"; fi; }

if run_logged lint "$VERILATOR" --lint-only -Wall --assert -I"$ROOT/rtl/include" --top-module p1_integer_top -f "$ROOT/rtl/p1_d.f"; then pass "P1-D RTL lint"; else bad "P1-D RTL lint"; fi
if run_logged lint-int-tb "$VERILATOR" --lint-only -Wall --assert -I"$ROOT/rtl/include" --top-module integer_tb_top -f "$ROOT/rtl/p1_d.f" "$ROOT/verification/p1c/tb/integer_tb_top.sv"; then pass "P1-D integer TB lint"; else bad "P1-D integer TB lint"; fi

rm -rf "$BUILD/arb" "$BUILD/int" "$BUILD/fault"; mkdir -p "$BUILD/arb/obj" "$BUILD/int/obj" "$BUILD/fault/obj"
if run_logged arb-build "$VERILATOR" --cc --exe --build --assert -Wall -I"$ROOT/rtl/include" --top-module arbiter_tb_top -Mdir "$BUILD/arb/obj" -CFLAGS -std=c++17 "$ROOT/rtl/include/core_config_pkg.sv" "$ROOT/rtl/include/core_types_pkg.sv" "$ROOT/rtl/core/p1_bus_arbiter.sv" "$ROOT/verification/p1d/tb/arbiter_tb_top.sv" "$ROOT/verification/p1d/tb/tb_arbiter.cpp" -o arb_tb; then
  if run_logged arb-run "$BUILD/arb/obj/arb_tb"; then
    if grep -qF 'P1D_ARB_PASS' "$LOG_DIR/arb-run.log"; then pass "arbiter fairness/routing/stability"; else bad "arbiter missing PASS"; fi
  else bad "arbiter run"; fi
else bad "arbiter build"; fi

if run_logged int-build "$VERILATOR" --cc --exe --build --assert -Wall -I"$ROOT/rtl/include" --top-module integer_tb_top -Mdir "$BUILD/int/obj" -CFLAGS -std=c++17 -f "$ROOT/rtl/p1_d.f" "$ROOT/verification/p1c/tb/integer_tb_top.sv" "$ROOT/verification/p1c/tb/tb_integer.cpp" -o integer_tb; then int_ok=1; pass "integer DUT build"; else int_ok=0; bad "integer DUT build"; fi
if run_logged fault-build "$VERILATOR" --cc --exe --build --assert -Wall -I"$ROOT/rtl/include" --top-module integer_tb_top -Mdir "$BUILD/fault/obj" -CFLAGS -std=c++17 -f "$ROOT/rtl/p1_d.f" "$ROOT/verification/p1c/tb/integer_tb_top.sv" "$ROOT/verification/p1d/tb/tb_data_faults.cpp" -o data_fault_tb; then fault_ok=1; pass "data fault build"; else fault_ok=0; bad "data fault build"; fi

read -r -a SPIKE_ARGS < "$ROOT/config/platform.spike.args"
CC_FLAGS=(-march=rv32i -mabi=ilp32 -mcmodel=medany -mno-relax -nostdlib -nostartfiles -ffreestanding -fno-builtin -O2 -T "$ROOT/software/smoke/link.ld" -Wl,--build-id=none)
build_program(){ local tag="$1" src="$2"; local elf="$SOFT_DIR/$tag.elf" bin="$SOFT_DIR/$tag.bin"; if ! run_logged "build-$tag" "${CROSS}gcc" "${CC_FLAGS[@]}" -o "$elf" "$src"; then bad "build $tag"; return 1; fi; if ! run_logged "objcopy-$tag" "${CROSS}objcopy" -O binary "$elf" "$bin"; then bad "objcopy $tag"; return 1; fi; if ! run_logged "objdump-$tag" bash -c 'exec "$0" -d "$1" > "$2"' "${CROSS}objdump" "$elf" "$SOFT_DIR/$tag.objdump"; then bad "objdump $tag"; return 1; fi; if ! run_logged "nm-$tag" bash -c 'exec "$0" "$1" > "$2"' "${CROSS}nm" "$elf" "$SOFT_DIR/$tag.nm"; then bad "nm $tag"; return 1; fi; if [ "$src" != "$SOFT_DIR/$tag.S" ]; then cp "$src" "$SOFT_DIR/$tag.S"; fi; pass "software $tag"; }

run_program(){ local tag="$1"; local elf="$SOFT_DIR/$tag.elf" bin="$SOFT_DIR/$tag.bin"; local dut="$SOFT_DIR/$tag.dut.jsonl" regs="$SOFT_DIR/$tag.regs.json" dump="$SOFT_DIR/$tag.ram"; local end; end="$("${CROSS}nm" "$elf" | awk '$3=="end"{print $1}')"; [ -z "$end" ] && { bad "no end $tag"; return 1; }; if ! run_logged "spike-$tag" "$SPIKE" "${SPIKE_ARGS[@]}" --pc=0x80000000 --instructions=5000 --log-commits --log="$SOFT_DIR/$tag.spike.log" "$elf"; then bad "Spike $tag"; return 1; fi; if ! run_logged "dut-$tag" "$BUILD/int/obj/integer_tb" +image="$bin" +trace="$dut" +regs="$regs" +end_pc=0x"$end" +max_retire=10000 +max_cycles=400000 +stall +delay +ram_dump="$dump" +ram_start=0x80018000 +ram_len=256; then bad "DUT $tag"; return 1; fi; if ! run_logged "contract-$tag" python3 "$ROOT/scripts/check_retire_contract.py" --validate-file "$dut"; then bad "contract $tag"; return 1; fi; local extra=(); if [ "$tag" = directed ] && [ -n "$INJECT" ]; then extra+=(--inject "$INJECT"); fi; if ! run_logged "diff-$tag" python3 "$ROOT/scripts/p1d_diff.py" --dut "$dut" --spike "$SOFT_DIR/$tag.spike.log" --regs "$regs" --end-pc "0x$end" --ram-dump "$dump" --ram-start 0x80018000 --ram-len 256 "${extra[@]}"; then bad "diff $tag"; return 1; fi; if ! grep -qF 'P1D_DIFF_PASS' "$LOG_DIR/diff-$tag.log"; then bad "diff $tag missing PASS"; return 1; fi; local stats; stats="$(grep 'P1D_MEM_STATS' "$LOG_DIR/dut-$tag.log" | tail -1)"; local dreq dresp wr; dreq="$(printf '%s' "$stats" | sed -n 's/.*data_req=\([0-9]*\).*/\1/p')"; dresp="$(printf '%s' "$stats" | sed -n 's/.*data_resp=\([0-9]*\).*/\1/p')"; wr="$(printf '%s' "$stats" | sed -n 's/.*ram_writes=\([0-9]*\).*/\1/p')"; [ -z "$dreq" ] && { bad "missing mem stats $tag"; return 1; }; if [ "$dreq" != "$dresp" ]; then bad "$tag data req/resp conservation $dreq/$dresp"; return 1; fi; if [ "$tag" != directed ] && { [ "$wr" -lt 64 ] || [ $((dreq-wr)) -lt 64 ]; }; then bad "$tag insufficient load/store $dreq/writes=$wr"; return 1; fi; printf '%s\n' "$dreq" >"$SOFT_DIR/$tag.data_req"; printf '%s\n' "$wr" >"$SOFT_DIR/$tag.writes"; pass "DUT/Spike diff $tag data_req=$dreq writes=$wr"; return 0; }

if [ "$int_ok" -eq 1 ]; then
  if build_program directed "$ROOT/software/p1d/directed.S"; then run_program directed || true; fi
  seeds=(0x1a2b3c4d 0x5e6f7a8b 0x9c0d1e2f)
  for i in 0 1 2; do tag="random$i"; src="$SOFT_DIR/$tag.S"; python3 "$ROOT/scripts/gen_p1d_random.py" --out "$src" --seed "${seeds[$i]}" --loops 80 --body 16 >"$LOG_DIR/gen-$tag.log" 2>&1 || bad "gen $tag"; if [ -f "$src" ] && build_program "$tag" "$src"; then run_program "$tag" || true; fi; done
else bad "software/diff skipped"; fi

if [ "$fault_ok" -eq 1 ]; then
  for c in load_misalign load_x0_misalign load_access store_misalign store_access bridge_load_error; do
    if run_logged "fault-$c" "$BUILD/fault/obj/data_fault_tb" +case="$c"; then
      if grep -qF "P1D_FAULT_PASS case=$c" "$LOG_DIR/fault-$c.log"; then pass "data fault $c"; else bad "fault $c missing PASS"; fi
    else bad "fault $c"; fi
  done
else bad "fault probes skipped"; fi

if [ -f "$SOFT_DIR/directed.dut.jsonl" ]; then
  end="$("${CROSS}nm" "$SOFT_DIR/directed.elf" | awk '$3=="end"{print $1}')"; dut="$SOFT_DIR/directed.dut.jsonl"; regs="$SOFT_DIR/directed.regs.json"; spike="$SOFT_DIR/directed.spike.log"; dump="$SOFT_DIR/directed.ram"
  probe_pc=pc
  if [ "$PROBE_EXTRA" = "1" ]; then probe_pc=pc_extra; fi
  for kind in pc instr rd next_pc missing duplicate token; do
    ikind="$kind"; if [ "$kind" = "pc" ]; then ikind="$probe_pc"; fi
    run_expected "diff-inject-$kind" 1 "P1D_DIFF_NEGATIVE_${kind^^}_DETECTED" python3 "$ROOT/scripts/p1d_diff.py" --dut "$dut" --spike "$spike" --regs "$regs" --end-pc "0x$end" --ram-dump "$dump" --ram-start 0x80018000 --ram-len 256 --inject "$ikind"
  done
  run_expected diff-inject-pc-extra 3 "P1D_DIFF_INJECTION_EXTRA_ERRORS" python3 "$ROOT/scripts/p1d_diff.py" --dut "$dut" --spike "$spike" --regs "$regs" --end-pc "0x$end" --ram-dump "$dump" --ram-start 0x80018000 --ram-len 256 --inject pc_extra
  vd="$INJECT_DIR/traces"; mkdir -p "$vd"
  for mode in seq_dup seq_missing bool_string; do
    v="$vd/$mode.jsonl"; python3 "$ROOT/scripts/p1c_make_trace_variant.py" --in "$dut" --out "$v" --mode "$mode"
    run_expected "format-$mode" 4 "P1D_DIFF_BASELINE_FAIL" python3 "$ROOT/scripts/p1d_diff.py" --dut "$v" --spike "$spike" --regs "$regs" --end-pc "0x$end" --ram-dump "$dump" --ram-start 0x80018000 --ram-len 256
  done
else bad "directed trace missing for negative probes"; fi

# Actual total-entry failures: normal directed step injected, and expected
# detection probe replaced by target+extra error.
if [ -n "$INJECT" ]; then bad "directed diff injected ($INJECT) failed as required"; fi
if [ "$PROBE_EXTRA" = "1" ]; then
  # Re-run the expected PC probe with pc_extra; it must not match the fixed
  # rc1/DETECTED criterion.
  run_expected probe-extra-rejection 3 "P1D_DIFF_INJECTION_EXTRA_ERRORS" python3 "$ROOT/scripts/p1d_diff.py" --dut "$SOFT_DIR/directed.dut.jsonl" --spike "$SOFT_DIR/directed.spike.log" --regs "$SOFT_DIR/directed.regs.json" --end-pc "0x$("${CROSS}nm" "$SOFT_DIR/directed.elf" | awk '$3=="end"{print $1}')" --ram-dump "$SOFT_DIR/directed.ram" --ram-start 0x80018000 --ram-len 256 --inject pc_extra
fi

if run_logged regression-p1-c env P1_C_EVIDENCE="$BASE/regression/P1-C" P1_C_HOST_TIMEOUT="${P1_D_P1C_HOST_TIMEOUT:-1200}" make -C "$ROOT" check-p1-c; then
  if grep -qF 'P1-C_CHECK_ALL_PASS' "$LOG_DIR/regression-p1-c.log"; then pass "P1-C regression (including P1-B/P1-A/P0)"; else bad "P1-C regression missing PASS"; fi
else bad "P1-C regression"; fi

{ printf 'P1-D check summary\n'; printf 'date_utc: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"; printf 'git_head: %s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"; printf 'git_branch: %s\n' "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"; printf 'log_dir: %s\n' "${LOG_DIR#"$ROOT"/}"; printf 'inject: %s\n' "${INJECT:-none}"; printf 'probe_extra: %s\n' "$PROBE_EXTRA"; printf 'git_status:\n'; git -C "$ROOT" status --short | sed 's/^/  /'; if [ "$fail" -eq 0 ]; then printf 'result: PASS\n'; else printf 'result: FAIL\n'; fi; } >"$LOG_DIR/summary.log"
cat "$LOG_DIR/summary.log"
if [ "$fail" -eq 0 ]; then printf 'P1-D_CHECK_ALL_PASS\n'; exit 0; fi
printf 'P1-D_CHECK_ALL_FAIL\n' >&2; exit 1
