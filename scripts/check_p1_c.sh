#!/usr/bin/env bash
# P1-C total entry: integer backend, ALU/ARF, directed/random Spike differential,
# stopped-fault probes, negative comparison isolation and P1-B/P1-A/P0 regression.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${P1_C_EVIDENCE:-$ROOT/verification/evidence/P1-C-R3}"
LOG_DIR="$BASE/logs"
SOFT_DIR="$BASE/software"
FAULT_DIR="$BASE/faults"
INJECT_DIR="$BASE/injection"
BUILD="$ROOT/build/p1-c"
VERILATOR="${VERILATOR:-verilator}"
SPIKE="${SPIKE:-spike}"
CROSS="${CROSS_PREFIX:-riscv64-unknown-elf-}"
HOST_TIMEOUT="${P1_C_HOST_TIMEOUT:-900}"
KILL_AFTER="${P1_C_KILL_AFTER:-5}"
INJECT="${P1_C_INJECT:-}"
DIFF_INJECT=""
case "$INJECT" in
  pc|instr|rd|next_pc|missing|duplicate|token|pc_extra) DIFF_INJECT="$INJECT" ;;
esac

if ! [[ "$HOST_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || ! [[ "$KILL_AFTER" =~ ^[1-9][0-9]*$ ]]; then
  printf 'P1-C_CONFIG_ERROR: invalid host timeout/kill-after\n' >&2
  exit 2
fi
case "$INJECT" in
  ""|pc|instr|rd|next_pc|missing|duplicate|token|pc_extra|fault_initial|fault_hold|probe_initial_extra|probe_hold_extra) ;;
  *) printf 'P1-C_CONFIG_ERROR: invalid P1_C_INJECT=%s\n' "$INJECT" >&2; exit 2 ;;
esac

mkdir -p "$LOG_DIR" "$SOFT_DIR" "$FAULT_DIR" "$INJECT_DIR" "$BUILD" || {
  printf 'P1-C_STEP_FAIL: cannot create directories\n' >&2
  exit 1
}

fail=0
pass() { printf 'P1-C_STEP_PASS: %s\n' "$*"; }
bad() { printf 'P1-C_STEP_FAIL: %s\n' "$*" >&2; fail=1; }

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
    printf 'P1-C_WATCHDOG_TIMEOUT: %s exceeded %ss (exit=%s)\n' \
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

# V01: lint and module-level units.
if run_logged lint "$VERILATOR" --lint-only -Wall --assert \
     -I"$ROOT/rtl/include" --top-module p1_integer_top -f "$ROOT/rtl/p1_c.f"; then
  pass "P1-C integer RTL lint"
else
  bad "P1-C integer RTL lint"
fi
if run_logged lint-integer-tb "$VERILATOR" --lint-only -Wall --assert \
     -I"$ROOT/rtl/include" --top-module integer_tb_top \
     -f "$ROOT/rtl/p1_c.f" "$ROOT/verification/p1c/tb/integer_tb_top.sv"; then
  pass "P1-C integer TB lint"
else
  bad "P1-C integer TB lint"
fi

rm -rf "$BUILD/alu" "$BUILD/arf" "$BUILD/integer" "$BUILD/fault"
mkdir -p "$BUILD/alu/obj" "$BUILD/arf/obj" "$BUILD/integer/obj" "$BUILD/fault/obj"
if run_logged alu-build "$VERILATOR" --cc --exe --build --assert -Wall \
     -I"$ROOT/rtl/include" --top-module alu_tb_top -Mdir "$BUILD/alu/obj" \
     -CFLAGS -std=c++17 "$ROOT/rtl/include/core_config_pkg.sv" \
     "$ROOT/rtl/include/core_types_pkg.sv" "$ROOT/rtl/core/p1_alu.sv" \
     "$ROOT/verification/p1c/tb/alu_tb_top.sv" \
     "$ROOT/verification/p1c/tb/tb_alu.cpp" -o alu_tb; then
  if run_logged alu-run "$BUILD/alu/obj/alu_tb"; then
    if grep -qF 'P1C_ALU_PASS' "$LOG_DIR/alu-run.log"; then pass "29-op ALU unit"; else bad "ALU missing PASS"; fi
  else bad "ALU run"; fi
