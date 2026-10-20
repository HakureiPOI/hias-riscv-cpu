#!/usr/bin/env bash
# Reproduce F01/F02/F03 against the original P1-B implementation 278f6f7.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${P1_B_R1_REPRO_EVIDENCE:-$ROOT/verification/evidence/P1-B-R1/old-repro}"
OLD="${P1_B_R1_OLD_WORKTREE:-/tmp/opencode/p1b-old-worktree}"
VERILATOR="${VERILATOR:-verilator}"
HOST_TIMEOUT="${P1_B_R1_REPRO_TIMEOUT:-120}"
KILL_AFTER="${P1_B_R1_REPRO_KILL_AFTER:-5}"

mkdir -p "$BASE/build" "$BASE/source" || exit 1

fail=0
pass() { printf 'P1-B-R1_OLD_REPRO_PASS: %s\n' "$*"; }
bad() { printf 'P1-B-R1_OLD_REPRO_FAIL: %s\n' "$*" >&2; fail=1; }

run_logged() {
  local name="$1"; shift
  local log="$BASE/$name.log"
  local rc
  {
    printf 'command: timeout -k %ss %ss %s\n' "$KILL_AFTER" "$HOST_TIMEOUT" "$*"
    timeout -k "${KILL_AFTER}s" "${HOST_TIMEOUT}s" "$@" 2>&1
    rc=$?
    printf 'exit: %s\n' "$rc"
  } >"$log" 2>&1
  return "$rc"
}

git -C "$ROOT" worktree remove --force "$OLD" >/dev/null 2>&1 || true
rm -rf "$OLD"
if ! git -C "$ROOT" worktree add --detach "$OLD" 278f6f7 >"$BASE/worktree.log" 2>&1; then
  bad "cannot create old worktree"
  cat "$BASE/worktree.log" >&2
  exit 1
fi

# F01: old decoder rejects the reviewed legal JAL words.
if run_logged f01-jal-build "$VERILATOR" --cc --exe --build --assert \
     -I"$OLD/rtl/include" --top-module decode_tb_top \
     -Mdir "$BASE/build/f01" -CFLAGS -std=c++17 \
     "$OLD/rtl/include/core_config_pkg.sv" "$OLD/rtl/include/core_types_pkg.sv" \
     "$OLD/rtl/frontend/p1_decode.sv" \
     "$OLD/verification/p1b/tb/decode_tb_top.sv" \
     "$ROOT/verification/p1b/old_repro/tb_jal_old.cpp" -o f01; then
  if run_logged f01-jal-run "$BASE/build/f01/f01"; then
    if grep -qF 'OLD_F01_JAL_ILLEGAL' "$BASE/f01-jal-run.log"; then
      pass "F01 old JAL illegal reproduced"
    else
      bad "F01 old JAL defect not reproduced"
    fi
  else
    bad "F01 old JAL run failed"
  fi
else
  bad "F01 old JAL build failed"
fi

# F02: old redirect/accept leak and old wrong-response early release.
if run_logged f02-build "$VERILATOR" --cc --exe --build --assert \
     -I"$OLD/rtl/include" --top-module frontend_tb_top -GGEN_W=2 \
     -Mdir "$BASE/build/f02" -CFLAGS -std=c++17 \
     "$OLD/rtl/include/core_config_pkg.sv" "$OLD/rtl/include/core_types_pkg.sv" \
     "$OLD/rtl/soc/ram_128k.sv" "$OLD/rtl/soc/ram_bridge.sv" \
     "$OLD/rtl/frontend/p1_decode.sv" "$OLD/rtl/frontend/p1_fetch.sv" \
     "$OLD/rtl/frontend/p1_frontend_core.sv" \
     "$OLD/verification/p1b/tb/frontend_tb_top.sv" \
     "$ROOT/verification/p1b/old_repro/tb_f02_old.cpp" -o f02; then
  if run_logged f02-run "$BASE/build/f02/f02"; then
    if grep -qF 'OLD_F02A_REDIRECT_ACCEPT_LEAK' "$BASE/f02-run.log" &&
       grep -qF 'OLD_F02B_CANCEL_WRONG_RESPONSE_RELEASED' "$BASE/f02-run.log"; then
      pass "F02 old redirect/accept and cancellation defects reproduced"
    else
      bad "F02 old defects not both reproduced"
    fi
  else
    bad "F02 old run failed"
  fi
