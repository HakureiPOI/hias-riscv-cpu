#!/usr/bin/env python3
"""Validate config/platform.json and generate derived platform files.

Single source of truth: config/platform.json.
Generated outputs:
  software/generated/platform.h       C constants for freestanding software
  software/generated/platform.ld      linker MEMORY/ASSERT definitions
  config/platform.spike.args          Spike host arguments
  config/platform.generated.json      normalized values used by checkers

Usage:
  python3 scripts/gen_platform.py            validate + write generated files
  python3 scripts/gen_platform.py --check    validate only, do not write
  python3 scripts/gen_platform.py --config <path> --out-dir <dir>
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = ROOT / "config" / "platform.json"
DEFAULT_OUT = ROOT

REQUIRED_TOP = {"schema", "version", "description", "isa", "memory", "software", "mmio", "reference"}
REQUIRED_ISA = {
    "xlen", "va_bits", "pa_bits", "p1_isa", "final_isa",
    "p1_priv", "final_priv", "p1_mmu", "final_mmu",
}
REQUIRED_MEM = {"name", "base", "size", "alignment", "cacheable", "access"}
REQUIRED_SW = {
    "reset_vector", "stack_reserve", "signature_reserve",
    "page_table_reserve", "tohost_symbol", "fromhost_symbol",
}
REQUIRED_MMIO = {"name", "base", "size", "p1", "final", "access", "cacheable"}
OPTIONAL_MMIO = {"note", "registers"}
REQUIRED_REF = {"model", "spike"}
REQUIRED_SPIKE = {
    "isa", "priv", "memory_arg", "disable_dtb",
    "boot_rom_base", "boot_rom_size", "htif",
}

P1_VALUES = {"implemented", "reserved"}
ACCESS_VALUES = {"read", "write", "execute"}
MMIO_ACCESS_VALUES = {"r", "w", "rw"}


class ConfigError(Exception):
    pass


def fail(msg: str) -> None:
    raise ConfigError(msg)


def as_int(value, field: str) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value, 0)
        except ValueError:
            fail(f"{field}: not an integer: {value!r}")
    fail(f"{field}: expected integer or numeric string, got {type(value).__name__}")


def require_keys(obj, keys, where: str) -> None:
    missing = sorted(keys - set(obj))
    if missing:
        fail(f"{where}: missing keys {missing}")
    extra = sorted(set(obj) - keys)
    if extra:
        fail(f"{where}: unknown keys {extra}")


def is_pow2(value: int) -> bool:
    return value > 0 and (value & (value - 1)) == 0


def require_keys_optional(obj, required, optional, where: str) -> None:
    missing = sorted(set(required) - set(obj))
    if missing:
        fail(f"{where}: missing keys {missing}")
    extra = sorted(set(obj) - set(required) - set(optional))
    if extra:
        fail(f"{where}: unknown keys {extra}")


def check_range(name: str, base: int, size: int, alignment: int) -> tuple[int, int]:
    if base < 0 or size <= 0:
        fail(f"{name}: base/size must be positive (base={base}, size={size})")
    if base % alignment != 0:
        fail(f"{name}: base 0x{base:x} not aligned to {alignment}")
    if size % alignment != 0:
        fail(f"{name}: size 0x{size:x} not a multiple of alignment {alignment}")
    end = base + size
    if end <= base:
        fail(f"{name}: range overflows")
    return base, end


def validate(cfg: dict) -> dict:
    if not isinstance(cfg, dict):
        fail("top level must be an object")
    require_keys(cfg, REQUIRED_TOP, "top")
    if cfg["schema"] != "hias-platform/1":
        fail(f"unsupported schema: {cfg['schema']!r}")
    if not isinstance(cfg["version"], str) or not cfg["version"]:
        fail("version must be a non-empty string")

    isa = cfg["isa"]
    if not isinstance(isa, dict):
        fail("isa must be an object")
    require_keys(isa, REQUIRED_ISA, "isa")
    for field in ("xlen", "va_bits", "pa_bits"):
        if not isinstance(isa[field], int):
            fail(f"isa.{field} must be an integer")
    if isa["xlen"] != 32:
        fail("isa.xlen must be 32 for this project")
    if isa["va_bits"] != 32:
        fail("isa.va_bits must be 32 (RV32)")
    if isa["pa_bits"] != 34:
        fail("isa.pa_bits must be 34 for Sv32")
    if isa["p1_mmu"] != "bare":
        fail("isa.p1_mmu must be bare for P1")
    if isa["final_mmu"] != "sv32_svade":
        fail("isa.final_mmu must be sv32_svade")

    mem = cfg["memory"]
    if not isinstance(mem, dict):
        fail("memory must be an object")
    require_keys(mem, REQUIRED_MEM, "memory")
    if mem["name"] != "ram":
        fail("memory.name must be 'ram'")
    base = as_int(mem["base"], "memory.base")
    size = as_int(mem["size"], "memory.size")
    align = as_int(mem["alignment"], "memory.alignment")
    if not is_pow2(align):
        fail("memory.alignment must be a power of two")
    if base != 0x80000000:
        fail("memory.base must be 0x80000000 for P1")
    if size != 0x20000:
        fail("memory.size must be 0x20000 (128 KiB) for P1")
    if align > size:
        fail("memory.alignment larger than memory")
    base, mem_end = check_range("memory.ram", base, size, align)
    if set(mem["access"]) != ACCESS_VALUES:
        fail(f"memory.access must be exactly {sorted(ACCESS_VALUES)}")
    if mem["cacheable"] is not True:
        fail("memory.cacheable must be true")

    sw = cfg["software"]
    if not isinstance(sw, dict):
        fail("software must be an object")
    require_keys(sw, REQUIRED_SW, "software")
    reset = as_int(sw["reset_vector"], "software.reset_vector")
    if reset != base:
        fail("software.reset_vector must equal memory.base")
    stack = as_int(sw["stack_reserve"], "software.stack_reserve")
    signature = as_int(sw["signature_reserve"], "software.signature_reserve")
    page_tables = as_int(sw["page_table_reserve"], "software.page_table_reserve")
    for name, value in (("stack_reserve", stack),
                        ("signature_reserve", signature)):
        if value <= 0 or value % 16 != 0:
            fail(f"software.{name} must be a positive multiple of 16")
    if page_tables < 4096 or page_tables % 4096 != 0:
        fail("software.page_table_reserve must be a positive multiple of 4096 (page granularity)")
    reserved = stack + signature + page_tables
    if reserved >= size:
        fail("software reserved regions consume the whole RAM")
    if (base + reserved) > mem_end:
        fail("software reserved regions exceed RAM")
    for key in ("tohost_symbol", "fromhost_symbol"):
        if not isinstance(sw[key], str) or not sw[key].isidentifier():
            fail(f"software.{key} must be a C identifier")

    mmio = cfg["mmio"]
    if not isinstance(mmio, list) or not mmio:
        fail("mmio must be a non-empty list")
    seen_names = set()
    ranges = [("ram", base, mem_end)]
    for index, entry in enumerate(mmio):
        where = f"mmio[{index}]"
        if not isinstance(entry, dict):
            fail(f"{where} must be an object")
        require_keys_optional(entry, REQUIRED_MMIO, OPTIONAL_MMIO, where)
        name = entry["name"]
        if not isinstance(name, str) or not name.isidentifier():
            fail(f"{where}.name must be an identifier")
        if name in seen_names:
            fail(f"{where}.name duplicate: {name}")
        seen_names.add(name)
        mbase = as_int(entry["base"], f"{where}.base")
        msize = as_int(entry["size"], f"{where}.size")
        if mbase < 0 or msize <= 0:
            fail(f"{where}: invalid range")
        if mbase % 4096 != 0 or msize % 4096 != 0:
            fail(f"{where}: MMIO base/size must be 4 KiB aligned")
        if mbase + msize > (1 << isa["pa_bits"]):
            fail(f"{where}: exceeds {isa['pa_bits']}-bit physical address space")
        if entry["p1"] not in P1_VALUES:
            fail(f"{where}.p1 must be one of {sorted(P1_VALUES)}")
        if entry["access"] not in MMIO_ACCESS_VALUES:
            fail(f"{where}.access must be one of {sorted(MMIO_ACCESS_VALUES)}")
        if entry["cacheable"] is not False:
            fail(f"{where}.cacheable must be false (MMIO)")
        for rname, rbase, rend in ranges:
            if mbase < rend and rbase < mbase + msize:
                fail(f"{where}: range overlaps {rname}")
        ranges.append((name, mbase, mbase + msize))
        regs = entry.get("registers", [])
        if not isinstance(regs, list):
            fail(f"{where}.registers must be a list")
        seen_regs = set()
        reg_ranges = []
        for ridx, reg in enumerate(regs):
            rwhere = f"{where}.registers[{ridx}]"
            if not isinstance(reg, dict):
                fail(f"{rwhere} must be an object")
            rkeys = {"name", "offset", "width", "access", "reset", "note"}
            require_keys(reg, rkeys, rwhere)
            if reg["name"] in seen_regs:
                fail(f"{rwhere}.name duplicate: {reg['name']}")
            seen_regs.add(reg["name"])
            off = as_int(reg["offset"], f"{rwhere}.offset")
            width = reg["width"]
            if not isinstance(width, int) or width not in (8, 16, 32):
                fail(f"{rwhere}.width must be 8, 16 or 32")
            if off < 0 or off % (width // 8) != 0:
                fail(f"{rwhere}.offset must be naturally aligned")
            rend = off + width // 8
            if rend > msize:
                fail(f"{rwhere} exceeds MMIO region")
            if reg["access"] not in {"r", "w", "rw"}:
                fail(f"{rwhere}.access must be r/w/rw")
            for other, ob, oe in reg_ranges:
                if off < oe and ob < rend:
                    fail(f"{rwhere} overlaps register {other}")
            reg_ranges.append((reg["name"], off, rend))

    ref = cfg["reference"]
    if not isinstance(ref, dict):
        fail("reference must be an object")
    require_keys(ref, REQUIRED_REF, "reference")
    if ref["model"] != "spike":
        fail("reference.model must be spike")
    spike = ref["spike"]
    if not isinstance(spike, dict):
        fail("reference.spike must be an object")
    require_keys(spike, REQUIRED_SPIKE, "reference.spike")
    expected_mem_arg = f"0x{base:x}:0x{size:x}"
    if spike["memory_arg"] != expected_mem_arg:
        fail(f"reference.spike.memory_arg must be {expected_mem_arg}")
    if spike["disable_dtb"] is not True:
        fail("reference.spike.disable_dtb must be true")
    if spike["isa"] != isa["p1_isa"]:
        fail("reference.spike.isa must equal isa.p1_isa for P1")
    if spike["priv"] != isa["p1_priv"]:
        fail("reference.spike.priv must equal isa.p1_priv for P1")
    boot_base = as_int(spike["boot_rom_base"], "reference.spike.boot_rom_base")
    boot_size = as_int(spike["boot_rom_size"], "reference.spike.boot_rom_size")
    check_range("reference.spike.boot_rom", boot_base, boot_size, 4096)
    if boot_base < mem_end and base < boot_base + boot_size:
        fail("reference.spike.boot_rom overlaps RAM")

    stack_top = mem_end - 16
    stack_limit = stack_top - stack
    page_table_end = stack_limit - (stack_limit % 4096)
    page_table_base = page_table_end - page_tables
    if page_table_base < 0:
        fail("page table reserve underflows")
    signature_end = page_table_base
    signature_base = signature_end - signature
    layout_gap_start = page_table_end
    layout_gap_end = stack_limit
    if signature_base < base:
        fail("software reserved regions exceed RAM below the program area")

    return {
        "base": base,
        "size": size,
        "end": mem_end,
        "reset": reset,
        "stack": stack,
        "signature": signature,
        "page_tables": page_tables,
        "stack_top": stack_top,
        "stack_limit": stack_limit,
        "page_table_base": page_table_base,
        "page_table_end": page_table_end,
        "signature_base": signature_base,
        "signature_end": signature_end,
        "layout_gap_start": layout_gap_start,
        "layout_gap_end": layout_gap_end,
        "mmio": [(e["name"], as_int(e["base"], e["name"]),
                  as_int(e["size"], e["name"]), e["p1"], e["access"])
                 for e in mmio],
        "spike_args": (
            f"--isa={spike['isa']} --priv={spike['priv']} "
            f"--disable-dtb -m{spike['memory_arg']}"
        ),
        "version": cfg["version"],
        "pa_bits": isa["pa_bits"],
        "va_bits": isa["va_bits"],
        "xlen": isa["xlen"],
    }


def write_header(path: Path, norm: dict, cfg: dict) -> None:
    lines = [
        "/* AUTO-GENERATED from config/platform.json by scripts/gen_platform.py.",
        " * Do not edit. Regenerate with: python3 scripts/gen_platform.py",
        " */",
        "#ifndef HIAS_PLATFORM_H",
        "#define HIAS_PLATFORM_H",
        "",
        f'#define PLATFORM_VERSION "{norm["version"]}"',
        f"#define PLATFORM_XLEN {norm['xlen']}",
        f"#define PLATFORM_VA_BITS {norm['va_bits']}",
        f"#define PLATFORM_PA_BITS {norm['pa_bits']}",
        f"#define PLATFORM_RAM_BASE 0x{norm['base']:08x}u",
        f"#define PLATFORM_RAM_SIZE 0x{norm['size']:08x}u",
        f"#define PLATFORM_RAM_END 0x{norm['end']:08x}u",
        f"#define PLATFORM_RESET_VECTOR 0x{norm['reset']:08x}u",
        f"#define PLATFORM_STACK_RESERVE 0x{norm['stack']:08x}u",
        f"#define PLATFORM_SIGNATURE_RESERVE 0x{norm['signature']:08x}u",
        f"#define PLATFORM_PAGE_TABLE_RESERVE 0x{norm['page_tables']:08x}u",
        f"#define PLATFORM_STACK_TOP 0x{norm['stack_top']:08x}u",
        f"#define PLATFORM_STACK_LIMIT 0x{norm['stack_limit']:08x}u",
        f"#define PLATFORM_SIGNATURE_BASE 0x{norm['signature_base']:08x}u",
        f"#define PLATFORM_PAGE_TABLE_BASE 0x{norm['page_table_base']:08x}u",
        f"#define PLATFORM_PAGE_TABLE_END 0x{norm['page_table_end']:08x}u",
        f"#define PLATFORM_LAYOUT_GAP_START 0x{norm['layout_gap_start']:08x}u",
        f"#define PLATFORM_LAYOUT_GAP_END 0x{norm['layout_gap_end']:08x}u",
        f"#define PLATFORM_PROGRAM_LIMIT 0x{norm['signature_base']:08x}u",
    ]
    for name, mbase, msize, p1, access in norm["mmio"]:
        upper = name.upper()
        lines.append(f"#define PLATFORM_MMIO_{upper}_BASE 0x{mbase:08x}u")
        lines.append(f"#define PLATFORM_MMIO_{upper}_SIZE 0x{msize:08x}u")
        lines.append(f"#define PLATFORM_MMIO_{upper}_P1_{p1.upper()} 1")
        for reg in _mmio_registers(cfg, name):
            rupper = reg["name"].upper()
            off = int(reg["offset"], 0)
            lines.append(f"#define PLATFORM_MMIO_{upper}_{rupper}_OFFSET 0x{off:08x}u")
            lines.append(f"#define PLATFORM_MMIO_{upper}_{rupper}_WIDTH {reg['width']}")
    lines.append("")
    lines.append("#endif /* HIAS_PLATFORM_H */")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


_REG_CACHE = {}
def _mmio_registers(cfg: dict, name: str):
    for entry in cfg.get("mmio", []):
        if entry.get("name") == name:
            return entry.get("registers", [])
    return []

def write_linker(path: Path, norm: dict) -> None:
    mmio_asserts = []
    for name, mbase, msize, _p1, _access in norm["mmio"]:
        mmio_asserts.append(
            f"ASSERT(({mbase} >= {norm['end']}) || ({mbase} + {msize} <= {norm['base']}), "
            f"\"platform config: MMIO {name} overlaps RAM\")"
        )
    text = "\n".join([
        "/* AUTO-GENERATED from config/platform.json by scripts/gen_platform.py.",
        " * Do not edit. Regenerate with: python3 scripts/gen_platform.py",
        " */",
        f"PLATFORM_RAM_BASE = 0x{norm['base']:08x};",
        f"PLATFORM_RAM_SIZE = 0x{norm['size']:08x};",
        f"PLATFORM_RESET_VECTOR = 0x{norm['reset']:08x};",
        f"PLATFORM_STACK_RESERVE = 0x{norm['stack']:08x};",
        f"PLATFORM_SIGNATURE_RESERVE = 0x{norm['signature']:08x};",
        f"PLATFORM_PAGE_TABLE_RESERVE = 0x{norm['page_tables']:08x};",
        f"PLATFORM_STACK_TOP = 0x{norm['stack_top']:08x};",
        f"PLATFORM_STACK_LIMIT = 0x{norm['stack_limit']:08x};",
        f"PLATFORM_SIGNATURE_BASE = 0x{norm['signature_base']:08x};",
        f"PLATFORM_PAGE_TABLE_BASE = 0x{norm['page_table_base']:08x};",
        f"PLATFORM_PAGE_TABLE_END = 0x{norm['page_table_end']:08x};",
        f"PLATFORM_LAYOUT_GAP_START = 0x{norm['layout_gap_start']:08x};",
        f"PLATFORM_LAYOUT_GAP_END = 0x{norm['layout_gap_end']:08x};",
        f"PLATFORM_PROGRAM_LIMIT = 0x{norm['signature_base']:08x};",
        "ASSERT(PLATFORM_RAM_BASE == PLATFORM_RESET_VECTOR, \"platform config: reset vector must equal RAM base\")",
        "ASSERT((PLATFORM_RAM_BASE % 4096) == 0, \"platform config: RAM base not 4 KiB aligned\")",
        "ASSERT((PLATFORM_RAM_SIZE % 4096) == 0, \"platform config: RAM size not 4 KiB aligned\")",
        *mmio_asserts,
        "",
    ])
    path.write_text(text, encoding="utf-8")


def write_spike_args(path: Path, norm: dict) -> None:
    path.write_text(norm["spike_args"] + "\n", encoding="utf-8")


def write_normalized(path: Path, norm: dict) -> None:
    data = {
        "version": norm["version"],
        "ram": {"base": f"0x{norm['base']:08x}",
                "size": f"0x{norm['size']:08x}",
                "end": f"0x{norm['end']:08x}"},
        "reset_vector": f"0x{norm['reset']:08x}",
        "layout": {
            "program_limit": f"0x{norm['signature_base']:08x}",
            "signature": [f"0x{norm['signature_base']:08x}", f"0x{norm['signature_end']:08x}"],
            "page_tables": [f"0x{norm['page_table_base']:08x}", f"0x{norm['page_table_end']:08x}"],
            "layout_gap": [f"0x{norm['layout_gap_start']:08x}", f"0x{norm['layout_gap_end']:08x}"],
            "stack": [f"0x{norm['stack_limit']:08x}", f"0x{norm['stack_top']:08x}"],
        },
        "mmio": [
            {"name": name, "base": f"0x{mbase:08x}", "size": f"0x{msize:08x}",
             "p1": p1, "access": access}
            for name, mbase, msize, p1, access in norm["mmio"]
        ],
        "spike_args": norm["spike_args"],
    }
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT))
    parser.add_argument("--check", action="store_true",
                        help="validate and compare checked-in generated files; do not write")
    parser.add_argument("--validate-only", action="store_true",
                        help="validate config semantics only; never inspect generated files")
    args = parser.parse_args(argv)

    config_path = Path(args.config)
    out = Path(args.out_dir)
    try:
        cfg = json.loads(config_path.read_text(encoding="utf-8"))
        norm = validate(cfg)
    except FileNotFoundError:
        print(f"PLATFORM_CONFIG_FAIL: missing {config_path}", file=sys.stderr)
        return 2
    except json.JSONDecodeError as exc:
        print(f"PLATFORM_CONFIG_FAIL: invalid JSON: {exc}", file=sys.stderr)
        return 2
    except ConfigError as exc:
        print(f"PLATFORM_CONFIG_FAIL: {exc}", file=sys.stderr)
        return 2

    print(f"PLATFORM_CONFIG_OK: version={norm['version']} "
          f"ram=[0x{norm['base']:08x},0x{norm['end']:08x}) "
          f"spike='{norm['spike_args']}'")

    if args.validate_only:
        print("PLATFORM_VALIDATE_ONLY_OK")
        return 0

    if args.check:
        # Regenerate into a temporary directory and compare with the checked-in
        # files, so hand edits and stale generated copies are rejected.
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            gen = tmp_root / "software" / "generated"
            cfg_out = tmp_root / "config"
            gen.mkdir(parents=True)
            cfg_out.mkdir(parents=True)
            write_header(gen / "platform.h", norm, cfg)
            write_linker(gen / "platform.ld", norm)
            write_spike_args(cfg_out / "platform.spike.args", norm)
            write_normalized(cfg_out / "platform.generated.json", norm)
            pairs = [
                (gen / "platform.h", out / "software" / "generated" / "platform.h"),
                (gen / "platform.ld", out / "software" / "generated" / "platform.ld"),
                (cfg_out / "platform.spike.args", out / "config" / "platform.spike.args"),
                (cfg_out / "platform.generated.json", out / "config" / "platform.generated.json"),
            ]
            drift = [str(dst) for src, dst in pairs
                     if not dst.exists() or dst.read_bytes() != src.read_bytes()]
        if drift:
            print("PLATFORM_GENERATED_DRIFT: " + ", ".join(drift), file=sys.stderr)
            return 3
        print("PLATFORM_GENERATED_OK: checked-in generated files match config")
        return 0

    generated = out / "software" / "generated"
    config_out = out / "config"
    generated.mkdir(parents=True, exist_ok=True)
    config_out.mkdir(parents=True, exist_ok=True)
    write_header(generated / "platform.h", norm, cfg)
    write_linker(generated / "platform.ld", norm)
    write_spike_args(config_out / "platform.spike.args", norm)
    write_normalized(config_out / "platform.generated.json", norm)
    print("PLATFORM_GENERATED_OK: software/generated/platform.h, "
          "software/generated/platform.ld, config/platform.spike.args, "
          "config/platform.generated.json")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
