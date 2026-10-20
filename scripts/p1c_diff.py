#!/usr/bin/env python3
"""P1-C DUT vs Spike subset differential (R1).

The DUT file is consumed in full. Exactly one normal endpoint retirement is
allowed and it must be the final record. The bounded Spike log may continue
with the endpoint self-loop; that suffix is validated and used only to derive
the last reference next_pc. Reference Token is not observable.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SPIKE_RE = re.compile(
    r"^core\s+\d+:\s+(?P<priv>\d)\s+(?P<pc>0x[0-9a-f]+)\s+"
    r"\((?P<instr>0x[0-9a-f]+)\)"
    r"(?:\s+x(?P<rd>\d+)\s+(?P<rdval>0x[0-9a-f]+))?"
    r"(?:\s+mem\s+(?P<memaddr>0x[0-9a-f]+)"
    r"(?:\s+(?P<memval>0x[0-9a-f]+))?)?\s*$"
)
PRIV = {3: "M", 1: "S", 0: "U"}


class DiffError(Exception):
    pass


class Diff:
    __slots__ = ("index", "field", "dut", "ref")
    def __init__(self, index: int, field: str, dut, ref):
        self.index, self.field, self.dut, self.ref = index, field, dut, ref
    def __str__(self):
        return f"index={self.index} field={self.field} dut={self.dut} ref={self.ref}"


def parse_spike(path: Path, end_pc: int):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = SPIKE_RE.match(line)
        if not m:
            raise DiffError(f"unparsable Spike line: {line!r}")
        priv = int(m["priv"])
        if priv not in PRIV:
            raise DiffError(f"unknown Spike privilege {m['priv']}")
        if m["memaddr"] is not None:
            raise DiffError(f"unexpected memory access in integer subset: {line!r}")
        rd = int(m["rd"]) if m["rd"] is not None else None
        rows.append({
            "pc": int(m["pc"], 16), "instr": int(m["instr"], 16),
            "priv": PRIV[priv],
            "rd_we": rd is not None and rd != 0,
            "rd": rd if rd is not None else 0,
            "rd_data": int(m["rdval"], 16) if rd is not None and rd != 0 else None,
        })
    first = next((i for i, r in enumerate(rows) if r["pc"] == end_pc), None)
    if first is None:
        raise DiffError("Spike never reached endpoint")
    endpoint_instr = rows[first]["instr"]
    for r in rows[first + 1:]:
        if r["pc"] != end_pc or r["instr"] != endpoint_instr:
            raise DiffError("Spike endpoint suffix is not a stable self-loop")
    if first + 1 >= len(rows):
        raise DiffError("Spike log has no successor after endpoint")
    return rows[:first + 1], rows[first + 1]["pc"]


def read_dut(path: Path, end_pc: int):
    lines = [ln for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip()]
    records = []
    endpoint_indexes = []
    for number, line in enumerate(lines, 1):
        try:
            r = json.loads(line)
        except json.JSONDecodeError as exc:
            raise DiffError(f"DUT trace line {number}: invalid JSON: {exc}")
        if r.get("schema") != "hias-retire/2" or r.get("kind") != "normal":
            raise DiffError(f"DUT trace line {number}: schema/kind")
        if r.get("source") != "dut":
            raise DiffError(f"DUT trace line {number}: source")
        if not r.get("token_valid") or not r.get("next_pc_valid"):
            raise DiffError(f"DUT trace line {number}: token/next_pc invalid")
        tok = r.get("token")
        if not isinstance(tok, dict) or tok.get("idx") != 0:
            raise DiffError(f"DUT trace line {number}: token idx")
        if tok.get("gen") != (len(records) & 0xff):
            raise DiffError(f"DUT trace line {number}: token generation")
        if r.get("csr_valid") or r.get("mem_valid"):
            raise DiffError(f"DUT trace line {number}: CSR/mem retirement")
        if r.get("rd_we") and r.get("rd") == 0:
            raise DiffError(f"DUT trace line {number}: x0 write")
        if r.get("pc") == end_pc:
            endpoint_indexes.append(len(records))
        records.append(r)
    if not records or records[-1].get("pc") != end_pc:
        raise DiffError("DUT never ended at the unique endpoint")
    if endpoint_indexes != [len(records) - 1]:
        raise DiffError("DUT endpoint retirement is not unique/final")
    return records


def collect_compare(records, rows, tail_next):
    diffs = []
    if len(records) != len(rows):
        diffs.append(Diff(min(len(records), len(rows)), "count",
                          len(records), len(rows)))
        return diffs
    for i, (d, s) in enumerate(zip(records, rows)):
        ref_next = rows[i + 1]["pc"] if i + 1 < len(rows) else tail_next
        for field, got, want in (
            ("pc", d["pc"], s["pc"]),
            ("instr", d["instr"], s["instr"]),
            ("priv", d["priv"], s["priv"]),
            ("rd_we", bool(d["rd_we"]), s["rd_we"]),
            ("next_pc", d["next_pc"], ref_next),
        ):
            if got != want:
                diffs.append(Diff(i, field, got, want))
        if s["rd_we"] and (d["rd"] != s["rd"] or d["rd_data"] != s["rd_data"]):
            diffs.append(Diff(i, "rd_wdata", (d["rd"], d["rd_data"]),
                              (s["rd"], s["rd_data"])))
    return diffs


def collect_token(records):
    diffs = []
    for i, r in enumerate(records):
        tok = r.get("token", {})
        if tok.get("idx") != 0:
            diffs.append(Diff(i, "token", tok, "idx=0"))
        if tok.get("gen") != (i & 0xff):
            diffs.append(Diff(i, "token", tok, f"gen={i & 0xff}"))
    return diffs


def collect_regs(regs, rows, end_pc, count):
    diffs = []
    if regs.get("final_pc") != end_pc:
        diffs.append(Diff(count - 1, "final_pc", regs.get("final_pc"), end_pc))
    if regs.get("retire_count") != count:
        diffs.append(Diff(count - 1, "retire_count", regs.get("retire_count"), count))
    ref_regs = [0] * 32
    for row in rows:
        if row["rd_we"]:
            ref_regs[row["rd"]] = row["rd_data"] & 0xffffffff
    ref_regs[0] = 0
    got_regs = regs.get("regs", [])
    if len(got_regs) != 32:
        diffs.append(Diff(count - 1, "regs", len(got_regs), 32))
        return diffs
    for r, (a, b) in enumerate(zip(got_regs, ref_regs)):
        if a != b:
            diffs.append(Diff(count - 1, f"x{r}", a, b))
    return diffs


def baseline(records, rows, tail_next, regs):
    diffs = collect_compare(records, rows, tail_next)
    diffs += collect_token(records)
    diffs += collect_regs(regs, rows, records[-1]["pc"], len(records))
    if diffs:
        raise DiffError(f"baseline: {diffs[0]}")
    return len(records)


def apply_injection(records, kind):
    out = [dict(r) for r in records]
    i = len(out) // 2
    if kind == "missing":
        out.pop(i)
        return out, ("count", min(i, len(out)))
    if kind == "duplicate":
        out.insert(i, dict(out[i]))
        return out, ("count", i)
    if kind == "pc":
        out[i]["pc"] = (out[i]["pc"] + 4) & 0xffffffff
        return out, ("pc", i)
    if kind == "instr":
        out[i]["instr"] ^= 1
        return out, ("instr", i)
    if kind == "next_pc":
        out[i]["next_pc"] = (out[i]["next_pc"] + 4) & 0xffffffff
        return out, ("next_pc", i)
    if kind == "rd":
        j = next((k for k, r in enumerate(out) if r["rd_we"]), i)
        out[j]["rd_data"] = (out[j]["rd_data"] + 1) & 0xffffffff
        return out, ("rd_wdata", j)
    if kind == "token":
        out[i]["token"]["gen"] = (out[i]["token"]["gen"] + 1) & 0xff
        return out, ("token", i)
    if kind == "pc_extra":
        out[i]["pc"] = (out[i]["pc"] + 4) & 0xffffffff
        j = next((k for k, r in enumerate(out) if r["rd_we"]), i)
        out[j]["rd_data"] = (out[j]["rd_data"] + 1) & 0xffffffff
        return out, ("pc", i)
    raise DiffError(f"unknown injection {kind}")


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--dut", required=True)
    ap.add_argument("--spike", required=True)
    ap.add_argument("--regs", required=True)
    ap.add_argument("--end-pc", required=True, type=lambda x: int(x, 0))
    ap.add_argument("--inject", default="",
                    choices=["", "pc", "instr", "rd", "next_pc", "missing",
                             "duplicate", "token", "pc_extra"])
    args = ap.parse_args(argv)
    try:
        rows, tail_next = parse_spike(Path(args.spike), args.end_pc)
        records = read_dut(Path(args.dut), args.end_pc)
        regs = json.loads(Path(args.regs).read_text(encoding="utf-8"))
        n = baseline(records, rows, tail_next, regs)
        if args.inject:
            injected, expected = apply_injection(records, args.inject)
            diffs = collect_compare(injected, rows, tail_next)
            if args.inject == "token":
                diffs = collect_token(injected)
            # A clean baseline was already proven; any difference must be the
            # single requested field/position (or the expected count change).
            target = [d for d in diffs if d.field == expected[0] and
                      (expected[0] == "count" or d.index == expected[1])]
            extra = [d for d in diffs if d not in target]
            tag = args.inject.upper()
            if len(target) == 1 and not extra:
                print(f"P1C_DIFF_NEGATIVE_{tag}_DETECTED: {target[0]}")
                return 1
            if not target:
                print(f"P1C_DIFF_INJECTION_WRONG_REASON: expected {expected}, "
                      f"got {[str(d) for d in diffs[:4]]}")
                return 3
            print(f"P1C_DIFF_INJECTION_EXTRA_ERRORS: target={target[0]} "
                  f"extra={[str(d) for d in extra[:4]]}")
            return 3
        print(f"P1C_DIFF_PASS retires={n} endpoint=0x{args.end_pc:08x} "
              f"reference_next_pc=derived")
        return 0
    except DiffError as exc:
        print(f"P1C_DIFF_BASELINE_FAIL: {exc}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
