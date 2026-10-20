#!/usr/bin/env bash
# P1-C-R2 targeted old-checker reproductions on d8d7cab.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${P1_C_R2_REPRO_EVIDENCE:-$ROOT/verification/evidence/P1-C-R2/old-repro}"
DATA="${P1_C_R2_BASE_DATA:-$ROOT/verification/evidence/P1-C-R2/software}"
BUILD="$ROOT/build/p1-c-r2/old-repro"
OLD_COMMIT=d8d7cabe9cad2b967ce7146feed6313848945ef9
TIMEOUT="${P1_C_R2_REPRO_TIMEOUT:-120}"
mkdir -p "$BASE/data" "$BUILD" || exit 1

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

# G01: old differential entry does not run the frozen stream/seq validator.
git -C "$ROOT" show "$OLD_COMMIT:scripts/p1c_diff.py" >"$BASE/old-p1c_diff.py"
python3 "$ROOT/scripts/p1c_make_trace_variant.py" --in "$DATA/directed.dut.jsonl" \
  --out "$BASE/data/seq-dup.jsonl" --mode seq_dup
end="$(riscv64-unknown-elf-nm "$DATA/directed.elf" | awk '$3=="end"{print $1}')"
run_logged g01-seq-dup python3 "$BASE/old-p1c_diff.py" \
  --dut "$BASE/data/seq-dup.jsonl" --spike "$DATA/directed.spike.log" \
  --regs "$DATA/directed.regs.json" --end-pc "0x$end"
g01_rc=$?
if [ "$g01_rc" -eq 0 ] && grep -qF 'P1C_DIFF_PASS' "$BASE/g01-seq-dup.log"; then
  printf 'OLD_G01_SEQ_BLIND_REPRODUCED\n'
else
  printf 'OLD_G01_SEQ_BLIND_NOT_REPRODUCED rc=%s\n' "$g01_rc" >&2
  exit 1
fi

# G02: old fault TB snapshots the observed ARF after fault, so a stable wrong
# x1 at first observation is accepted. The wrapper is a test observation
# fixture; current RTL itself writes the correct prefix values.
git -C "$ROOT" show "$OLD_COMMIT:verification/p1c/tb/tb_faults.cpp" >"$BASE/data/tb_faults_old.cpp"
cp "$ROOT/verification/p1c/old_repro/integer_tb_top_old_repro.sv" \
   "$BUILD/integer_tb_top_old_repro.sv"
if ! run_logged g02-build verilator --cc --exe --build --assert -Wall \
     -Wno-DECLFILENAME -I"$ROOT/rtl/include" \
     --top-module integer_tb_top -Mdir "$BUILD/obj" \
     -CFLAGS -std=c++17 -f "$ROOT/rtl/p1_c.f" \
     "$BUILD/integer_tb_top_old_repro.sv" "$BASE/data/tb_faults_old.cpp" -o fault_old; then
  printf 'OLD_G02_BUILD_FAIL\n' >&2
  exit 1
fi
run_logged g02-initial-arf "$BUILD/obj/fault_old" +case=jalr_unaligned
g02_rc=$?
if [ "$g02_rc" -eq 0 ] && grep -qF 'P1C_FAULT_PASS case=jalr_unaligned' "$BASE/g02-initial-arf.log"; then
  printf 'OLD_G02_FAULT_INITIAL_ARF_SNAPSHOT_REPRODUCED\n'
else
  printf 'OLD_G02_FAULT_INITIAL_ARF_NOT_REPRODUCED rc=%s\n' "$g02_rc" >&2
  exit 1
fi
printf 'P1-C-R2_OLD_REPRO_ALL_PASS\n'
