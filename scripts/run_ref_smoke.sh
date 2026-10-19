#!/usr/bin/env bash
# P0-01 software/reference smoke: build RV32I/ILP32 ELF variants, inspect the
# ELF, run them under Spike, and prove that the checker detects a wrong result
# and a timeout. No pk, no libc, no OS.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/ref-smoke"
LOG_DIR="${P0_01_LOG_DIR:-$ROOT/verification/evidence/P0-01-R1/logs}"
CROSS="${CROSS_PREFIX:-riscv64-unknown-elf-}"
SPIKE="${SPIKE:-spike}"
PLATFORM_ARGS_FILE="${PLATFORM_ARGS_FILE:-$ROOT/config/platform.spike.args}"

# shellcheck source=lib/watchdog.sh
. "$ROOT/scripts/lib/watchdog.sh"

if ! mkdir -p "$BUILD" "$LOG_DIR"; then
  printf 'P0-01_REF_STEP_FAIL: cannot create build/log directories\n' >&2
  exit 1
fi

# Spike target arguments are generated from config/platform.json. This keeps
# the reference RAM range identical to the linker MEMORY region.
if [ ! -r "$PLATFORM_ARGS_FILE" ]; then
  printf 'P0-01_REF_STEP_FAIL: missing platform args %s; run python3 scripts/gen_platform.py\n' \
    "$PLATFORM_ARGS_FILE" >&2
  exit 1
fi
read -r -a SPIKE_PLATFORM_ARGS < "$PLATFORM_ARGS_FILE"

CC_FLAGS=(-march=rv32i -mabi=ilp32 -mcmodel=medany -mno-relax
          -nostdlib -nostartfiles -ffreestanding -fno-builtin -O2
          -T "$ROOT/software/smoke/link.ld" -Wl,--build-id=none)
SRC=("$ROOT/software/smoke/start.S" "$ROOT/software/smoke/main.c"
     "$ROOT/software/smoke/platform_check.c")

fail=0
pass() { printf 'P0-01_REF_STEP_PASS: %s\n' "$*"; }
bad() { printf 'P0-01_REF_STEP_FAIL: %s\n' "$*" >&2; fail=1; }

build_elf() {
  local name="$1"; shift
  local log="$LOG_DIR/build-$name.log"
  local rc
  {
    printf 'command: timeout -k 5s %ss %s %s %s -o build/ref-smoke/%s.elf\n' \
      "$P0_01_HOST_TIMEOUT" "${CROSS}gcc" "${CC_FLAGS[*]}" "$*" "$name"
    timeout -k 5s "${P0_01_HOST_TIMEOUT}s" "${CROSS}gcc" "${CC_FLAGS[@]}" "$@" \
      -o "$BUILD/$name.elf" 2>&1
    rc=$?
    printf 'exit: %s\n' "$rc"
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
      printf 'P0-01_WATCHDOG_TIMEOUT: host watchdog fired during build of %s.elf (exit=%s)\n' \
        "$name" "$rc"
    fi
  } >"$log" 2>&1
  if [ "$rc" -eq 0 ] && [ -f "$BUILD/$name.elf" ]; then
    pass "build $name.elf"
  else
    bad "build $name.elf (exit=$rc; see ${log#"$ROOT"/})"
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
    pass "ELF inspection (log: ${log#"$ROOT"/})"
  else
    bad "ELF inspection (see ${log#"$ROOT"/})"
  fi
}

inspect

