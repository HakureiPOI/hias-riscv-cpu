#!/usr/bin/env python3
"""Generate deterministic P1-C random integer/control assembly programs.
Only the 29 P1-C instructions are emitted (plus assembler li/jal expansions
that stay within LUI/ADDI/JAL)."""
from __future__ import annotations
import argparse
import random
from pathlib import Path

R_OPS = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
I_OPS = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SH_OPS = ["slli", "srli", "srai"]
BR_OPS = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]


def reg(rng):
    return rng.randrange(1, 30)  # x1..x29; x30 is the loop counter


def imm12(rng):
    return rng.randrange(-2048, 2048)


def arith(rng, lines, label_serial):
    kind = rng.randrange(100)
    if kind < 42:
        lines.append(f"    {rng.choice(R_OPS)} x{reg(rng)}, x{reg(rng)}, x{reg(rng)}")
    elif kind < 75:
        lines.append(f"    {rng.choice(I_OPS)} x{reg(rng)}, x{reg(rng)}, {imm12(rng)}")
    elif kind < 88:
        lines.append(f"    {rng.choice(SH_OPS)} x{reg(rng)}, x{reg(rng)}, {rng.randrange(32)}")
    elif kind < 94:
        lines.append(f"    lui x{reg(rng)}, 0x{rng.randrange(1 << 20):05x}")
    elif kind < 97:
        lines.append(f"    auipc x{reg(rng)}, 0x{rng.randrange(1 << 20):05x}")
    else:
        # Forward branch over one arithmetic instruction.
        lab = f".Lskip{label_serial[0]}"
        label_serial[0] += 1
        lines.append(f"    {rng.choice(BR_OPS)} x{reg(rng)}, x{reg(rng)}, {lab}")
        lines.append(f"    {rng.choice(R_OPS)} x{reg(rng)}, x{reg(rng)}, x{reg(rng)}")
        lines.append(f"{lab}:")


def generate(seed: int, loops: int, body: int, out: Path):
    rng = random.Random(seed)
    lines = [
        "# AUTO-GENERATED P1-C random integer program",
        f"# seed={seed} loops={loops} body={body}",
        "    .option norvc",
        '    .section .text.init, "ax", @progbits',
        "    .globl _start",
        "_start:",
    ]
    for r in range(1, 32):
        lines.append(f"    li x{r}, 0x{rng.randrange(1 << 32):08x}")
    lines.append(f"    li x30, {loops}")
    lines.append(".Lloop:")
    serial = [0]
    for _ in range(body):
        arith(rng, lines, serial)
    lines.append("    addi x30, x30, -1")
    lines.append("    bne x30, x0, .Lloop")
    for _ in range(16):
        arith(rng, lines, serial)
    lines.append("    jal x0, end")
    lines.append("end:")
    lines.append("    jal x0, end")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=lambda x: int(x, 0), required=True)
    ap.add_argument("--loops", type=int, default=40)
    ap.add_argument("--body", type=int, default=28)
    args = ap.parse_args()
    generate(args.seed, args.loops, args.body, Path(args.out))


if __name__ == "__main__":
    main()
