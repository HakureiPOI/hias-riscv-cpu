#!/usr/bin/env python3
"""Report/check the six-branch taken/untaken matrix from a Spike log."""
import argparse
import re
import sys

RE = re.compile(r"^core\s+\d+:\s+(\d)\s+(0x[0-9a-f]+)\s+\((0x[0-9a-f]+)\)")
NAMES = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}
rows = []
ap = argparse.ArgumentParser()
ap.add_argument("--spike", required=True)
ap.add_argument("--end-pc", required=True, type=lambda x: int(x, 0))
args = ap.parse_args()
for line in open(args.spike, encoding="utf-8"):
    m = RE.match(line)
    if m:
        rows.append((int(m.group(2), 16), int(m.group(3), 16)))
end = next((i for i, (pc, _) in enumerate(rows) if pc == args.end_pc), None)
if end is None:
    print("P1C_BRANCH_MATRIX_FAIL: no endpoint", file=sys.stderr)
    sys.exit(1)
rows = rows[:end + 1]
counts = {n: [0, 0] for n in NAMES.values()}  # [untaken, taken]
for i, (pc, instr) in enumerate(rows):
    if (instr & 0x7f) != 0x63:
        continue
    name = NAMES.get((instr >> 12) & 7)
    if name is None or i + 1 >= len(rows):
        print(f"P1C_BRANCH_MATRIX_FAIL: bad branch at index {i}", file=sys.stderr)
        sys.exit(1)
    taken = rows[i + 1][0] != ((pc + 4) & 0xffffffff)
    counts[name][1 if taken else 0] += 1
bad = False
for name in ("beq", "bne", "blt", "bge", "bltu", "bgeu"):
    untaken, taken = counts[name]
    print(f"P1C_BRANCH_MATRIX {name} untaken={untaken} taken={taken}")
    if untaken == 0 or taken == 0:
        bad = True
if bad:
    print("P1C_BRANCH_MATRIX_FAIL: missing direction", file=sys.stderr)
    sys.exit(1)
print("P1C_BRANCH_MATRIX_PASS six_branches_both_directions")
