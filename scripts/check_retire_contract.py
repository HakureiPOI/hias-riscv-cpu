#!/usr/bin/env python3
"""P0-02-R1 retirement/trap contract checker and Spike converter.

Protocol version: hias-retire/2.
- DUT records must carry all hardware observations (token/next_pc valid).
- Spike-derived records must mark unavailable fields null and list them in
  not_observed_fields; derived values are listed in derived_fields.
- Synthetic records are format fixtures and are never DUT evidence.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "verification" / "spec" / "retire" / "retire_schema.json"
EXAMPLES = ROOT / "verification" / "spec" / "retire" / "examples"

NORMAL_REQUIRED = {
    "schema", "kind", "source", "seq", "token", "token_valid",
    "pc", "instr", "next_pc", "next_pc_valid", "priv",
    "rd_we", "rd", "rd_data",
    "csr_valid", "csr_rd_valid", "csr_wr_valid", "csr_addr",
    "csr_wdata", "csr_rdata",
    "mem_valid", "mem_we", "mem_va", "mem_pa", "mem_size", "mem_mask",
    "mem_wdata", "mem_rdata", "derived_fields", "not_observed_fields",
}
TRAP_REQUIRED = {
    "schema", "kind", "source", "seq", "pc", "epc", "target_pc",
    "cause", "is_interrupt", "tval", "from_priv", "to_priv",
    "mstatus_before", "mstatus_after", "cause_csr_before", "cause_csr_after",
    "epc_csr_before", "epc_csr_after",
}
BUNDLE_REQUIRED = {"schema", "kind", "slots", "trap", "seq_base"}
SOURCES = {"dut", "spike-derived", "synthetic"}
NORMAL_FIELDS = NORMAL_REQUIRED - {"derived_fields", "not_observed_fields"}
PRIVS = {"U", "S", "M"}
SIZES = {"none", "byte", "half", "word"}
SIZE_BYTES = {"byte": 1, "half": 2, "word": 4}


class RecordError(Exception):
    pass


def load_schema() -> dict:
    return json.loads(SCHEMA.read_text(encoding="utf-8"))


def is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def need_range(value, name: str, lo: int, hi: int) -> None:
    if not is_int(value) or value < lo or value > hi:
        raise RecordError(f"{name}: expected integer in [{lo},{hi}], got {value!r}")


def need_bool(value, name: str) -> None:
    if not isinstance(value, bool):
        raise RecordError(f"{name}: expected boolean, got {type(value).__name__}")


def need_str(value, name: str, allowed: set[str] | None = None) -> None:
    if not isinstance(value, str):
        raise RecordError(f"{name}: expected string")
    if allowed is not None and value not in allowed:
        raise RecordError(f"{name}: {value!r} not in {sorted(allowed)}")


def check_keys(record: dict, required: set[str], where: str) -> None:
    missing = sorted(required - set(record))
    if missing:
        raise RecordError(f"{where}: missing fields {missing}")
    extra = sorted(set(record) - required)
    if extra:
        raise RecordError(f"{where}: unknown fields {extra}")


def csr_expected(instr: int) -> dict | None:
    """Derive CSR read/write validity from the instruction encoding."""
    if (instr & 0x7f) != 0x73:
        return None
    funct3 = (instr >> 12) & 0x7
    if funct3 not in (1, 2, 3, 5, 6, 7):
        return None
    rd = (instr >> 7) & 0x1f
    rs1 = (instr >> 15) & 0x1f
    addr = (instr >> 20) & 0xfff
    if funct3 == 1:      # CSRRW
        read, write = rd != 0, True
    elif funct3 == 2:    # CSRRS
        read, write = True, rs1 != 0
    elif funct3 == 3:    # CSRRC
        read, write = True, rs1 != 0
    elif funct3 == 5:    # CSRRWI
        read, write = rd != 0, True
    elif funct3 == 6:    # CSRRSI
        read, write = True, rs1 != 0
    else:                # CSRRCI
        read, write = True, rs1 != 0
    return {"addr": addr, "read": read, "write": write}


def check_csr(record: dict) -> None:
    expected = csr_expected(record["instr"])
    if expected is None:
        if record["csr_valid"]:
            raise RecordError("csr_valid set on a non-CSR instruction")
        return
    if not record["csr_valid"]:
        raise RecordError("CSR instruction missing csr_valid")
    if record["csr_addr"] != expected["addr"]:
        raise RecordError("csr_addr does not match instruction")
    if record["csr_rd_valid"] != expected["read"]:
        raise RecordError("csr_rd_valid does not match CSR read rule")
    if record["csr_wr_valid"] != expected["write"]:
        raise RecordError("csr_wr_valid does not match CSR write rule")


def expected_mask(size: str, addr: int) -> int:
    width = SIZE_BYTES[size]
    if size in ("half", "word") and addr % width != 0:
        raise RecordError(f"unaligned {size} access at 0x{addr:x}")
    return ((1 << width) - 1) << (addr & 3)


def validate_normal(record: dict) -> None:
    check_keys(record, NORMAL_REQUIRED, "normal")
    if record["schema"] != "hias-retire/2":
        raise RecordError("unsupported schema")
    if record["kind"] != "normal":
        raise RecordError("kind must be normal")
    need_str(record["source"], "source", SOURCES)
    need_range(record["seq"], "seq", 0, 1 << 62)
    need_str(record["priv"], "priv", PRIVS)
    for name in ("derived_fields", "not_observed_fields"):
        if not isinstance(record[name], list) or not all(isinstance(x, str) for x in record[name]):
            raise RecordError(f"{name} must be a list of strings")
        unknown = sorted(set(record[name]) - NORMAL_FIELDS)
        if unknown:
            raise RecordError(f"{name}: unknown field names {unknown}")
    for name in record["not_observed_fields"]:
        if record[name] is not None:
            raise RecordError(f"{name} is listed as not observed but has a value")
    for name in record["derived_fields"]:
        if record[name] is None:
            raise RecordError(f"{name} is listed as derived but has no value")
    both = set(record["derived_fields"]) & set(record["not_observed_fields"])
    if both:
        raise RecordError(f"fields both derived and not observed: {sorted(both)}")

    need_bool(record["token_valid"], "token_valid")
    need_bool(record["next_pc_valid"], "next_pc_valid")

    if record["token_valid"]:
        token = record["token"]
        if not isinstance(token, dict) or set(token) != {"idx", "gen"}:
            raise RecordError("token must be null or {idx, gen}")
        need_range(token["idx"], "token.idx", 0, 31)
        need_range(token["gen"], "token.gen", 0, 255)
        if "token" in record["not_observed_fields"]:
            raise RecordError("token is both valid and not observed")
    else:
        if record["token"] is not None:
            raise RecordError("token_valid=false requires token=null")
        if "token" not in record["not_observed_fields"]:
            raise RecordError("missing token must be listed in not_observed_fields")

    need_range(record["pc"], "pc", 0, 0xffffffff)
    need_range(record["instr"], "instr", 0, 0xffffffff)
    if record["next_pc_valid"]:
        need_range(record["next_pc"], "next_pc", 0, 0xffffffff)
        if "next_pc" in record["not_observed_fields"]:
            raise RecordError("next_pc is both valid and not observed")
    else:
        if record["next_pc"] is not None:
            raise RecordError("next_pc_valid=false requires next_pc=null")
        if "next_pc" not in record["not_observed_fields"]:
            raise RecordError("missing next_pc must be listed in not_observed_fields")

    need_bool(record["rd_we"], "rd_we")
    need_range(record["rd"], "rd", 0, 31)
    if record["rd"] == 0 and record["rd_we"]:
        raise RecordError("rd=x0 must not write")
    if record["rd_we"]:
        need_range(record["rd_data"], "rd_data", 0, 0xffffffff)
        if "rd_data" in record["not_observed_fields"]:
            raise RecordError("rd_data is both written and not observed")
    elif record["rd_data"] is not None:
        raise RecordError("rd_we=false requires rd_data=null")

    for name in ("csr_valid", "csr_rd_valid", "csr_wr_valid", "mem_valid", "mem_we"):
        need_bool(record[name], name)
    if not record["csr_valid"]:
        if record["csr_rd_valid"] or record["csr_wr_valid"]:
            raise RecordError("csr_valid=false requires rd/wr valid=false")
        for name in ("csr_addr", "csr_wdata", "csr_rdata"):
            if record[name] is not None:
                raise RecordError(f"csr_valid=false requires {name}=null")
    else:
        need_range(record["csr_addr"], "csr_addr", 0, 4095)
        if record["csr_rd_valid"]:
            if record["csr_rdata"] is None:
                if record["source"] == "dut" or "csr_rdata" not in record["not_observed_fields"]:
                    raise RecordError("CSR read missing csr_rdata observation")
            else:
                need_range(record["csr_rdata"], "csr_rdata", 0, 0xffffffff)
        elif record["csr_rdata"] is not None:
            raise RecordError("csr_rd_valid=false requires csr_rdata=null")
        if record["csr_wr_valid"]:
            if record["csr_wdata"] is None:
                if record["source"] == "dut" or "csr_wdata" not in record["not_observed_fields"]:
                    raise RecordError("CSR write missing csr_wdata observation")
            else:
                need_range(record["csr_wdata"], "csr_wdata", 0, 0xffffffff)
        elif record["csr_wdata"] is not None:
            raise RecordError("csr_wr_valid=false requires csr_wdata=null")
    check_csr(record)

    need_str(record["mem_size"], "mem_size", SIZES)
    if not record["mem_valid"]:
        if record["mem_we"]:
            raise RecordError("mem_valid=false requires mem_we=false")
        if record["mem_size"] != "none":
            raise RecordError("mem_valid=false requires mem_size=none")
        for name in ("mem_va", "mem_pa", "mem_mask", "mem_wdata", "mem_rdata"):
            if record[name] is not None:
                raise RecordError(f"mem_valid=false requires {name}=null")
    else:
        if record["mem_size"] == "none":
            raise RecordError("mem_valid=true requires concrete mem_size")
        need_range(record["mem_va"], "mem_va", 0, 0xffffffff)
        need_range(record["mem_pa"], "mem_pa", 0, (1 << 34) - 1)
        need_range(record["mem_mask"], "mem_mask", 0, 15)
        mask = expected_mask(record["mem_size"], record["mem_va"])
        if record["mem_mask"] != mask:
            raise RecordError(
                f"mem_mask 0x{record['mem_mask']:x} != expected 0x{mask:x} "
                f"for {record['mem_size']} at 0x{record['mem_va']:x}")
        if record["mem_we"]:
            need_range(record["mem_wdata"], "mem_wdata", 0, 0xffffffff)
            width = SIZE_BYTES[record["mem_size"]]
            if record["mem_wdata"] >= (1 << (8 * width)):
                raise RecordError("store mem_wdata does not fit the access size")
            if record["mem_rdata"] is not None:
                raise RecordError("store must not report mem_rdata")
        else:
            if record["mem_wdata"] is not None:
                raise RecordError("load must not report mem_wdata")
            if record["mem_rdata"] is None:
                if "mem_rdata" not in record["not_observed_fields"]:
                    raise RecordError("missing load data must be listed as not observed")
            else:
                need_range(record["mem_rdata"], "mem_rdata", 0, 0xffffffff)
                if "mem_rdata" in record["not_observed_fields"]:
                    raise RecordError("mem_rdata is both observed and not observed")

    if record["source"] == "dut":
        if not record["token_valid"] or not record["next_pc_valid"]:
            raise RecordError("DUT record requires token and next_pc")
        if record["derived_fields"] or record["not_observed_fields"]:
            raise RecordError("DUT record must not mark required observations missing")
        if record["mem_valid"] and not record["mem_we"] and record["mem_rdata"] is None:
            raise RecordError("DUT load must provide mem_rdata")
    if record["source"] == "spike-derived":
        if record["token_valid"] or record["next_pc_valid"]:
            raise RecordError("Spike-derived record must not fabricate token/next_pc")
        if not record["derived_fields"]:
            raise RecordError("Spike-derived record must list derived fields")


def validate_trap(record: dict) -> None:
    check_keys(record, TRAP_REQUIRED, "trap")
    if record["schema"] != "hias-retire/2":
        raise RecordError("unsupported schema")
    if record["kind"] != "trap":
        raise RecordError("kind must be trap")
    need_str(record["source"], "source", {"dut", "synthetic"})
    need_range(record["seq"], "seq", 0, 1 << 62)
    for name in ("pc", "epc", "target_pc", "tval", "mstatus_before",
                 "mstatus_after", "cause_csr_before", "cause_csr_after",
                 "epc_csr_before", "epc_csr_after"):
        need_range(record[name], name, 0, 0xffffffff)
    need_range(record["cause"], "cause", 0, 31)
    need_bool(record["is_interrupt"], "is_interrupt")
    need_str(record["from_priv"], "from_priv", PRIVS)
    need_str(record["to_priv"], "to_priv", PRIVS)


def validate_bundle(record: dict) -> list[dict]:
    check_keys(record, BUNDLE_REQUIRED, "bundle")
    if record["schema"] != "hias-retire/2" or record["kind"] != "bundle":
        raise RecordError("bundle schema/kind mismatch")
    need_range(record["seq_base"], "seq_base", 0, 1 << 62)
    slots = record["slots"]
    if not isinstance(slots, list) or len(slots) > 2:
        raise RecordError("bundle slots must contain 0..2 records")
    for index, slot in enumerate(slots):
        validate_normal(slot)
        if slot["seq"] != record["seq_base"] + index:
            raise RecordError("bundle slot seq does not follow seq_base")
    trap = record["trap"]
    if trap is not None:
        validate_trap(trap)
        if slots:
            raise RecordError("normal retirement and Trap must be mutually exclusive")
        if trap["seq"] != record["seq_base"]:
            raise RecordError("trap seq does not match seq_base")
    return slots + ([trap] if trap is not None else [])


def validate_stream(records: list[dict]) -> None:
    last = -1
    for index, record in enumerate(records, 1):
        kind = record.get("kind")
        if kind == "bundle":
            events = validate_bundle(record)
            seqs = [e["seq"] for e in events]
            for seq in seqs:
                if seq <= last:
                    raise RecordError(
                        f"stream:{index}: seq {seq} is not strictly greater than {last}")
            if seqs:
                last = max(seqs)
            # An empty bundle is a no-op placeholder: it does not advance the
            # retirement sequence, and repeated empty bundles are permitted.
        elif kind in ("normal", "trap"):
            if kind == "normal":
                validate_normal(record)
            else:
                validate_trap(record)
            if record["seq"] <= last:
                raise RecordError(f"stream:{index}: seq not strictly increasing")
            last = record["seq"]
        else:
            raise RecordError(f"stream:{index}: unknown kind {kind!r}")


def read_jsonl(path: Path) -> list[dict]:
    records = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as exc:
            raise RecordError(f"{path.name}:{number}: invalid JSON: {exc}")
    return records


def validate_examples() -> int:
    files = sorted(EXAMPLES.glob("*.jsonl"))
    if not files:
        print("RETIRE_CONTRACT_FAIL: no examples", file=sys.stderr)
        return 2
    total = 0
    for path in files:
        records = read_jsonl(path)
        validate_stream(records)
        total += len(records)
        print(f"RETIRE_CONTRACT_FILE_OK: {path.name} records={len(records)}")
    print(f"RETIRE_CONTRACT_PASS: files={len(files)} records={total}")
    return 0


# ---------------------------------------------------------------------------
# Self-test: paired positive/negative rules
# ---------------------------------------------------------------------------

def base_normal(**over):
    rec = {
        "schema": "hias-retire/2", "kind": "normal", "source": "synthetic",
        "seq": 1, "token": {"idx": 1, "gen": 0}, "token_valid": True,
        "pc": 0x80000000, "instr": 0x00100093, "next_pc": 0x80000004,
        "next_pc_valid": True, "priv": "M",
        "rd_we": True, "rd": 1, "rd_data": 1,
        "csr_valid": False, "csr_rd_valid": False, "csr_wr_valid": False,
        "csr_addr": None, "csr_wdata": None, "csr_rdata": None,
        "mem_valid": False, "mem_we": False, "mem_va": None, "mem_pa": None,
        "mem_size": "none", "mem_mask": None, "mem_wdata": None, "mem_rdata": None,
        "derived_fields": [], "not_observed_fields": [],
    }
    rec.update(over)
    return rec


def base_mem(**over):
    rec = base_normal(rd_we=False, rd=0, rd_data=None, next_pc=0x80000008,
                      mem_valid=True, mem_we=True, mem_va=0x80000000,
                      mem_pa=0x80000000, mem_size="word", mem_mask=0xF,
                      mem_wdata=0x12345678, mem_rdata=None)
    rec.update(over)
    return rec


def self_test() -> int:
    failures = 0
    positives = 0
    negatives = 0

    def positive(name, record):
        nonlocal positives
        if isinstance(record, list):
            validate_stream(record)
        elif isinstance(record, dict) and record.get("kind") == "bundle":
            validate_bundle(record)
        else:
            validate_normal(record)
        positives += 1
        print(f"RETIRE_CONTRACT_POSITIVE_OK: {name}")

    def negative(name, record, reason):
        nonlocal failures, negatives
        try:
            if isinstance(record, list):
                validate_stream(record)
            elif record.get("kind") == "bundle":
                validate_bundle(record)
            elif record.get("kind") == "trap":
                validate_trap(record)
            else:
                validate_normal(record)
        except RecordError as exc:
            if reason not in str(exc):
                print(f"RETIRE_CONTRACT_NEGATIVE_FAIL: {name}: wrong reason: {exc}",
                      file=sys.stderr)
                failures += 1
            else:
                negatives += 1
                print(f"RETIRE_CONTRACT_NEGATIVE_OK: {name} ({exc})")
        else:
            print(f"RETIRE_CONTRACT_NEGATIVE_FAIL: {name} was accepted", file=sys.stderr)
            failures += 1

    # CSR truth table: read/write validity must match the instruction encoding.
    csrrw_x0 = 0x30001073  # csrrw x0, mstatus, x0
    csrrs_x0 = 0x30002073  # csrrs x0, mstatus, x0
    csrrs_x1 = 0x3000a0f3  # csrrs x1, mstatus, x1 (rs1=1)
    csrrwi_0 = 0x30005073  # csrrwi x0, mstatus, 0
    csrrsi_0 = 0x30006073  # csrrsi x0, mstatus, 0
    for name, instr, rd, rd_we, rd_valid, wr_valid in [
        ("csrrw rd=x0", csrrw_x0, 0, False, False, True),
        ("csrrs rs1=x0", csrrs_x0, 0, False, True, False),
        ("csrrs rs1=x1 value0", csrrs_x1, 1, True, True, True),
        ("csrrwi zimm=0", csrrwi_0, 0, False, False, True),
        ("csrrsi zimm=0", csrrsi_0, 0, False, True, False),
    ]:
        positive(name, base_normal(
            instr=instr, rd=rd, rd_we=rd_we,
            rd_data=(1 if rd_we else None),
            csr_valid=True, csr_rd_valid=rd_valid, csr_wr_valid=wr_valid,
            csr_addr=0x300, csr_wdata=(1 if wr_valid else None),
            csr_rdata=(0 if rd_valid else None),
        ))

    # Byte lanes and half positions.
    for offset in range(4):
        positive(f"byte lane {offset}", base_mem(
            mem_size="byte", mem_va=0x80000000 + offset,
            mem_pa=0x80000000 + offset, mem_mask=1 << offset,
            mem_wdata=0xa0 + offset))
    for offset in (0, 2):
        positive(f"half offset {offset}", base_mem(
            mem_size="half", mem_va=0x80000000 + offset,
            mem_pa=0x80000000 + offset, mem_mask=3 << offset,
            mem_wdata=0x1234))
    positive("word", base_mem())
    for name, instr in [("LBU", 0x00004083), ("LHU", 0x00005083)]:
        positive(name, base_mem(
            mem_we=False, instr=instr,
            mem_size="byte" if name == "LBU" else "half",
            mem_mask=1 if name == "LBU" else 3,
            mem_wdata=None, mem_rdata=0x5a))

    # Missing observation must be explicit.
    positive("Spike-derived missing next_pc/token", base_normal(
        source="spike-derived", token=None, token_valid=False,
        next_pc=None, next_pc_valid=False,
        derived_fields=["seq"], not_observed_fields=["token", "next_pc"]))
    positive("load x0 missing rdata", base_mem(
        source="spike-derived", token=None, token_valid=False,
        next_pc=None, next_pc_valid=False, mem_we=False, mem_wdata=None,
        mem_rdata=None, derived_fields=["mem_pa", "mem_size", "mem_mask"],
        not_observed_fields=["token", "next_pc", "mem_rdata"]))

    # Legal false/zero and empty-bundle placeholder.
    positive("legal token/next_pc false", base_normal(
        source="synthetic", token=None, token_valid=False,
        next_pc=None, next_pc_valid=False,
        not_observed_fields=["token", "next_pc"]))
    positive("empty bundle placeholder",
             [base_normal(seq=0),
              {"schema": "hias-retire/2", "kind": "bundle", "seq_base": 1,
               "slots": [], "trap": None},
              base_normal(seq=1)])

    # Paired negatives.
    negative("rd_we=false with rd_data",
             base_normal(rd_we=False, rd=0, rd_data=1),
             "rd_we=false requires rd_data=null")
    negative("x0 write", base_normal(rd=0, rd_we=True), "rd=x0")
    negative("CSR read suppression wrong",
             base_normal(instr=csrrw_x0, rd=0, rd_we=False, rd_data=None,
                         csr_valid=True, csr_rd_valid=True, csr_wr_valid=True,
                         csr_addr=0x300, csr_wdata=1, csr_rdata=0),
             "csr_rd_valid")
    negative("CSR write suppression wrong",
             base_normal(instr=csrrs_x0, rd=0, rd_we=False, rd_data=None,
                         csr_valid=True, csr_rd_valid=True, csr_wr_valid=True,
                         csr_addr=0x300, csr_wdata=1, csr_rdata=0),
             "csr_wr_valid")
    negative("wrong byte mask", base_mem(
        mem_size="byte", mem_va=0x80000003, mem_mask=1), "mem_mask")
    negative("unaligned half", base_mem(
        mem_size="half", mem_va=0x80000001, mem_mask=3), "unaligned half")
    negative("word mask wrong", base_mem(mem_mask=3), "mem_mask")
    negative("missing load data unmarked", base_mem(
        mem_we=False, mem_wdata=None, mem_rdata=None, not_observed_fields=[]),
        "must be listed as not observed")
    negative("token missing gen", base_normal(token={"idx": 1}), "token")
    negative("token idx out of range",
             base_normal(token={"idx": 32, "gen": 0}), "token.idx")
    negative("unknown privilege", base_normal(priv="H"), "priv")
    negative("DUT missing next_pc", base_normal(
        source="dut", token_valid=True, next_pc=None, next_pc_valid=False,
        not_observed_fields=["next_pc"]), "DUT record")
    negative("Spike-derived fabricates token", base_normal(
        source="spike-derived", token_valid=True, next_pc=None,
        next_pc_valid=False, derived_fields=["seq"],
        not_observed_fields=["next_pc"]), "Spike-derived")
    negative("seq duplicate", [base_normal(seq=1), base_normal(seq=1)],
             "seq not strictly increasing")
    negative("seq backwards", [base_normal(seq=2), base_normal(seq=1)],
             "seq not strictly increasing")
    negative("trap missing field", {
        "schema": "hias-retire/2", "kind": "trap", "source": "synthetic",
        "seq": 3, "pc": 0x80000010, "epc": 0x80000010,
        "target_pc": 0x80000100, "cause": 11, "is_interrupt": False,
        "tval": 0, "from_priv": "M", "to_priv": "M",
        "mstatus_before": 0, "mstatus_after": 0x1800,
        "cause_csr_before": 0, "cause_csr_after": 11,
        "epc_csr_before": 0,
    }, "missing fields")
    negative("trap from spike-derived", {
        "schema": "hias-retire/2", "kind": "trap", "source": "spike-derived",
        "seq": 3, "pc": 0x80000010, "epc": 0x80000010,
        "target_pc": 0x80000100, "cause": 11, "is_interrupt": False,
        "tval": 0, "from_priv": "M", "to_priv": "M",
        "mstatus_before": 0, "mstatus_after": 0x1800,
        "cause_csr_before": 0, "cause_csr_after": 11,
        "epc_csr_before": 0, "epc_csr_after": 0x80000010,
    }, "source")
    # CSR classification must not be hidden by csr_valid=false.
    hidden = base_normal(instr=0x30002073, rd=0, rd_we=False, rd_data=None,
                         csr_valid=False, csr_rd_valid=False,
                         csr_wr_valid=False, csr_addr=None,
                         csr_wdata=None, csr_rdata=None)
    negative("CSR instruction hidden with csr_valid=false", hidden,
             "CSR instruction missing csr_valid")
    # Strict boolean types.
    negative("token_valid not boolean",
             base_normal(token_valid=1), "token_valid")
    negative("next_pc_valid not boolean",
             base_normal(next_pc_valid="yes"), "next_pc_valid")
    # List type/name/consistency.
    negative("not_observed not a list",
             base_normal(not_observed_fields="token"), "list of strings")
    negative("not_observed unknown field",
             base_normal(not_observed_fields=["bogus"]), "unknown field")
    negative("not_observed field has a value",
             base_normal(not_observed_fields=["rd_data"]),
             "listed as not observed")
    negative("derived field has no value",
             base_normal(derived_fields=["mem_pa"]), "listed as derived")
    # Bundle sequence strictness.
    dup_bundle = {"schema": "hias-retire/2", "kind": "bundle", "seq_base": 5,
                  "slots": [base_normal(seq=5)], "trap": None}
    negative("duplicate non-empty bundle",
             [dup_bundle, json.loads(json.dumps(dup_bundle))],
             "not strictly greater")
    adjacent = {"schema": "hias-retire/2", "kind": "bundle", "seq_base": 5,
                "slots": [base_normal(seq=5)], "trap": None}
    negative("adjacent bundle repeats first seq",
             [base_normal(seq=5), adjacent], "not strictly greater")
    negative("bundle trap plus retire", {
        "schema": "hias-retire/2", "kind": "bundle", "seq_base": 5,
        "slots": [base_normal(seq=5)],
        "trap": {"schema": "hias-retire/2", "kind": "trap", "source": "synthetic",
                 "seq": 5, "pc": 0x80000010, "epc": 0x80000010,
                 "target_pc": 0x80000100, "cause": 11, "is_interrupt": False,
                 "tval": 0, "from_priv": "M", "to_priv": "M",
                 "mstatus_before": 0, "mstatus_after": 0x1800,
                 "cause_csr_before": 0, "cause_csr_after": 11,
                 "epc_csr_before": 0, "epc_csr_after": 0x80000010},
    }, "mutually exclusive")

    if failures:
        print(f"RETIRE_CONTRACT_SELFTEST_FAIL failures={failures} "
              f"positives={positives} negatives={negatives}", file=sys.stderr)
        return 1
    print(f"RETIRE_CONTRACT_SELFTEST_PASS positives={positives} negatives={negatives}")
    return 0


# ---------------------------------------------------------------------------
# Spike converter
# ---------------------------------------------------------------------------

SPIKE_RE = re.compile(
    r"^core\s+\d+:\s+(?P<priv>\d)\s+(?P<pc>0x[0-9a-f]+)\s+"
    r"\((?P<instr>0x[0-9a-f]+)\)"
    r"(?:\s+x(?P<rd>\d+)\s+(?P<rdval>0x[0-9a-f]+))?"
    r"(?:\s+mem\s+(?P<memaddr>0x[0-9a-f]+)"
    r"(?:\s+(?P<memval>0x[0-9a-f]+))?)?\s*$"
)
PRIV_MAP = {"3": "M", "1": "S", "0": "U"}
LOAD_FUNCT3 = {0: ("byte", False), 1: ("half", False), 2: ("word", False),
               4: ("byte", True), 5: ("half", True)}
STORE_FUNCT3 = {0: "byte", 1: "half", 2: "word"}


def convert_spike(path: Path) -> int:
    records = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = SPIKE_RE.match(line)
        if not match:
            print(f"RETIRE_CONTRACT_SPIKE_PARSE_FAIL: line {number}: {line!r}",
                  file=sys.stderr)
            return 1
        if match["priv"] not in PRIV_MAP:
            print(f"RETIRE_CONTRACT_SPIKE_PARSE_FAIL: line {number}: unknown priv "
                  f"{match['priv']}", file=sys.stderr)
            return 1
        pc = int(match["pc"], 16)
        instr = int(match["instr"], 16)
        opcode = instr & 0x7f
        funct3 = (instr >> 12) & 0x7
        rd = int(match["rd"]) if match["rd"] is not None else None
        rd_val = int(match["rdval"], 16) if match["rdval"] else None
        mem_addr = int(match["memaddr"], 16) if match["memaddr"] else None
        mem_val = int(match["memval"], 16) if match["memval"] else None

        mem_valid = False
        mem_we = False
        mem_size = "none"
        mask = None
        wdata = None
        rdata = None
        derived = ["seq"]
        not_observed = ["token", "next_pc"]
        if opcode == 0x03 and mem_addr is not None:
            mem_valid = True
            mem_size, unsigned = LOAD_FUNCT3[funct3]
            mask = expected_mask(mem_size, mem_addr)
            derived += ["mem_va", "mem_pa", "mem_size", "mem_mask"]
            if rd is not None and rd != 0 and rd_val is not None:
                rdata = rd_val
                derived.append("mem_rdata")
            else:
                not_observed.append("mem_rdata")
        elif opcode == 0x23 and mem_addr is not None:
            mem_valid = True
            mem_we = True
            mem_size = STORE_FUNCT3[funct3]
            mask = expected_mask(mem_size, mem_addr)
            wdata = mem_val
            derived += ["mem_va", "mem_pa", "mem_size", "mem_mask", "mem_wdata"]
        elif mem_addr is not None:
            print(f"RETIRE_CONTRACT_SPIKE_PARSE_FAIL: line {number}: mem on "
                  f"unsupported opcode 0x{opcode:02x}", file=sys.stderr)
            return 1

        csr = csr_expected(instr)
        if csr is None:
            csr_valid = csr_rd = csr_wr = False
            csr_addr = csr_wdata = csr_rdata = None
        else:
            csr_valid = True
            csr_rd = csr["read"]
            csr_wr = csr["write"]
            csr_addr = csr["addr"]
            csr_wdata = None
            csr_rdata = None
            derived += ["csr_valid", "csr_addr", "csr_rd_valid", "csr_wr_valid"]
            if csr_wr:
                not_observed.append("csr_wdata")
            if csr_rd:
                not_observed.append("csr_rdata")

        rd_we = rd is not None and rd != 0
        if rd_we and rd_val is None:
            print(f"RETIRE_CONTRACT_SPIKE_PARSE_FAIL: line {number}: missing rd value",
                  file=sys.stderr)
            return 1
        records.append({
            "schema": "hias-retire/2", "kind": "normal",
            "source": "spike-derived", "seq": len(records),
            "token": None, "token_valid": False,
            "pc": pc, "instr": instr, "next_pc": None, "next_pc_valid": False,
            "priv": PRIV_MAP[match["priv"]],
            "rd_we": rd_we, "rd": rd if rd is not None else 0,
            "rd_data": rd_val if rd_we else None,
            "csr_valid": csr_valid, "csr_rd_valid": csr_rd,
            "csr_wr_valid": csr_wr, "csr_addr": csr_addr,
            "csr_wdata": csr_wdata, "csr_rdata": csr_rdata,
            "mem_valid": mem_valid, "mem_we": mem_we,
            "mem_va": mem_addr, "mem_pa": mem_addr,
            "mem_size": mem_size, "mem_mask": mask,
            "mem_wdata": wdata, "mem_rdata": rdata,
            "derived_fields": sorted(set(derived)),
            "not_observed_fields": sorted(set(not_observed)),
        })

    validate_stream(records)
    out = EXAMPLES / "spike_derived_examples.jsonl"
    with out.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, sort_keys=True) + "\n")
    print(f"RETIRE_CONTRACT_SPIKE_CONVERTED: lines={len(records)} "
          f"out={out.relative_to(ROOT)}")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--validate-examples", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--convert-spike")
    args = parser.parse_args(argv)
    try:
        if args.self_test:
            return self_test()
        if args.convert_spike:
            return convert_spike(Path(args.convert_spike))
        if args.validate_examples:
            return validate_examples()
    except RecordError as exc:
        print(f"RETIRE_CONTRACT_FAIL: {exc}", file=sys.stderr)
        return 1
    parser.error("choose --validate-examples, --self-test, or --convert-spike")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
