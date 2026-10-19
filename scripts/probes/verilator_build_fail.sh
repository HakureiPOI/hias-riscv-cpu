#!/usr/bin/env bash
# Isolated build-failure wrapper for F02.
#
# Runs the real Verilator (which may successfully produce the target binary)
# and then deliberately returns a non-zero status. It is only selected when
# P0_01_BUILD_FAULT=1; normal builds use Verilator directly.
set -u
export LC_ALL=C

REAL="${VERILATOR_REAL:-/usr/local/bin/verilator}"

if [ ! -x "$REAL" ]; then
  printf 'P0-01_BUILD_FAULT_INJECTION: real verilator not executable: %s\n' "$REAL" >&2
  exit 127
fi

"$REAL" "$@"
real_rc=$?

printf 'P0-01_BUILD_FAULT_INJECTION: real verilator exit=%s; forcing build failure (exit=3)\n' \
  "$real_rc" >&2
exit 3