else bad "ALU build"; fi

if run_logged arf-build "$VERILATOR" --cc --exe --build --assert -Wall \
     -I"$ROOT/rtl/include" --top-module arf_tb_top -Mdir "$BUILD/arf/obj" \
     -CFLAGS -std=c++17 "$ROOT/rtl/include/core_config_pkg.sv" \
     "$ROOT/rtl/include/core_types_pkg.sv" "$ROOT/rtl/core/p1_arf.sv" \
     "$ROOT/verification/p1c/tb/arf_tb_top.sv" \
     "$ROOT/verification/p1c/tb/tb_arf.cpp" -o arf_tb; then
  if run_logged arf-run "$BUILD/arf/obj/arf_tb"; then
    if grep -qF 'P1C_ARF_PASS' "$LOG_DIR/arf-run.log"; then pass "ARF x0/reset/write/read"; else bad "ARF missing PASS"; fi
  else bad "ARF run"; fi
else bad "ARF build"; fi

if run_logged integer-build "$VERILATOR" --cc --exe --build --assert -Wall \
     -I"$ROOT/rtl/include" --top-module integer_tb_top -Mdir "$BUILD/integer/obj" \
     -CFLAGS -std=c++17 -f "$ROOT/rtl/p1_c.f" \
     "$ROOT/verification/p1c/tb/integer_tb_top.sv" \
     "$ROOT/verification/p1c/tb/tb_integer.cpp" -o integer_tb; then
  pass "integer DUT build"
  integer_ok=1
else
  bad "integer DUT build"
  integer_ok=0
fi
if run_logged fault-build "$VERILATOR" --cc --exe --build --assert -Wall \
     -I"$ROOT/rtl/include" --top-module integer_tb_top -Mdir "$BUILD/fault/obj" \
     -CFLAGS -std=c++17 -f "$ROOT/rtl/p1_c.f" \
     "$ROOT/verification/p1c/tb/integer_tb_top.sv" \
     "$ROOT/verification/p1c/tb/tb_faults.cpp" -o fault_tb; then
  pass "fault-probe build"
  fault_ok=1
else
  bad "fault-probe build"
  fault_ok=0
fi

# V02/V03: software build, Spike reference, DUT run, and exact subset diff.
read -r -a SPIKE_ARGS < "$ROOT/config/platform.spike.args"
CC_FLAGS=(-march=rv32i -mabi=ilp32 -mcmodel=medany -mno-relax
          -nostdlib -nostartfiles -ffreestanding -fno-builtin -O2
          -T "$ROOT/software/smoke/link.ld" -Wl,--build-id=none)

build_program() {
  local tag="$1" src="$2"
  local elf="$SOFT_DIR/$tag.elf" bin="$SOFT_DIR/$tag.bin"
  local dis="$SOFT_DIR/$tag.objdump" nmf="$SOFT_DIR/$tag.nm"
  if ! run_logged "build-$tag" "${CROSS}gcc" "${CC_FLAGS[@]}" -o "$elf" "$src"; then
    bad "software build $tag"; return 1
  fi
  if ! run_logged "objcopy-$tag" "${CROSS}objcopy" -O binary "$elf" "$bin"; then
    bad "objcopy $tag"; return 1
  fi
  if ! run_logged "objdump-$tag" bash -c 'exec "$0" -d "$1" > "$2"' \
       "${CROSS}objdump" "$elf" "$dis"; then
    bad "objdump $tag"; return 1
  fi
  if ! run_logged "nm-$tag" bash -c 'exec "$0" "$1" > "$2"' \
       "${CROSS}nm" "$elf" "$nmf"; then
    bad "nm $tag"; return 1
  fi
  if [ "$src" != "$SOFT_DIR/$tag.S" ]; then cp "$src" "$SOFT_DIR/$tag.S"; fi
  pass "software $tag"
  return 0
}

