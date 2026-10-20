#!/usr/bin/env python3
"""P1-C DUT vs Spike subset differential.

DUT records are source=dut hias-retire/2 normal records produced by
verification/p1c/tb/tb_integer.cpp.  Spike records are normalized from
--log-commits.  Reference next_pc is derived from the next committed PC (or the
endpoint PC for the last record) and is marked as derived, never as directly
observed.  Reference Token is not observable; only the DUT token is asserted.
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


class DiffError(Exception):
    def __init__(self, msg: str, field: str = "", index: int = -1):
        super().__init__(msg)
        self.field = field
        self.index = index


def parse_spike(path: Path, end_pc: int):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = SPIKE_RE.match(line)
        if not m:
            raise DiffError(f"unparsable Spike line: {line!r}")
        pc = int(m["pc"], 16)
        instr = int(m["instr"], 16)
        rd = int(m["rd"]) if m["rd"] is not None else None
        rdval = int(m["rdval"], 16) if m["rdval"] else None
        mem = m["memaddr"]
        if mem is not None:
            raise DiffError(f"unexpected memory access in integer subset: {line!r}")
        rows.append({
            "pc": pc, "instr": instr, "priv": int(m["priv"]),
            "rd_we": rd is not None and rd != 0,
            "rd": rd if rd is not None else 0,
            "rd_data": rdval if rd is not None and rd != 0 else None,
        })
        if pc == end_pc:
            break
    if not rows or rows[-1]["pc"] != end_pc:
        raise DiffError("Spike never reached endpoint")
    return rows


def read_dut(path: Path, end_pc: int):
    records = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            r = json.loads(line)
        except json.JSONDecodeError as exc:
            raise DiffError(f"DUT trace line {number}: invalid JSON: {exc}")
        if r.get("schema") != "hias-retire/2" or r.get("kind") != "normal":
            raise DiffError(f"DUT trace line {number}: schema/kind")
        if r.get("source") != "dut":
            raise DiffError(f"DUT trace line {number}: source must be dut")
        if not r.get("token_valid") or not r.get("next_pc_valid"):
            raise DiffError(f"DUT trace line {number}: missing token/next_pc")
        records.append(r)
        if r["pc"] == end_pc:
            break
    if not records or records[-1]["pc"] != end_pc:
        raise DiffError("DUT never reached endpoint")
    return records


def regs_from_reference(rows):
    regs = [0] * 32
    for row in rows:
        if row["rd_we"]:
            regs[row["rd"]] = row["rd_data"] & 0xffffffff
    regs[0] = 0
    return regs


def check_dut_internal(records):
    for i, r in enumerate(records):
        tok = r.get("token")
        if not isinstance(tok, dict) or tok.get("idx") != 0:
            raise DiffError(f"DUT token idx at index {i}: {tok!r}", "token", i)
        if tok.get("gen") != (i & 0xff):
            raise DiffError(f"DUT token gen at index {i}: {tok.get('gen')} != {i & 0xff}",
                            "token", i)
        if r.get("csr_valid") or r.get("mem_valid"):
            raise DiffError(f"DUT CSR/mem retirement at index {i}", "kind", i)
        if r.get("rd_we") and r.get("rd") == 0:
            raise DiffError(f"DUT x0 write at index {i}", "rd", i)


def compare(records, rows, end_pc):
    if len(records) != len(rows):
        raise DiffError(f"retire count: dut={len(records)} ref={len(rows)}",
                        "count", min(len(records), len(rows)))
    for i, (d, s) in enumerate(zip(records, rows)):
        ref_next = rows[i + 1]["pc"] if i + 1 < len(rows) else end_pc
        checks = [
            ("pc", d["pc"], s["pc"]),
            ("instr", d["instr"], s["instr"]),
            ("priv", "M", {3: "M", 1: "S", 0: "U"}.get(s["priv"], "?")),
            ("rd_we", bool(d["rd_we"]), s["rd_we"]),
            ("next_pc", d["next_pc"], ref_next),
        ]
        for name, got, want in checks:
            if got != want:
                raise DiffError(f"first difference index={i} field={name} "
                                f"dut={got} ref={want}", name, i)
        if s["rd_we"]:
            if d["rd"] != s["rd"] or d["rd_data"] != s["rd_data"]:
                raise DiffError(f"first difference index={i} field=rd_wdata "
                                f"dut={d['rd']}:{d['rd_data']} "
                                f"ref={s['rd']}:{s['rd_data']}", "rd_wdata", i)
    return len(records)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--dut", required=True)
    ap.add_argument("--spike", required=True)
    ap.add_argument("--regs", required=True)
    ap.add_argument("--end-pc", required=True, type=lambda x: int(x, 0))
    ap.add_argument("--inject", choices=["", "pc", "instr", "rd", "next_pc",
                                         "missing", "duplicate", "token"],
                    default="")
    args = ap.parse_args(argv)

    try:
        rows = parse_spike(Path(args.spike), args.end_pc)
        records = read_dut(Path(args.dut), args.end_pc)
        check_dut_internal(records)
        regs = json.loads(Path(args.regs).read_text(encoding="utf-8"))
        if regs.get("final_pc") != args.end_pc:
            raise DiffError("DUT final_pc does not match endpoint", "final_pc")
        if regs.get("retire_count") != len(records):
            raise DiffError("DUT retire_count mismatch", "count")
        ref_regs = regs_from_reference(rows)
        if regs.get("regs") != ref_regs:
            for i, (a, b) in enumerate(zip(regs.get("regs", []), ref_regs)):
                if a != b:
                    raise DiffError(f"final register x{i}: dut={a} ref={b}",
                                    f"x{i}", i)
            raise DiffError("final register vector mismatch", "regs")
        if rows[-1]["pc"] != args.end_pc:
            raise DiffError("reference endpoint mismatch", "final_pc")

        injected = args.inject
        if injected:
            records = [dict(r) for r in records]
            i = len(records) // 2
            if injected == "missing":
                records.pop(i)
            elif injected == "duplicate":
                records.insert(i, dict(records[i]))
            elif injected == "pc":
                records[i]["pc"] = (records[i]["pc"] + 4) & 0xffffffff
            elif injected == "instr":
                records[i]["instr"] ^= 1
            elif injected == "rd":
                if not records[i]["rd_we"]:
                    for j, r in enumerate(records):
                        if r["rd_we"]:
                            i = j
                            break
                records[i]["rd_data"] = (records[i]["rd_data"] + 1) & 0xffffffff
            elif injected == "next_pc":
                records[i]["next_pc"] = (records[i]["next_pc"] + 4) & 0xffffffff
            elif injected == "token":
                records[i]["token"]["gen"] = (records[i]["token"]["gen"] + 1) & 0xff
            try:
                if injected == "token":
                    check_dut_internal(records)
                else:
                    compare(records, rows, args.end_pc)
            except DiffError as exc:
                print(f"P1C_DIFF_NEGATIVE_{injected.upper()}_DETECTED: {exc}")
                return 1
            print(f"P1C_DIFF_NEGATIVE_{injected.upper()}_NOT_DETECTED")
            return 2

        n = compare(records, rows, args.end_pc)
        print(f"P1C_DIFF_PASS retires={n} endpoint=0x{args.end_pc:08x} "
              f"reference_next_pc=derived")
        return 0
    except DiffError as exc:
        where = f" index={exc.index}" if exc.index >= 0 else ""
        field = f" field={exc.field}" if exc.field else ""
        print(f"P1C_DIFF_FAIL:{where}{field}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
