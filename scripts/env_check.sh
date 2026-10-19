#!/usr/bin/env bash
# P0-01 environment check. Prints real values and fails if a required tool is
# missing or cannot produce a valid RV32I/ILP32 object.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/scripts/toolchain.lock"
BUILD="$ROOT/build/envcheck"
CROSS="${CROSS_PREFIX:-riscv64-unknown-elf-}"
VERILATOR="${VERILATOR:-verilator}"
SPIKE="${SPIKE:-spike}"

fail=0
note() { printf '%s\n' "$*"; }
bad() { printf 'ENV_CHECK_FAIL: %s\n' "$*" >&2; fail=1; }

note "== environment =="
note "date_utc: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
note "timezone: $(date '+%Z %z')"
note "repo_root: $ROOT"
note "git_head: $(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
note "git_branch: $(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
note "git_status:"
git -C "$ROOT" status --short 2>&1 | sed 's/^/  /'
note "os: $(. /etc/os-release && printf '%s %s' "$NAME" "$VERSION_ID")"
note "kernel: $(uname -srmo)"
note "arch: $(uname -m)"
note "nproc: $(nproc 2>/dev/null || echo unknown)"
note "uid: $(id -u) ($(id -un 2>/dev/null || echo unknown))"
note "mem_total: $(awk '/MemTotal/ {print $2 " kB"}' /proc/meminfo 2>/dev/null)"
note "disk_workspace: $(df -h "$ROOT" 2>/dev/null | awk 'NR==2 {print $2 " total, " $4 " available"}')"
note "ulimit_nofile: $(ulimit -n 2>/dev/null || echo unknown)"
note "ulimit_nproc: $(ulimit -u 2>/dev/null || echo unknown)"

note ""
note "== toolchain lock =="
if [ -r "$LOCK" ]; then
  sed 's/^/  /' "$LOCK"
else
  bad "missing $LOCK"
fi

note ""
note "== required commands =="
for tool in git make gcc g++ python3 "$VERILATOR" \
            "${CROSS}gcc" "${CROSS}readelf" "${CROSS}objdump" \
            "${CROSS}nm" "$SPIKE"; do
  if command -v "$tool" >/dev/null 2>&1; then
    note "  OK   $tool -> $(command -v "$tool")"
  else
    note "  MISS $tool"
    bad "required command not found: $tool"
  fi
done

note ""
note "== versions =="
note "  git: $(git --version 2>&1)"
note "  make: $(make --version 2>&1 | head -1)"
note "  gcc: $(gcc --version 2>&1 | head -1)"
note "  g++: $(g++ --version 2>&1 | head -1)"
note "  python3: $(python3 --version 2>&1)"
if command -v "$VERILATOR" >/dev/null 2>&1; then
  note "  verilator: $("$VERILATOR" --version 2>&1 | tail -1)"
fi
if command -v "${CROSS}gcc" >/dev/null 2>&1; then
  note "  ${CROSS}gcc: $("${CROSS}gcc" --version 2>&1 | head -1)"
fi
if command -v "$SPIKE" >/dev/null 2>&1; then
  note "  spike_banner: $("$SPIKE" --help 2>&1 | head -1)"
  note "  spike_path: $(command -v "$SPIKE")"
fi

note ""
note "== RV32I/ILP32 compile probe =="
rm -rf "$BUILD"
mkdir -p "$BUILD"
cat >"$BUILD/probe.c" <<'EOF'
int probe(int x) { return x * 3 + 1; }
EOF
if "${CROSS}gcc" -march=rv32i -mabi=ilp32 -mcmodel=medany -mno-relax \
      -nostdlib -ffreestanding -c "$BUILD/probe.c" -o "$BUILD/probe.o" \
      >"$BUILD/compile.log" 2>&1; then
  note "  compile_exit: 0"
else
  note "  compile_exit: nonzero"
  sed 's/^/  /' "$BUILD/compile.log" >&2
  bad "RV32I/ILP32 compile probe failed"
fi
if [ -f "$BUILD/probe.o" ]; then
  note "  elf_header:"
  "${CROSS}readelf" -h "$BUILD/probe.o" 2>&1 | \
    grep -E 'Class:|Machine:|Type:' | sed 's/^/    /'
  note "  attributes:"
  "${CROSS}readelf" -A "$BUILD/probe.o" 2>&1 | \
    grep -E 'Tag_RISCV_arch|Tag_RISCV_stack_align' | sed 's/^/    /'
  if "${CROSS}readelf" -h "$BUILD/probe.o" 2>&1 | grep -q 'ELF32' &&
     "${CROSS}readelf" -h "$BUILD/probe.o" 2>&1 | grep -q 'RISC-V' &&
     "${CROSS}readelf" -A "$BUILD/probe.o" 2>&1 | grep -q 'rv32i2p1'; then
    note "  rv32i_ilp32_object: OK"
  else
    bad "compiled object is not ELF32 RISC-V rv32i"
  fi
fi

note ""
if [ "$fail" -eq 0 ]; then
  note "ENV_CHECK_PASS"
  exit 0
fi
note "ENV_CHECK_FAIL"
exit 1