run_program() {
  local tag="$1"
  local elf="$SOFT_DIR/$tag.elf" bin="$SOFT_DIR/$tag.bin"
  local dut="$SOFT_DIR/$tag.dut.jsonl" regs="$SOFT_DIR/$tag.regs.json"
  local spike_log="$LOG_DIR/spike-$tag.log"
  local commit_log="$SOFT_DIR/$tag.spike.log"
  local end_pc
  end_pc="$("${CROSS}nm" "$elf" | awk '$3 == "end" {print $1}')"
  if [ -z "$end_pc" ]; then bad "no end symbol for $tag"; return 1; fi
  if ! run_logged "spike-$tag" "$SPIKE" "${SPIKE_ARGS[@]}" \
       --pc=0x80000000 --instructions=5000 --log-commits --log="$commit_log" "$elf"; then
    bad "Spike $tag"; return 1
  fi
  if ! grep -q '^core ' "$commit_log"; then bad "Spike produced no commits for $tag"; return 1; fi
  if ! run_logged "dut-$tag" "$BUILD/integer/obj/integer_tb" \
       +image="$bin" +trace="$dut" +regs="$regs" +end_pc=0x"$end_pc" \
       +max_retire=200000 +max_cycles=1000000 +stall +delay; then
    bad "DUT $tag"; return 1
  fi
  if ! run_logged "contract-$tag" python3 "$ROOT/scripts/check_retire_contract.py" \
       --validate-file "$dut"; then
    bad "retire contract $tag"; return 1
  fi
  local diff_args=(--dut "$dut" --spike "$commit_log" --regs "$regs" --end-pc "0x$end_pc")
  local diff_extra=()
  if [ "$tag" = directed ] && [ -n "$DIFF_INJECT" ]; then
    diff_extra+=(--inject "$DIFF_INJECT")
  fi
  local diff_rc
  run_logged "diff-$tag" python3 "$ROOT/scripts/p1c_diff.py" "${diff_args[@]}" "${diff_extra[@]}"
  diff_rc=$?
  if [ "$diff_rc" -ne 0 ]; then
    bad "subset diff $tag (see ${LOG_DIR#"$ROOT"/}/diff-$tag.log)"
    return 1
  fi
  if ! grep -qF 'P1C_DIFF_PASS' "$LOG_DIR/diff-$tag.log"; then
    bad "subset diff $tag missing PASS"; return 1
  fi
  local retires
  retires="$(sed -n 's/.*retires=\([0-9][0-9]*\).*/\1/p' "$LOG_DIR/dut-$tag.log" | head -1)"
  if [ -z "$retires" ] || [ "$retires" -lt 1 ]; then bad "DUT $tag retire count missing"; return 1; fi
  if [ "$tag" != "directed" ] && [ "$retires" -lt 1000 ]; then
    bad "random $tag retires=$retires below 1000"; return 1
  fi
  printf '%s\n' "$retires" >"$SOFT_DIR/$tag.retires"
  pass "DUT/Spike diff $tag retires=$retires"
  return 0
}

