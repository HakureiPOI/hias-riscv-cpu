#!/usr/bin/env bash
# P0-01 software/reference smoke: build RV32I/ILP32 ELF variants, inspect the
# ELF, run them under Spike, and prove that the checker detects a wrong result
# and a timeout. No pk, no libc, no OS.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/ref-smoke"
LOG_DIR="$ROOT/verification/evidence/P0-01/logs"
CROSS="${CROSS_PREFIX:-riscv64-unknown-elf-}"
SPIKE="${SPIKE:-spike}"
SPIKE_ISA="${SPIKE_ISA:-rv32i}"
SPIKE_MEM="${SPIKE_MEM:-128}"
mkdir -p "$BUILD" "$LOG_DIR"

CC_FLAGS=(-march=rv32i -mabi=ilp32 -mcmodel=medany -mno-relax
          -nostdlib -nostartfiles -ffreestanding -fno-builtin -O2
          -T "$ROOT/software/smoke/link.ld" -Wl,--build-id=none)
SRC=("$ROOT/software/smoke/start.S" "$ROOT/software/smoke/main.c")

fail=0
pass() { printf 'P0-01_REF_STEP_PASS: %s\n' "$*"; }
bad() { printf 'P0-01_REF_STEP_FAIL: %s\n' "$*" >&2; fail=1; }

build_elf() {
  local name="$1"; shift
  local log="$LOG_DIR/build-$name.log"
  {
    printf 'command: %s %s %s -o build/ref-smoke/%s.elf\n' \
      "${CROSS}gcc" "${CC_FLAGS[*]}" "$*" "$name"
    "${CROSS}gcc" "${CC_FLAGS[@]}" "$@" -o "$BUILD/$name.elf" 2>&1
    printf 'exit: %s\n' "$?"
  } >"$log" 2>&1
  if grep -q '^exit: 0$' "$log" && [ -f "$BUILD/$name.elf" ]; then
    pass "build $name.elf"
  else
    bad "build $name.elf (see verification/evidence/P0-01/logs/build-$name.log)"
  fi
}

build_elf ok "${SRC[@]}"
build_elf fail -DSMOKE_FAIL=1 "${SRC[@]}"
build_elf hang -DSMOKE_HANG=1 "${SRC[@]}"

inspect() {
  local elf="$BUILD/ok.elf"
  local log="$LOG_DIR/elf-inspection.log"
  {
    printf '== %s header ==\n' "$elf"
    "${CROSS}readelf" -h "$elf" 2>&1
    printf '\n== program headers ==\n'
    "${CROSS}readelf" -l "$elf" 2>&1
    printf '\n== attributes ==\n'
    "${CROSS}readelf" -A "$elf" 2>&1
    printf '\n== selected symbols ==\n'
    "${CROSS}nm" "$elf" 2>&1 | grep -E ' (_start|main|tohost|fromhost|smoke_signature)$'
    printf '\n== disassembly (first 48 lines) ==\n'
    "${CROSS}objdump" -d "$elf" 2>&1 | head -48
    printf '\n== sha256 ==\n'
    sha256sum "$elf" 2>&1
  } >"$log" 2>&1
  if grep -q 'Class:.*ELF32' "$log" &&
     grep -q 'Machine:.*RISC-V' "$log" &&
     grep -q 'Entry point address:.*0x80000000' "$log" &&
     grep -q 'Tag_RISCV_arch:.*rv32i2p1' "$log"; then
    pass "ELF inspection (log: verification/evidence/P0-01/logs/elf-inspection.log)"
  else
    bad "ELF inspection (see verification/evidence/P0-01/logs/elf-inspection.log)"
  fi
}

inspect