else
  bad "F02 old build failed"
fi

# F03: keep the old TB's per-seed errors=0 clearing, but make its +mismatch
# injection continue into the normal flow instead of returning immediately.
cp "$OLD/verification/p1b/tb/tb_frontend.cpp" \
   "$BASE/source/tb_frontend_f03_patched.cpp"
python3 - "$BASE/source/tb_frontend_f03_patched.cpp" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
block = """  if (mismatch_probe) {
    tb.wait_accept(RESET_VECTOR);
    if (tb.errors == 0) {
      std::printf(\"P1-B_FRONTEND_NEGATIVE_NOT_DETECTED\\n\");
      delete dut;
      return 2;
    }
    std::printf(\"P1-B_FRONTEND_NEGATIVE_MISMATCH_DETECTED\\n\");
    delete dut;
    return 1;
  }

"""
if block not in s:
    raise SystemExit("F03 patch anchor not found")
s = s.replace(block, "")
# Restore the injected expectation after the basic directional image so the
# later normal phases are unaffected; the old checker still clears the early
# error at the first random seed.
anchor = "  tb.drain_response_counters();\n  std::printf(\"P1-B_FRONTEND_BASIC_PASS"
if anchor not in s:
    raise SystemExit("F03 restore anchor not found")
s = s.replace(anchor,
    "  tb.drain_response_counters();\n"
    "  if (mismatch_probe) tb.image[RESET_VECTOR].op ^= 1u;\n"
    "  std::printf(\"P1-B_FRONTEND_BASIC_PASS")
open(p, "w").write(s)
PY
cp "$BASE/source/tb_frontend_f03_patched.cpp" \
   "$OLD/verification/p1b/tb/tb_frontend_f03.cpp"
diff -u "$OLD/verification/p1b/tb/tb_frontend.cpp" \
        "$OLD/verification/p1b/tb/tb_frontend_f03.cpp" \
        >"$BASE/source/f03_patch.diff" || true

if run_logged f03-build "$VERILATOR" --cc --exe --build --assert \
     -I"$OLD/rtl/include" --top-module frontend_tb_top -GGEN_W=2 \
     -Mdir "$BASE/build/f03" -CFLAGS "-std=c++17 -DP1B_GEN_W=2" \
     "$OLD/rtl/include/core_config_pkg.sv" "$OLD/rtl/include/core_types_pkg.sv" \
     "$OLD/rtl/soc/ram_128k.sv" "$OLD/rtl/soc/ram_bridge.sv" \
     "$OLD/rtl/frontend/p1_decode.sv" "$OLD/rtl/frontend/p1_fetch.sv" \
     "$OLD/rtl/frontend/p1_frontend_core.sv" \
     "$OLD/verification/p1b/tb/frontend_tb_top.sv" \
     "$OLD/verification/p1b/tb/tb_frontend_f03.cpp" -o f03; then
  if run_logged f03-run "$BASE/build/f03/f03" +mismatch; then
    if grep -qF 'P1-B_FRONTEND_PASS' "$BASE/f03-run.log"; then
      printf 'OLD_F03_ERROR_CLEARED\n' >>"$BASE/f03-run.log"
      pass "F03 old early error forgotten (injected run exit 0)"
    else
      bad "F03 old run did not report the expected clearance path"
    fi
  else
    bad "F03 injected old run was nonzero; expected the old bug"
  fi
else
  bad "F03 old build failed"
fi

{
  printf 'P1-B-R1 old reproduction summary\n'
  printf 'old_commit: 278f6f7e13eb423952c1119a28d1900f3ac57356\n'
  if [ "$fail" -eq 0 ]; then printf 'result: PASS\n'; else printf 'result: FAIL\n'; fi
} >"$BASE/summary.log"
cat "$BASE/summary.log"
if [ "$fail" -eq 0 ]; then printf 'P1-B-R1_OLD_REPRO_ALL_PASS\n'; exit 0; fi
printf 'P1-B-R1_OLD_REPRO_ALL_FAIL\n' >&2
exit 1