if [ "$integer_ok" -eq 1 ]; then
  if build_program directed "$ROOT/software/p1c/directed.S"; then
    run_program directed || true
    directed_end="$("${CROSS}nm" "$SOFT_DIR/directed.elf" | awk '$3=="end"{print $1}')"
    if run_logged branch-matrix python3 "$ROOT/scripts/p1c_branch_matrix.py" \
         --spike "$SOFT_DIR/directed.spike.log" --end-pc "0x$directed_end"; then
      if grep -qF 'P1C_BRANCH_MATRIX_PASS' "$LOG_DIR/branch-matrix.log"; then
        pass "six-branch taken/untaken matrix"
      else bad "branch matrix missing PASS"; fi
    else bad "branch matrix"; fi

    # Real recovery timing sweep: request not accepted, accepted response
    # waiting, held decoded result, and response in the redirect cycle.
    for spec in "0 0 redirect_req_wait" "1 2 redirect_resp_wait" \
                "2 0 redirect_dec" "3 0 redirect_resp_same"; do
      set -- $spec
      rr="$1"; dd="$2"; key="$3"
      rtag="recovery-$rr-$dd"
      rtrace="$SOFT_DIR/directed-$rtag.jsonl"
      rregs="$SOFT_DIR/directed-$rtag.regs.json"
      if ! run_logged "dut-$rtag" "$BUILD/integer/obj/integer_tb" \
           +image="$SOFT_DIR/directed.bin" +trace="$rtrace" +regs="$rregs" \
           +end_pc=0x"$directed_end" +max_retire=200000 +max_cycles=1000000 \
           +recovery="$rr" +resp_delay="$dd"; then
        bad "recovery $rtag run"; continue
      fi
      if ! run_logged "contract-$rtag" python3 "$ROOT/scripts/check_retire_contract.py" \
           --validate-file "$rtrace"; then bad "recovery $rtag contract"; continue; fi
      if ! run_logged "diff-$rtag" python3 "$ROOT/scripts/p1c_diff.py" \
           --dut "$rtrace" --spike "$SOFT_DIR/directed.spike.log" \
           --regs "$rregs" --end-pc "0x$directed_end"; then
        bad "recovery $rtag diff"; continue
      fi
      value="$(sed -n "s/.*$key=\([0-9][0-9]*\).*/\1/p" "$LOG_DIR/dut-$rtag.log" | head -1)"
      if [ -z "$value" ] || [ "$value" -eq 0 ]; then
        bad "recovery $rtag missing $key"
      else
        pass "recovery $rtag $key=$value"
      fi
    done
  fi
  # Targeted old-checker reproduction (F01/F02) using current trace data.
  if run_logged old-repro env \
       P1_C_R1_REPRO_EVIDENCE="$BASE/old-repro" \
       P1_C_R1_BASE_DATA="$SOFT_DIR" \
       P1_C_R1_END_PC="$directed_end" \
       "$ROOT/scripts/repro_p1_c_r1.sh"; then
    if grep -qF 'P1-C-R1_OLD_REPRO_ALL_PASS' "$LOG_DIR/old-repro.log"; then
      pass "old-checker F01/F02 reproduction"
    else bad "old-checker reproduction missing PASS"; fi
  else
    bad "old-checker F01/F02 reproduction"
  fi
  # R2 old-checker reproductions: seq gate and fault initial-ARF snapshot.
  if run_logged old-repro-r2 env \
       P1_C_R2_REPRO_EVIDENCE="$BASE/old-repro-r2" \
       P1_C_R2_BASE_DATA="$SOFT_DIR" \
       "$ROOT/scripts/repro_p1_c_r2.sh"; then
    if grep -qF 'P1-C-R2_OLD_REPRO_ALL_PASS' "$LOG_DIR/old-repro-r2.log"; then
      pass "old-checker G01/G02 reproduction"
    else bad "old-checker R2 reproduction missing PASS"; fi
  else
    bad "old-checker G01/G02 reproduction"
  fi
  if run_logged old-repro-r3 env \
       P1_C_R3_REPRO_EVIDENCE="$BASE/old-repro-r3" \
       "$ROOT/scripts/repro_p1_c_r3.sh"; then
    if grep -qF 'P1-C-R3_OLD_REPRO_ALL_PASS' "$LOG_DIR/old-repro-r3.log"; then
      pass "old fault-probe H01 reproduction"
    else bad "old fault-probe reproduction missing PASS"; fi
  else
    bad "old fault-probe H01 reproduction"
  fi

  seeds=(0x1a2b3c4d 0x5e6f7a8b 0x9c0d1e2f)
  for idx in 0 1 2; do
    tag="random$idx"
    src="$SOFT_DIR/$tag.S"
    python3 "$ROOT/scripts/gen_p1c_random.py" --out "$src" --seed "${seeds[$idx]}" \
      --loops 40 --body 28 >"$LOG_DIR/gen-$tag.log" 2>&1 || bad "generate $tag"
    if [ -f "$src" ] && build_program "$tag" "$src"; then
      run_program "$tag" || true
    fi
  done
else
  bad "software/DUT differential skipped because integer DUT build failed"
fi