run_ok() {
  local log="$LOG_DIR/spike-ok.log"
  local commit="$LOG_DIR/spike-ok-commits.log"
  local elf="$BUILD/ok.elf"
  local rc
  local -a cmd=("$SPIKE" "${SPIKE_PLATFORM_ARGS[@]}")
  if [ "${P0_01_SPIKE_NORMAL_HANG:-0}" = "1" ]; then
    # Controlled fault: do not enable --log-commits here, otherwise a 2 s
    # hanging run can emit a very large trace. The watchdog message is the
    # evidence for this probe.
    elf="$BUILD/hang.elf"
  else
    cmd+=(--log-commits --log="$commit")
  fi
  {
    printf 'command: timeout -k 5s %ss %s %s\n' \
      "${P0_01_SPIKE_NORMAL_TIMEOUT:-$P0_01_HOST_TIMEOUT}" "${cmd[*]}" "$elf"
  } >"$log" 2>&1
  P0_01_HOST_TIMEOUT="${P0_01_SPIKE_NORMAL_TIMEOUT:-$P0_01_HOST_TIMEOUT}" \
    run_guarded_append "$log" "${cmd[@]}" "$elf"
  rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    printf 'P0-01_WATCHDOG_TIMEOUT: Spike normal run exceeded %ss (exit=%s)\n' \
      "${P0_01_SPIKE_NORMAL_TIMEOUT:-$P0_01_HOST_TIMEOUT}" "$rc"
  fi
  if [ "$rc" -eq 0 ] &&
     grep -qE 'mem 0x[0-9a-f]+ 0x50415353' "$commit"; then
    pass "Spike normal run reached PASS signature"
  else
    bad "Spike normal run (exit=$rc; see ${log#"$ROOT"/})"
  fi
}

run_fail() {
  local log="$LOG_DIR/spike-fail.log"
  local rc
  run_guarded "$log" "$SPIKE" "${SPIKE_PLATFORM_ARGS[@]}" "$BUILD/fail.elf"
  rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    printf 'P0-01_WATCHDOG_TIMEOUT: Spike negative control exceeded host timeout (exit=%s)\n' "$rc"
  fi
  if [ "$rc" = "1" ] && grep -qF '*** FAILED ***' "$log"; then
    pass "Spike negative control detected wrong result (exit=$rc)"
  else
    bad "Spike negative control (exit=$rc; see ${log#"$ROOT"/})"
  fi
}

run_hang() {
  local log="$LOG_DIR/spike-hang.log"
  local rc
  P0_01_HOST_TIMEOUT="${P0_01_SPIKE_HANG_TIMEOUT:-5}" run_guarded "$log" \
    "$SPIKE" "${SPIKE_PLATFORM_ARGS[@]}" "$BUILD/hang.elf"
  rc=$?
  if [ "$rc" = "124" ] && grep -qF 'P0-01_WATCHDOG_TIMEOUT' "$log"; then
    pass "Spike timeout control detected hang (exit=$rc)"
  else
    bad "Spike timeout control (exit=$rc; see ${log#"$ROOT"/})"
  fi
}

run_ok
run_fail
run_hang

observe() {
  local log="$LOG_DIR/spike-observe.log"
  local cmds="$BUILD/debug-cmds.txt"
  local main_addr
  local rc
  local observe_elf="$BUILD/ok.elf"
  main_addr="$("${CROSS}nm" "$BUILD/ok.elf" 2>/dev/null |
    awk '$3 == "main" {print $1}')"
  if [ -z "$main_addr" ]; then
    bad "cannot resolve main symbol for Spike observation"
    return
  fi
  if [ "${P0_01_OBSERVE_HANG:-0}" = "1" ]; then
    # Controlled fault: run a program that never reaches the target address,
    # so `until pc` cannot complete and the host watchdog must intervene.
    observe_elf="$BUILD/hang.elf"
    main_addr="deadbeef"
  fi
  cat >"$cmds" <<EOF
reg 0
pc 0
until pc 0 0x$main_addr
reg 0
quit
EOF
  P0_01_HOST_TIMEOUT="${P0_01_OBSERVE_TIMEOUT:-5}" run_guarded "$log" \
    "$SPIKE" "${SPIKE_PLATFORM_ARGS[@]}" -d --debug-cmd="$cmds" \
    "$observe_elf"
  rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    printf 'P0-01_WATCHDOG_TIMEOUT: Spike observation exceeded %ss (exit=%s)\n' \
      "${P0_01_OBSERVE_TIMEOUT:-5}" "$rc"
  fi
  if [ "$rc" -eq 0 ] && grep -q 'zero:' "$log"; then
    pass "Spike observation interface (-d reg/until, --log-commits)"
  else
    bad "Spike observation interface (exit=$rc; see ${log#"$ROOT"/})"
  fi
}

observe

if [ "$fail" -eq 0 ]; then
  printf 'P0-01_REF_SMOKE_ALL_PASS\n'
  exit 0
fi
printf 'P0-01_REF_SMOKE_ALL_FAIL\n' >&2
exit 1
