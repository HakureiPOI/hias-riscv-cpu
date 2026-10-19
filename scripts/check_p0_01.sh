#!/usr/bin/env bash
# P0-01 total entry. Runs every step, records the real exit status, and fails
# if any required step is missing, times out, or fails. Expected-failure probes
# are handled inside the step scripts, not by ignoring arbitrary non-zero codes
# here.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${P0_01_LOG_DIR:-$ROOT/verification/evidence/P0-01-R1/logs}"
SUMMARY="$LOG_DIR/summary.log"
STEP_TIMEOUT="${P0_01_STEP_TIMEOUT:-600}"

# shellcheck source=lib/watchdog.sh
. "$ROOT/scripts/lib/watchdog.sh"

if ! mkdir -p "$LOG_DIR"; then
  printf 'P0-01_CHECK_FAIL: cannot create log directory %s\n' "$LOG_DIR" >&2
  exit 1
fi

declare -a NAMES=()
declare -a CODES=()
fail=0

run_step() {
  local name="$1"; shift
  local log="$LOG_DIR/$name.log"
  local rc
  printf '== %s ==\n' "$name"
  timeout -k 5s "${STEP_TIMEOUT}s" bash -c 'cd "$1" && shift && "$@"' _ "$ROOT" "$@" 2>&1 |
    tee "$log"
  rc=${PIPESTATUS[0]}
  NAMES+=("$name")
  CODES+=("$rc")
  if [ "$rc" -ne 0 ]; then
    fail=1
    printf 'STEP_FAIL %s exit=%s\n' "$name" "$rc"
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
      printf 'P0-01_WATCHDOG_TIMEOUT: step %s exceeded %ss (exit=%s)\n' \
        "$name" "$STEP_TIMEOUT" "$rc"
    fi
  else
    printf 'STEP_PASS %s exit=%s\n' "$name" "$rc"
  fi
}

run_step env-check ./scripts/env_check.sh
run_step rtl-smoke ./scripts/run_rtl_smoke.sh
run_step ref-smoke ./scripts/run_ref_smoke.sh

{
  printf 'P0-01 check summary\n'
  printf 'date_utc: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'git_head: %s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  printf 'git_branch: %s\n' "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  printf 'host_timeout_seconds: %s\n' "$P0_01_HOST_TIMEOUT"
  printf 'step_timeout_seconds: %s\n' "$STEP_TIMEOUT"
  printf 'log_dir: %s\n' "${LOG_DIR#"$ROOT"/}"
  printf 'git_status:\n'
  git -C "$ROOT" status --short | sed 's/^/  /'
  printf 'steps:\n'
  local_i=0
  while [ "$local_i" -lt "${#NAMES[@]}" ]; do
    printf '  %-12s exit=%s\n' "${NAMES[$local_i]}" "${CODES[$local_i]}"
    local_i=$((local_i + 1))
  done
  if [ "$fail" -eq 0 ]; then
    printf 'result: PASS\n'
  else
    printf 'result: FAIL\n'
  fi
} >"$SUMMARY"

cat "$SUMMARY"
if [ "$fail" -eq 0 ]; then
  exit 0
fi
exit 1
