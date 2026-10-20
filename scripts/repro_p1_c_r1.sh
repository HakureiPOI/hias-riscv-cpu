#!/usr/bin/env bash
# Reproduce P1-C-R1 F01/F02 against the original P1-C checker at 7643d36.
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${P1_C_R1_REPRO_EVIDENCE:-$ROOT/verification/evidence/P1-C-R1/old-repro}"
DATA="${P1_C_R1_BASE_DATA:-$ROOT/verification/evidence/P1-C-R1/software}"
OLD="${P1_C_R1_OLD_WORKTREE:-/tmp/opencode/p1c-old-worktree}"
END="${P1_C_R1_END_PC:-}"
TIMEOUT="${P1_C_R1_REPRO_TIMEOUT:-120}"
mkdir -p "$BASE/data" || exit 1

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

git -C "$ROOT" worktree remove --force "$OLD" >/dev/null 2>&1 || true
rm -rf "$OLD"
if ! git -C "$ROOT" worktree add --detach "$OLD" 7643d36c7b4cd590e7b62226f08931b736d9ab7d \
     >"$BASE/worktree.log" 2>&1; then
  printf 'P1-C-R1_OLD_REPRO_FAIL: worktree\n' >&2
  exit 1
fi
cp "$DATA/directed.dut.jsonl" "$DATA/directed.spike.log" "$DATA/directed.regs.json" \
   "$BASE/data/"
if [ -z "$END" ]; then
  END="$(riscv64-unknown-elf-nm "$DATA/directed.elf" | awk '$3=="end"{print $1}')"
fi
if [ -z "$END" ]; then printf 'P1-C-R1_OLD_REPRO_FAIL: no end pc\n' >&2; exit 1; fi

python3 "$ROOT/scripts/p1c_make_trace_variant.py" --in "$BASE/data/directed.dut.jsonl" \
  --out "$BASE/data/extra_endpoint.jsonl" --mode extra_endpoint
python3 "$ROOT/scripts/p1c_make_trace_variant.py" --in "$BASE/data/directed.dut.jsonl" \
  --out "$BASE/data/priv_s.jsonl" --mode priv
python3 "$ROOT/scripts/p1c_make_trace_variant.py" --in "$BASE/data/directed.dut.jsonl" \
  --out "$BASE/data/dirty_pc.jsonl" --mode dirty_pc

fail=0
check_old() {
  local name="$1" want_rc="$2" want="$3" data="$4"; shift 4
  if run_logged "$name" python3 "$OLD/scripts/p1c_diff.py" --dut "$data" \
       --spike "$BASE/data/directed.spike.log" --regs "$BASE/data/directed.regs.json" \
       --end-pc "0x$END" "$@"; then rc=0; else rc=$?; fi
  if [ "$rc" != "$want_rc" ] || ! grep -qF "$want" "$BASE/$name.log"; then
    printf 'P1-C-R1_OLD_REPRO_FAIL: %s rc=%s expected=%s\n' "$name" "$rc" "$want_rc" >&2
    fail=1
  else
    printf 'P1-C-R1_OLD_REPRO_PASS: %s rc=%s marker=%s\n' "$name" "$rc" "$want"
  fi
}

# Original checker stops at the first endpoint: appended normal records and a
# priv=S record are incorrectly accepted.
check_old f01-extra-endpoint 0 "P1C_DIFF_PASS" "$BASE/data/extra_endpoint.jsonl"
check_old f01-priv-s 0 "P1C_DIFF_PASS" "$BASE/data/priv_s.jsonl"
# Original checker reports the requested RD injection even though the baseline
# already has an unrelated PC error.
check_old f02-dirty-baseline-rd 1 "P1C_DIFF_NEGATIVE_RD_DETECTED" \
  "$BASE/data/dirty_pc.jsonl" --inject rd

if [ "$fail" -eq 0 ]; then
  printf 'P1-C-R1_OLD_REPRO_ALL_PASS\n'
  exit 0
fi
printf 'P1-C-R1_OLD_REPRO_ALL_FAIL\n' >&2
exit 1