run_ok() {
  local log="$LOG_DIR/spike-ok.log"
  local commit="$LOG_DIR/spike-ok-commits.log"
  {
    printf 'command: %s --isa=%s -m%s --log-commits --log=%s %s\n' \
      "$SPIKE" "$SPIKE_ISA" "$SPIKE_MEM" "$commit" "$BUILD/ok.elf"
    "$SPIKE" --isa="$SPIKE_ISA" -m"$SPIKE_MEM" --log-commits --log="$commit" \
      "$BUILD/ok.elf" 2>&1
    printf 'exit: %s\n' "$?"
  } >"$log" 2>&1
  if grep -q '^exit: 0$' "$log" &&
     grep -qE 'mem 0x[0-9a-f]+ 0x50415353' "$commit"; then
    pass "Spike normal run reached PASS signature"
  else
    bad "Spike normal run (see verification/evidence/P0-01/logs/spike-ok.log)"
  fi
}

run_fail() {
  local log="$LOG_DIR/spike-fail.log"
  {
    printf 'command: %s --isa=%s -m%s %s\n' \
      "$SPIKE" "$SPIKE_ISA" "$SPIKE_MEM" "$BUILD/fail.elf"
    "$SPIKE" --isa="$SPIKE_ISA" -m"$SPIKE_MEM" "$BUILD/fail.elf" 2>&1
    printf 'exit: %s\n' "$?"
  } >"$log" 2>&1
  local rc
  rc="$(awk -F': ' '/^exit: / {v=$2} END {print v}' "$log")"
  if [ "$rc" = "1" ] && grep -qF '*** FAILED ***' "$log"; then
    pass "Spike negative control detected wrong result (exit=$rc)"
  else
    bad "Spike negative control (exit=$rc; see verification/evidence/P0-01/logs/spike-fail.log)"
  fi
}

run_hang() {
  local log="$LOG_DIR/spike-hang.log"
  {
    printf 'command: timeout 5s %s --isa=%s -m%s %s\n' \
      "$SPIKE" "$SPIKE_ISA" "$SPIKE_MEM" "$BUILD/hang.elf"
    timeout 5s "$SPIKE" --isa="$SPIKE_ISA" -m"$SPIKE_MEM" "$BUILD/hang.elf" 2>&1
    printf 'exit: %s\n' "$?"
  } >"$log" 2>&1
  local rc
  rc="$(awk -F': ' '/^exit: / {v=$2} END {print v}' "$log")"
  if [ "$rc" = "124" ]; then
    pass "Spike timeout control detected hang (exit=$rc)"
  else
    bad "Spike timeout control (exit=$rc; see verification/evidence/P0-01/logs/spike-hang.log)"
  fi
}

run_ok
run_fail
run_hang

observe() {
  local log="$LOG_DIR/spike-observe.log"
  local cmds="$BUILD/debug-cmds.txt"
  local main_addr
  main_addr="$("${CROSS}nm" "$BUILD/ok.elf" 2>/dev/null |
    awk '$3 == "main" {print $1}')"
  if [ -z "$main_addr" ]; then
    bad "cannot resolve main symbol for Spike observation"
    return
  fi
  cat >"$cmds" <<EOF
reg 0
pc 0
until pc 0 0x$main_addr
reg 0
quit
EOF
  {
    printf 'command: %s --isa=%s -m%s -d --debug-cmd=%s %s\n' \
      "$SPIKE" "$SPIKE_ISA" "$SPIKE_MEM" "$cmds" "$BUILD/ok.elf"
    "$SPIKE" --isa="$SPIKE_ISA" -m"$SPIKE_MEM" -d --debug-cmd="$cmds" \
      "$BUILD/ok.elf" 2>&1
    printf 'exit: %s\n' "$?"
  } >"$log" 2>&1
  if grep -q '^exit: 0$' "$log" && grep -q 'zero:' "$log"; then
    pass "Spike observation interface (-d reg/until, --log-commits)"
  else
    bad "Spike observation interface (see verification/evidence/P0-01/logs/spike-observe.log)"
  fi
}

observe

if [ "$fail" -eq 0 ]; then
  printf 'P0-01_REF_SMOKE_ALL_PASS\n'
  exit 0
fi
printf 'P0-01_REF_SMOKE_ALL_FAIL\n' >&2
exit 1
