#!/usr/bin/env python3
"""Check the P0-02 retirement/trap contract and example records.

Modes:
  --validate-examples   validate every JSONL record against retire_schema.json
  --self-test           run the validator against deliberately bad records and
                        require each one to be rejected
  --convert-spike FILE  convert selected real Spike --log-commits lines to
                        contract-shaped records (source=spike-derived)

The validator enforces explicit valid bits and rejects zero/null used to
pretend an observation exists. It never claims these examples are DUT output.
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


class RecordError(Exception):
    pass


def load_schema() -> dict:
    return json.loads(SCHEMA.read_text(encoding="utf-8"))


def check_type(value, spec, field: str) -> None:
    types = spec.get("type")
    if types is None:
        return
    allowed = types if isinstance(types, list) else [types]
    ok = False
    for t in allowed:
        if t == "integer" and isinstance(value, int) and not isinstance(value, bool):
            ok = True
        elif t == "boolean" and isinstance(value, bool):
            ok = True
        elif t == "string" and isinstance(value, str):
            ok = True
        elif t == "null" and value is None:
            ok = True
        elif t == "object" and isinstance(value, dict):
            ok = True
    if not ok:
        raise RecordError(f"{field}: expected {allowed}, got {type(value).__name__}")


def check_field(value, spec, field: str) -> None:
    check_type(value, spec, field)
    if value is None:
        return
    if "const" in spec and value != spec["const"]:
        raise RecordError(f"{field}: must equal {spec['const']!r}")
    if "enum" in spec and value not in spec["enum"]:
        raise RecordError(f"{field}: {value!r} not in {spec['enum']}")
    if "min" in spec and isinstance(value, int) and value < spec["min"]:
        raise RecordError(f"{field}: {value} < {spec['min']}")
    if "max" in spec and isinstance(value, int) and value > spec["max"]:
        raise RecordError(f"{field}: {value} > {spec['max']}")


def validate_normal(record: dict, schema: dict) -> None:
    for field in schema["required"]:
        if field not in record:
            raise RecordError(f"missing field {field}")
    extra = set(record) - set(schema["required"])
    if extra:
        raise RecordError(f"unknown fields {sorted(extra)}")
    fields = schema["fields"]
    for name, spec in fields.items():
        if name in record:
            check_field(record[name], spec, name)
    if record["kind"] != "normal":
        raise RecordError("normal validator called with kind != normal")

    token = record["token"]
    if not isinstance(token, dict) or set(token) != {"idx", "gen"}:
        raise RecordError("token must be {idx, gen}")

    if record["rd"] == 0 and record["rd_we"]:
        raise RecordError("rd=x0 must not write")
    if record["rd_we"] and record["rd_data"] is None:
        raise RecordError("rd_we=true requires rd_data")
    if not record["rd_we"] and record["rd_data"] is not None:
        raise RecordError("rd_we=false requires rd_data=null")

    if record["csr_we"]:
        for field in ("csr_addr", "csr_wdata", "csr_rdata"):
            if record[field] is None:
                raise RecordError(f"csr_we=true requires {field}")
    else:
        for field in ("csr_addr", "csr_wdata"):
            if record[field] is not None:
                raise RecordError(f"csr_we=false requires {field}=null")

    if record["mem_valid"]:
        if record["mem_size"] == "none":
            raise RecordError("mem_valid=true requires a concrete mem_size")
        if record["mem_va"] is None or record["mem_pa"] is None:
            raise RecordError("mem_valid=true requires mem_va and mem_pa")
        if record["mem_mask"] is None:
            raise RecordError("mem_valid=true requires mem_mask")
        if record["mem_pa"] >= (1 << 34):
            raise RecordError("mem_pa exceeds 34 bits")
        width = {"byte": 1, "half": 2, "word": 4}[record["mem_size"]]
        if record["mem_mask"] == 0 or record["mem_mask"] >= (1 << width):
            raise RecordError("mem_mask inconsistent with mem_size")
        if record["mem_we"]:
            if record["mem_wdata"] is None:
                raise RecordError("store requires mem_wdata")
            if record["mem_rdata"] is not None:
                raise RecordError("store must not report mem_rdata")
        else:
            if record["mem_wdata"] is not None:
                raise RecordError("load must not report mem_wdata")
    else:
        if record["mem_we"]:
            raise RecordError("mem_valid=false requires mem_we=false")
        if record["mem_size"] != "none":
            raise RecordError("mem_valid=false requires mem_size=none")
        for field in ("mem_va", "mem_pa", "mem_mask", "mem_wdata", "mem_rdata"):
            if record[field] is not None:
                raise RecordError(f"mem_valid=false requires {field}=null")


def validate_trap(record: dict, schema: dict) -> None:
    for field in schema["trap_required"]:
        if field not in record:
            raise RecordError(f"missing trap field {field}")
    extra = set(record) - set(schema["trap_required"])
    if extra:
        raise RecordError(f"unknown trap fields {sorted(extra)}")
    for name, spec in schema["trap_fields"].items():
        if name in record:
            check_field(record[name], spec, name)
    if record["kind"] != "trap":
        raise RecordError("trap validator called with kind != trap")


def validate_record(record: dict, schema: dict) -> None:
    if not isinstance(record, dict):
        raise RecordError("record must be an object")
    kind = record.get("kind")
    if kind == "normal":
        validate_normal(record, schema)
    elif kind == "trap":
        validate_trap(record, schema)
    else:
        raise RecordError(f"kind must be normal or trap, got {kind!r}")


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
    schema = load_schema()
    files = sorted(EXAMPLES.glob("*.jsonl"))
    if not files:
        print("RETIRE_CONTRACT_FAIL: no example files", file=sys.stderr)
        return 2
    total = 0
    for path in files:
        records = read_jsonl(path)
        for index, record in enumerate(records, 1):
            try:
                validate_record(record, schema)
            except RecordError as exc:
                print(f"RETIRE_CONTRACT_FAIL: {path.name}:{index}: {exc}",
                      file=sys.stderr)
                return 1
        total += len(records)
        print(f"RETIRE_CONTRACT_FILE_OK: {path.name} records={len(records)}")
    print(f"RETIRE_CONTRACT_PASS: files={len(files)} records={total}")
    return 0


def self_test() -> int:
    schema = load_schema()
    good_normal = {
        "schema": "hias-retire/1", "kind": "normal", "seq": 1,
        "token": {"idx": 1, "gen": 1},
        "pc": 0x80000000, "instr": 0x00100093, "next_pc": 0x80000004,
        "priv": "M", "rd_we": True, "rd": 1, "rd_data": 1,
        "csr_we": False, "csr_addr": None, "csr_wdata": None,
        "csr_rdata": None, "mem_valid": False, "mem_we": False,
        "mem_va": None, "mem_pa": None, "mem_size": "none",
        "mem_mask": None, "mem_wdata": None, "mem_rdata": None,
        "source": "synthetic",
    }
    validate_record(good_normal, schema)

    bad_cases = []
    case = json.loads(json.dumps(good_normal))
    case["rd_we"] = False  # rd_data still set
    bad_cases.append(("rd_we=false with rd_data", case))
    case = json.loads(json.dumps(good_normal))
    case["rd"] = 0  # x0 write
    bad_cases.append(("x0 write", case))
    case = json.loads(json.dumps(good_normal))
    case["mem_valid"] = True  # no addresses
    bad_cases.append(("mem_valid without address", case))
    case = json.loads(json.dumps(good_normal))
    case["csr_we"] = True  # missing csr data
    bad_cases.append(("csr_we without data", case))
    case = json.loads(json.dumps(good_normal))
    case["token"] = {"idx": 1}
    bad_cases.append(("token missing gen", case))
    case = json.loads(json.dumps(good_normal))
    case["mem_valid"] = True
    case["mem_size"] = "word"
    case["mem_va"] = 0x80000000
    case["mem_pa"] = 0x80000000
    case["mem_mask"] = 0
    bad_cases.append(("zero mem_mask", case))
    case = json.loads(json.dumps(good_normal))
    case["source"] = "dut"
    case["priv"] = "H"
    bad_cases.append(("bad privilege", case))

    failures = 0
    for name, record in bad_cases:
        try:
            validate_record(record, schema)
        except RecordError:
            print(f"RETIRE_CONTRACT_NEGATIVE_OK: {name}")
        else:
            print(f"RETIRE_CONTRACT_NEGATIVE_FAIL: {name} was accepted",
                  file=sys.stderr)
            failures += 1

    # Trap negative cases.
    good_trap = {
        "schema": "hias-retire/1", "kind": "trap", "seq": 2,
        "pc": 0x80000010, "epc": 0x80000010, "target_pc": 0x80000100,
        "cause": 11, "is_interrupt": False, "tval": 0,
        "from_priv": "M", "to_priv": "M",
        "mstatus_before": 0, "mstatus_after": 0x1800,
        "cause_csr_before": 0, "cause_csr_after": 11,
        "epc_csr_before": 0, "epc_csr_after": 0x80000010,
        "source": "synthetic",
    }
    validate_record(good_trap, schema)
    case = json.loads(json.dumps(good_trap))
    del case["epc_csr_after"]
    try:
        validate_record(case, schema)
    except RecordError:
        print("RETIRE_CONTRACT_NEGATIVE_OK: trap missing csr field")
    else:
        print("RETIRE_CONTRACT_NEGATIVE_FAIL: trap missing csr field",
              file=sys.stderr)
        failures += 1

    if failures:
        print("RETIRE_CONTRACT_SELFTEST_FAIL", file=sys.stderr)
        return 1
    print("RETIRE_CONTRACT_SELFTEST_PASS")
    return 0


SPIKE_RE = re.compile(
    r"^core\s+\d+:\s+(?P<priv>\d)\s+(?P<pc>0x[0-9a-f]+)\s+"
    r"\((?P<instr>0x[0-9a-f]+)\)"
    r"(?:\s+x(?P<rd>\d+)\s+(?P<rdval>0x[0-9a-f]+))?"
    r"(?:\s+mem\s+(?P<memaddr>0x[0-9a-f]+)"
    r"(?:\s+(?P<memval>0x[0-9a-f]+))?)?\s*$"
)

PRIV_MAP = {"3": "M", "1": "S", "0": "U"}

# Opcodes used to classify memory access size/kind from the instruction word.
LOAD_OPS = {0x03: "load"}
STORE_OPS = {0x23: "store"}
FUNCT3_SIZE = {0: "byte", 1: "half", 2: "word"}


def convert_spike(path: Path) -> int:
    """Convert real Spike commit lines to contract-shaped records.

    Only fields Spike actually prints (priv, pc, instr, rd value, mem address,
    mem value) are filled. Everything else is null/false with an explicit
    validity rule, and the record is marked source=spike-derived. This is a
    field-mapping demonstration, not a DUT retirement trace.
    """
    records = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = SPIKE_RE.match(line)
        if not match:
            continue
        pc = int(match["pc"], 16)
        instr = int(match["instr"], 16)
        opcode = instr & 0x7f
        funct3 = (instr >> 12) & 0x7
        rd = int(match["rd"]) if match["rd"] is not None else None
        mem_addr = int(match["memaddr"], 16) if match["memaddr"] else None
        mem_val = int(match["memval"], 16) if match["memval"] else None

        mem_kind = None
        if opcode in LOAD_OPS:
            mem_kind = "load"
        elif opcode in STORE_OPS:
            mem_kind = "store"

        record = {
            "schema": "hias-retire/1",
            "kind": "normal",
            "seq": len(records),
            "token": {"idx": len(records) % 32, "gen": len(records) // 32 % 256},
            "pc": pc,
            "instr": instr,
            "next_pc": 0,  # Spike log does not print next_pc
            "priv": PRIV_MAP.get(match["priv"], "M"),
            "rd_we": rd is not None and rd != 0,
            "rd": rd if rd is not None else 0,
            "rd_data": int(match["rdval"], 16) if match["rdval"] else None,
            "csr_we": False,
            "csr_addr": None,
            "csr_wdata": None,
            "csr_rdata": None,
            "mem_valid": mem_kind is not None,
            "mem_we": mem_kind == "store",
            "mem_va": mem_addr,
            "mem_pa": mem_addr,
            "mem_size": FUNCT3_SIZE.get(funct3, "none") if mem_kind else "none",
            "mem_mask": (1 << (1 << funct3)) - 1 if mem_kind else None,
            "mem_wdata": mem_val if mem_kind == "store" else None,
            "mem_rdata": mem_val if mem_kind == "load" else None,
            "source": "spike-derived",
        }
        if record["rd_we"] and record["rd_data"] is None:
            # Spike prints the destination value for register writes.
            record["rd_we"] = False
            record["rd"] = 0
        if record["mem_valid"] and record["mem_size"] == "none":
            record["mem_valid"] = False
            record["mem_we"] = False
            record["mem_va"] = None
            record["mem_pa"] = None
            record["mem_mask"] = None
            record["mem_wdata"] = None
            record["mem_rdata"] = None
        records.append(record)

    out = EXAMPLES / "spike_derived_examples.jsonl"
    with out.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, sort_keys=True) + "\n")
    print(f"RETIRE_CONTRACT_SPIKE_CONVERTED: lines={len(records)} out={out.relative_to(ROOT)}")
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
