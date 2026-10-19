#!/usr/bin/env bash
# Shared host watchdog for P0-01 runners.
#
# Every simulation/reference execution goes through run_guarded. The timeout is
# configurable through P0_01_HOST_TIMEOUT (seconds). A timeout is a real failure
# and is recorded with the actual exit code; it is never treated as success.

P0_01_HOST_TIMEOUT="${P0_01_HOST_TIMEOUT:-60}"

if ! [[ "$P0_01_HOST_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  printf 'P0-01_WATCHDOG_CONFIG_ERROR: invalid P0_01_HOST_TIMEOUT=%s\n' \
    "$P0_01_HOST_TIMEOUT" >&2
  exit 2
fi

# run_guarded <log> <command> [args...]
#
# Runs the command under `timeout`, appends command, elapsed time, real exit
# code and (on 124/137) an explicit watchdog reason to the log. Returns the
# command's exit status. `-k 5s` bounds kill escalation so no child survives
# the watchdog indefinitely.
run_guarded() {
  local log="$1"
  shift
  local tmo="$P0_01_HOST_TIMEOUT"
  local start end rc
  start="$(date +%s)"
  {
    printf 'command: timeout -k 5s %ss %s\n' "$tmo" "$*"
    timeout -k 5s "${tmo}s" "$@" 2>&1
    rc=$?
    end="$(date +%s)"
    printf 'elapsed_seconds: %s\n' "$((end - start))"
    printf 'exit: %s\n' "$rc"
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
      printf 'P0-01_WATCHDOG_TIMEOUT: host watchdog fired after %ss (exit=%s); command=%s\n' \
        "$tmo" "$rc" "$*"
    fi
  } >"$log" 2>&1
  return "$rc"
}

# run_guarded_append <log> <command> [args...]
# Same as run_guarded but appends to an existing log (used when the caller
# wants to record the fully expanded command line first).
run_guarded_append() {
  local log="$1"
  shift
  local tmo="$P0_01_HOST_TIMEOUT"
  local start end rc
  start="$(date +%s)"
  {
    timeout -k 5s "${tmo}s" "$@" 2>&1
    rc=$?
    end="$(date +%s)"
    printf 'elapsed_seconds: %s\n' "$((end - start))"
    printf 'exit: %s\n' "$rc"
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
      printf 'P0-01_WATCHDOG_TIMEOUT: host watchdog fired after %ss (exit=%s); command=%s\n' \
        "$tmo" "$rc" "$*"
    fi
  } >>"$log" 2>&1
  return "$rc"
}