# V02 stopped faults and control alignment boundaries.
if [ "$fault_ok" -eq 1 ]; then
  for c in illegal unsupported unaligned unaligned_branch jalr_unaligned fetch branch_untaken jalr_clear; do
    fault_extra=()
    if [ "$c" = jalr_unaligned ] && [ "$INJECT" = fault_initial ]; then
      fault_extra+=(+negative=initial_arf)
    fi
    if [ "$c" = jalr_unaligned ] && [ "$INJECT" = fault_hold ]; then
      fault_extra+=(+negative=hold_change)
    fi
    if run_logged "fault-$c" "$BUILD/fault/obj/fault_tb" +case="$c" "${fault_extra[@]}"; then
      if grep -qF "P1C_FAULT_PASS case=$c" "$LOG_DIR/fault-$c.log"; then
        pass "fault/control probe $c"
      else bad "fault probe $c missing PASS"; fi
    else
      bad "fault probe $c"
    fi
  done
  neg_initial=initial_arf
  neg_hold=hold_change
  if [ "$INJECT" = probe_initial_extra ]; then neg_initial=initial_arf_extra; fi
  if [ "$INJECT" = probe_hold_extra ]; then neg_hold=hold_change_extra; fi
  run_expected fault-negative-initial 1 \
    "P1C_FAULT_NEGATIVE_INITIAL_ARF_DETECTED" \
    "$BUILD/fault/obj/fault_tb" +case=jalr_unaligned +negative="$neg_initial"
  run_expected fault-negative-hold 1 \
    "P1C_FAULT_NEGATIVE_HOLD_CHANGE_DETECTED" \
    "$BUILD/fault/obj/fault_tb" +case=jalr_unaligned +negative="$neg_hold"
  run_expected fault-negative-initial-extra 3 \
    "P1C_FAULT_NEGATIVE_INITIAL_ARF_EXTRA_ERRORS" \
    "$BUILD/fault/obj/fault_tb" +case=jalr_unaligned +negative=initial_arf_extra
  run_expected fault-negative-hold-extra 3 \
    "P1C_FAULT_NEGATIVE_HOLD_CHANGE_EXTRA_ERRORS" \
    "$BUILD/fault/obj/fault_tb" +case=jalr_unaligned +negative=hold_change_extra
  run_expected fault-negative-initial-missing 2 \
    "P1C_FAULT_NEGATIVE_INITIAL_ARF_NOT_DETECTED" \
    "$BUILD/fault/obj/fault_tb" +case=jalr_unaligned +negative=initial_arf_missing
else
  bad "fault probes skipped because build failed"
fi

