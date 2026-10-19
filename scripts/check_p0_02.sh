#!/usr/bin/env bash
# P0-02 total entry: platform config, shared types, retire contract, and the
# existing P0-01/R1 regression with logs redirected to this round's evidence.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${P0_02_EVIDENCE:-$ROOT/verification/evidence/P0-02}"
LOG_DIR="$BASE/logs"
BUILD="$ROOT/build/p0-02"
VERILATOR="${VERILATOR:-verilator}"
STEP_TIMEOUT="${P0_02_STEP_TIMEOUT:-600}"

# shellcheck source=lib/watchdog.sh
. "$ROOT/scripts/lib/watchdog.sh"

if ! mkdir -p "$LOG_DIR" "$BUILD"; then
  printf 'P0-02_CHECK_FAIL: cannot create log/build directories\n' >&2
  exit 1
fi

fail=0
pass() { printf 'P0-02_STEP_PASS: %s\n' "$*"; }
bad() { printf 'P0-02_STEP_FAIL: %s\n' "$*" >&2; fail=1; }

run_logged() {
  local name="$1"; shift
  local log="$LOG_DIR/$name.log"
  local rc
  {
    printf 'command: %s\n' "$*"
    timeout -k 5s "${STEP_TIMEOUT}s" "$@" 2>&1
    rc=$?
    printf 'exit: %s\n' "$rc"
  } >"$log" 2>&1
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    printf 'P0-02_WATCHDOG_TIMEOUT: %s exceeded %ss (exit=%s)\n' \
      "$name" "$STEP_TIMEOUT" "$rc"
  fi
  return "$rc"
}

# S02: single platform source, generated files, linker/ELF/Spike agreement.
if run_logged platform-check python3 "$ROOT/scripts/check_platform.py"; then
  pass "platform config, generated files, linker, ELF and Spike agree"
else
  bad "platform check (see ${LOG_DIR#"$ROOT"/}/platform-check.log)"
fi

if run_logged platform-negative python3 "$ROOT/scripts/check_platform.py" --negative; then
  pass "negative platform configs rejected"
else
  bad "negative platform configs (see ${LOG_DIR#"$ROOT"/}/platform-negative.log)"
fi

# S02b: record the installed Spike's actual final-ISA/Svade option support.
if run_logged spike-features bash -c '
  set -e
  args="--isa=rv32im_zicsr_zifencei_svade --priv=msu"
  echo "== dump-dts =="
  spike $args -m0x80000000:0x20000 --dump-dts "$1" | sed -n "1,40p"
  echo "== run =="
  spike $args --disable-dtb -m0x80000000:0x20000 "$1"
  echo "spike-final-smoke-exit: $?"
' _ "$ROOT/build/p0-02-platform/platform_check.elf"; then
  pass "Spike accepts final ISA/Svade/priv and runs the smoke ELF"
else
  bad "Spike final ISA/Svade probe (see ${LOG_DIR#"$ROOT"/}/spike-features.log)"
fi

# S03: shared types compile, lint, self-check, and reject illegal parameters.
TYPES_SRC=(
  "$ROOT/rtl/include/core_config_pkg.sv"
  "$ROOT/rtl/include/core_types_pkg.sv"
  "$ROOT/verification/spec/types/type_selfcheck.sv"
)

if run_logged types-lint "$VERILATOR" --lint-only -Wall --assert \
     -I"$ROOT/rtl/include" --top-module type_selfcheck "${TYPES_SRC[@]}"; then
  pass "shared type lint"
else
  bad "shared type lint (see ${LOG_DIR#"$ROOT"/}/types-lint.log)"
fi

rm -rf "$BUILD/types"
mkdir -p "$BUILD/types/obj"
if run_logged types-build "$VERILATOR" --cc --exe --build --assert \
     -I"$ROOT/rtl/include" --top-module type_selfcheck \
     -Mdir "$BUILD/types/obj" -CFLAGS -std=c++17 "${TYPES_SRC[@]}" \
     "$ROOT/verification/spec/types/tb_types.cpp" -o type_selfcheck; then
  pass "shared type build"
  if run_logged types-run "$BUILD/types/obj/type_selfcheck"; then
    if grep -q 'P0-02_TYPE_SELFCHECK_PASS' "$LOG_DIR/types-run.log"; then
      pass "shared type width/layout self-check"
    else
      bad "shared type self-check did not print the expected marker"
    fi
  else
    bad "shared type self-check run (see ${LOG_DIR#"$ROOT"/}/types-run.log)"
  fi
else
  bad "shared type build (see ${LOG_DIR#"$ROOT"/}/types-build.log)"
fi

rm -rf "$BUILD/invalid"
mkdir -p "$BUILD/invalid/obj"
if run_logged types-invalid-build "$VERILATOR" --cc --exe --build --assert \
     -I"$ROOT/rtl/include" -GINJECT_INVALID=1 --top-module type_invalid_probe \
     -Mdir "$BUILD/invalid/obj" -CFLAGS -std=c++17 \
     "$ROOT/rtl/include/core_config_pkg.sv" \
     "$ROOT/verification/spec/types/type_invalid_probe.sv" \
     "$ROOT/verification/spec/types/tb_invalid.cpp" -o invalid_probe; then
  if run_logged types-invalid-run "$BUILD/invalid/obj/invalid_probe"; then
    bad "invalid parameter probe unexpectedly passed"
  else
    if grep -q 'P0-02_INVALID_PARAM_DETECTED' "$LOG_DIR/types-invalid-run.log"; then
      pass "invalid shared parameters rejected"
    else
      bad "invalid parameter probe failed without the expected message"
    fi
  fi
else
  bad "invalid parameter probe build (see ${LOG_DIR#"$ROOT"/}/types-invalid-build.log)"
fi

# S04: retire contract format and negative self-test.
if run_logged retire-selftest python3 "$ROOT/scripts/check_retire_contract.py" --self-test; then
  pass "retire contract validator rejects malformed records"
else
  bad "retire contract self-test (see ${LOG_DIR#"$ROOT"/}/retire-selftest.log)"
fi

if run_logged retire-validate python3 "$ROOT/scripts/check_retire_contract.py" --validate-examples; then
  pass "retire contract examples validate"
else
  bad "retire contract examples (see ${LOG_DIR#"$ROOT"/}/retire-validate.log)"
fi

# S06: existing regression, with logs redirected so history is not overwritten.
if run_logged regression-p0-01 env \
     P0_01_LOG_DIR="$BASE/regression/p0-01/logs" \
     make -C "$ROOT" check-p0-01; then
  pass "make check-p0-01 regression"
else
  bad "make check-p0-01 regression (see ${LOG_DIR#"$ROOT"/}/regression-p0-01.log)"
fi

if run_logged regression-r1-probes env \
     P0_01_R1_PROBE_DIR="$BASE/regression/p0-01-r1" \
     make -C "$ROOT" r1-probes; then
  pass "make r1-probes regression"
else
  bad "make r1-probes regression (see ${LOG_DIR#"$ROOT"/}/regression-r1-probes.log)"
fi

{
  printf 'P0-02 check summary\n'
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
  printf 'P0-02_CHECK_ALL_PASS\n'
  exit 0
fi
printf 'P0-02_CHECK_ALL_FAIL\n' >&2
exit 1
