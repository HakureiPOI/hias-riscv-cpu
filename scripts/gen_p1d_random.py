#!/usr/bin/env python3
"""Generate deterministic P1-D random integer+RAM Load/Store programs."""
from __future__ import annotations
import argparse
import random
from pathlib import Path

R_OPS = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
I_OPS = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SH_OPS = ["slli", "srli", "srai"]
BR_OPS = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
LOAD = [("lb", 1), ("lh", 2), ("lw", 4), ("lbu", 1), ("lhu", 2)]
STORE = [("sb", 1), ("sh", 2), ("sw", 4)]


def reg(rng):
    return rng.randrange(1, 30)


def mem_off(rng, width):
    return rng.randrange(0, (256 - width) // width + 1) * width


def arith(rng, lines, serial):
    k = rng.randrange(100)
    if k < 40:
        lines.append(f"    {rng.choice(R_OPS)} x{reg(rng)}, x{reg(rng)}, x{reg(rng)}")
    elif k < 72:
        lines.append(f"    {rng.choice(I_OPS)} x{reg(rng)}, x{reg(rng)}, {rng.randrange(-2048, 2048)}")
    elif k < 84:
        lines.append(f"    {rng.choice(SH_OPS)} x{reg(rng)}, x{reg(rng)}, {rng.randrange(32)}")
    else:
        lab = f".Lskip{serial[0]}"
        serial[0] += 1
        lines.append(f"    {rng.choice(BR_OPS)} x{reg(rng)}, x{reg(rng)}, {lab}")
        lines.append(f"    {rng.choice(R_OPS)} x{reg(rng)}, x{reg(rng)}, x{reg(rng)}")
        lines.append(f"{lab}:")


def memop(rng, lines, store):
    if not store:
        name, width = rng.choice(LOAD)
        lines.append(f"    {name} x{reg(rng)}, {mem_off(rng, width)}(x31)")
    else:
        name, width = rng.choice(STORE)
        lines.append(f"    {name} x{reg(rng)}, {mem_off(rng, width)}(x31)")


def generate(seed: int, loops: int, body: int, out: Path):
    rng = random.Random(seed)
    lines = [
        "# AUTO-GENERATED P1-D random integer+Load/Store program",
        f"# seed={seed} loops={loops} body={body}",
        "    .option norvc",
        '    .section .text.init, "ax", @progbits',
        "    .globl _start",
        "_start:",
    ]
    for r in range(1, 32):
        lines.append(f"    li x{r}, 0x{rng.randrange(1 << 32):08x}")
    lines.append("    li x31, 0x80018000")
    lines.append("    li x30, 64")
    lines.append("    li x5, 0x10203040")
    lines.append(".Linit:")
    lines.append("    sw x5, 0(x31)")
    lines.append("    addi x5, x5, 0x111")
    lines.append("    addi x31, x31, 4")
    lines.append("    addi x30, x30, -1")
    lines.append("    bne x30, x0, .Linit")
    lines.append("    li x31, 0x80018000")
    lines.append(f"    li x30, {loops}")
    lines.append(".Lloop:")
    serial = [0]
    for _ in range(body):
        arith(rng, lines, serial)
    memop(rng, lines, False)
    memop(rng, lines, True)
    lines.append("    addi x30, x30, -1")
    lines.append("    bne x30, x0, .Lloop")
    for _ in range(12):
        arith(rng, lines, serial)
        memop(rng, lines, False)
        memop(rng, lines, True)
    lines.append("    li x31, 0x80018000")
    for r in range(1, 17):
        lines.append(f"    lw x{r}, {(r-1)*4}(x31)")
    lines.append("end:")
    lines.append("    jal x0, end")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=lambda x: int(x, 0), required=True)
    ap.add_argument("--loops", type=int, default=80)
    ap.add_argument("--body", type=int, default=16)
    a = ap.parse_args()
    generate(a.seed, a.loops, a.body, Path(a.out))


if __name__ == "__main__":
    main()