# V04: negative comparison isolation on the directed trace.
if [ -f "$SOFT_DIR/directed.dut.jsonl" ] && [ -f "$SOFT_DIR/directed.spike.log" ]; then
  end_pc="$("${CROSS}nm" "$SOFT_DIR/directed.elf" | awk '$3=="end"{print $1}')"
  regs="$SOFT_DIR/directed.regs.json"
  dut="$SOFT_DIR/directed.dut.jsonl"
  spike_log="$SOFT_DIR/directed.spike.log"
  for kind in pc instr rd next_pc missing duplicate token; do
    run_expected "diff-inject-$kind" 1 "P1C_DIFF_NEGATIVE_${kind^^}_DETECTED" \
      python3 "$ROOT/scripts/p1c_diff.py" --dut "$dut" --spike "$spike_log" \
      --regs "$regs" --end-pc "0x$end_pc" --inject "$kind"
  done
  run_expected diff-inject-pc-extra 3 "P1C_DIFF_INJECTION_EXTRA_ERRORS" \
    python3 "$ROOT/scripts/p1c_diff.py" --dut "$dut" --spike "$spike_log" \
    --regs "$regs" --end-pc "0x$end_pc" --inject pc_extra

  variant_dir="$INJECT_DIR/traces"
  mkdir -p "$variant_dir"
  for spec in extra_endpoint:extra-endpoint:not\ unique/final \
              extra_other:extra-other:never\ ended \
              bad_line:bad-line:invalid\ JSON \
              priv:priv:field=priv \
              last_next:last-next:field=next_pc; do
    mode="${spec%%:*}"; rest="${spec#*:}"; vname="${rest%%:*}"
    pattern="${rest#*:}"
    variant="$variant_dir/$vname.jsonl"
    python3 "$ROOT/scripts/p1c_make_trace_variant.py" --in "$dut" --out "$variant" --mode "$mode"
    run_expected "variant-$vname" 4 "P1C_DIFF_BASELINE_FAIL" \
      python3 "$ROOT/scripts/p1c_diff.py" --dut "$variant" --spike "$spike_log" \
      --regs "$regs" --end-pc "0x$end_pc"
    if ! grep -qF "$pattern" "$INJECT_DIR/variant-$vname.log"; then
      bad "variant $vname missing reason '$pattern'"
    fi
  done
  dirty="$variant_dir/dirty-pc.jsonl"
  python3 "$ROOT/scripts/p1c_make_trace_variant.py" --in "$dut" --out "$dirty" --mode dirty_pc
  run_expected variant-dirty-pc-inject-rd 4 "P1C_DIFF_BASELINE_FAIL" \
    python3 "$ROOT/scripts/p1c_diff.py" --dut "$dirty" --spike "$spike_log" \
    --regs "$regs" --end-pc "0x$end_pc" --inject rd
  if grep -qF 'NEGATIVE_RD_DETECTED' "$INJECT_DIR/variant-dirty-pc-inject-rd.log"; then
    bad "dirty baseline incorrectly produced RD detection"
  fi

  # Direct differential format gate: same public path, no outer validator.
  for spec in seq_dup:seq-dup:not\ strictly\ increasing \
              seq_back:seq-back:not\ strictly\ increasing \
              seq_missing:seq-missing:missing\ fields \
              bool_string:bool-string:token_valid \
              field_missing:field-missing:missing\ fields \
              type_error:type-error:pc; do
    mode="${spec%%:*}"; rest="${spec#*:}"; vname="${rest%%:*}"
    pattern="${rest#*:}"
    variant="$variant_dir/$vname.jsonl"
    python3 "$ROOT/scripts/p1c_make_trace_variant.py" --in "$dut" --out "$variant" --mode "$mode"
    run_expected "format-$vname" 4 "P1C_DIFF_BASELINE_FAIL" \
      python3 "$ROOT/scripts/p1c_diff.py" --dut "$variant" --spike "$spike_log" \
      --regs "$regs" --end-pc "0x$end_pc"
    if ! grep -qF "$pattern" "$INJECT_DIR/format-$vname.log"; then
      bad "format $vname missing reason '$pattern'"
    fi
  done
  seqdup="$variant_dir/seq-dup.jsonl"
  python3 "$ROOT/scripts/p1c_make_trace_variant.py" --in "$dut" --out "$seqdup" --mode seq_dup
  run_expected format-seq-dup-inject-rd 4 "P1C_DIFF_BASELINE_FAIL" \
    python3 "$ROOT/scripts/p1c_diff.py" --dut "$seqdup" --spike "$spike_log" \
    --regs "$regs" --end-pc "0x$end_pc" --inject rd
  if grep -qF 'NEGATIVE_RD_DETECTED' "$INJECT_DIR/format-seq-dup-inject-rd.log"; then
    bad "format-invalid baseline incorrectly produced RD detection"
  fi
else
  bad "directed trace missing for negative probes"
fi

# V05: accepted P1-B (with P1-A/P0) regression, nested under this round.
if run_logged regression-p1-b env \
     P1_B_EVIDENCE="$BASE/regression/P1-B" \
     P1_B_HOST_TIMEOUT="${P1_C_P1B_HOST_TIMEOUT:-900}" \
     make -C "$ROOT" check-p1-b; then
  if grep -qF 'P1-B-R2_CHECK_ALL_PASS' "$LOG_DIR/regression-p1-b.log"; then
    pass "P1-B regression (including P1-A/P0)"
  else
    bad "P1-B regression missing PASS marker"
  fi
else
  bad "P1-B regression"
fi

{
  printf 'P1-C check summary\n'
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
if [ "$fail" -eq 0 ]; then printf 'P1-C_CHECK_ALL_PASS\n'; exit 0; fi
printf 'P1-C_CHECK_ALL_FAIL\n' >&2
exit 1
