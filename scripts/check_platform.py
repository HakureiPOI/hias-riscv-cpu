#!/usr/bin/env python3
"""P0-02 platform consistency checks beyond schema validation.

Checks that the generated files, the linker script, the compiled ELF and the
Spike argument file all agree with config/platform.json. Also provides
negative configuration probes by mutating a copy of the config.
"""

from __future__ import annotations

import argparse
import copy
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "config" / "platform.json"
GEN = ROOT / "software" / "generated"
GEN_LD = GEN / "platform.ld"
GEN_H = GEN / "platform.h"
SPIKE_ARGS = ROOT / "config" / "platform.spike.args"
CROSS = "riscv64-unknown-elf-"
BUILD = ROOT / "build" / "p0-02-platform"
ELF = BUILD / "platform_check.elf"


class CheckError(Exception):
    pass


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def load_config() -> dict:
    return json.loads(CONFIG.read_text(encoding="utf-8"))


def read_macros(path: Path) -> dict[str, str]:
    macros = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line.startswith("#define "):
            continue
        parts = line.split(None, 2)
        if len(parts) != 3:
            continue
        _, name, value = parts
        macros[name] = value.rstrip("u")
    return macros


def check_generated() -> None:
    result = run([sys.executable, str(ROOT / "scripts" / "gen_platform.py"), "--check"])
    if result.returncode != 0:
        raise CheckError(f"generated files differ from config:\n{result.stderr}")
    print("PLATFORM_CHECK_GENERATED_OK")


def check_linker_script() -> None:
    cfg = load_config()
    text = GEN_LD.read_text(encoding="utf-8")
    expected = {
        "PLATFORM_RAM_BASE": cfg["memory"]["base"],
        "PLATFORM_RAM_SIZE": cfg["memory"]["size"],
        "PLATFORM_RESET_VECTOR": cfg["software"]["reset_vector"],
        "PLATFORM_STACK_RESERVE": cfg["software"]["stack_reserve"],
        "PLATFORM_SIGNATURE_RESERVE": cfg["software"]["signature_reserve"],
        "PLATFORM_PAGE_TABLE_RESERVE": cfg["software"]["page_table_reserve"],
    }
    for name, raw in expected.items():
        value = int(raw, 0)
        needle = f"{name} = 0x{value:08x};"
        if needle not in text:
            raise CheckError(f"linker constant missing/mismatched: {needle}")
    print("PLATFORM_CHECK_LINKER_OK")


def check_header() -> None:
    cfg = load_config()
    macros = read_macros(GEN_H)
    expected = {
        "PLATFORM_RAM_BASE": int(cfg["memory"]["base"], 0),
        "PLATFORM_RAM_SIZE": int(cfg["memory"]["size"], 0),
        "PLATFORM_RESET_VECTOR": int(cfg["software"]["reset_vector"], 0),
        "PLATFORM_PAGE_TABLE_BASE": 0x8001a000,
        "PLATFORM_PAGE_TABLE_END": 0x8001e000,
        "PLATFORM_PAGE_TABLE_RESERVE": int(cfg["software"]["page_table_reserve"], 0),
        "PLATFORM_LAYOUT_GAP_START": 0x8001e000,
        "PLATFORM_LAYOUT_GAP_END": 0x8001eff0,
    }
    for name, value in expected.items():
        if name not in macros:
            raise CheckError(f"header macro missing: {name}")
        if int(macros[name], 0) != value:
            raise CheckError(f"header macro {name} mismatch")
    print("PLATFORM_CHECK_HEADER_OK")


def check_rtl_package() -> None:
    """The RTL package carries a few platform constants; keep them in sync."""
    cfg = load_config()
    text = (ROOT / "rtl" / "include" / "core_config_pkg.sv").read_text(encoding="utf-8")
    expected = {
        "PA_BITS": int(cfg["isa"]["pa_bits"]),
        "VA_BITS": int(cfg["isa"]["va_bits"]),
        "XLEN": int(cfg["isa"]["xlen"]),
    }
    for name, value in expected.items():
        needle = f"localparam int unsigned {name} = {value};"
        if needle not in text:
            raise CheckError(f"RTL package {name} does not match config ({value})")
    import re
    base = int(cfg["memory"]["base"], 0)
    size = int(cfg["memory"]["size"], 0)
    def package_const(name: str) -> int:
        match = re.search(
            rf"{name}\s*=\s*PA_BITS'\(32'h([0-9a-fA-F_]+)\)", text)
        if not match:
            raise CheckError(f"RTL package missing {name}")
        return int(match.group(1).replace("_", ""), 16)
    if package_const("RAM_BASE") != base:
        raise CheckError("RTL package RAM_BASE does not match config")
    if package_const("RAM_SIZE") != size:
        raise CheckError("RTL package RAM_SIZE does not match config")
    print("PLATFORM_CHECK_RTL_PACKAGE_OK")


def check_spike_args() -> None:
    cfg = load_config()
    text = SPIKE_ARGS.read_text(encoding="utf-8").strip()
    expected = (f"--isa={cfg['reference']['spike']['isa']} "
                f"--priv={cfg['reference']['spike']['priv']} "
                f"--disable-dtb "
                f"-m{cfg['reference']['spike']['memory_arg']}")
    if text != expected:
        raise CheckError(f"Spike args mismatch:\n got: {text}\nwant: {expected}")
    print("PLATFORM_CHECK_SPIKE_ARGS_OK")


def check_elf_layout() -> None:
    cfg = load_config()
    BUILD.mkdir(parents=True, exist_ok=True)
    base = int(cfg["memory"]["base"], 0)
    size = int(cfg["memory"]["size"], 0)
    end = base + size
    cmd = [
        f"{CROSS}gcc", "-march=rv32i", "-mabi=ilp32", "-mcmodel=medany",
        "-mno-relax", "-nostdlib", "-nostartfiles", "-ffreestanding",
        "-fno-builtin", "-O2", "-T", str(ROOT / "software" / "smoke" / "link.ld"),
        "-Wl,--build-id=none", "-o", str(ELF),
        str(ROOT / "software" / "smoke" / "start.S"),
        str(ROOT / "software" / "smoke" / "main.c"),
        str(ROOT / "software" / "smoke" / "platform_check.c"),
    ]
    result = run(cmd)
    if result.returncode != 0:
        raise CheckError(f"platform ELF link failed:\n{result.stderr}")
    nm = run([f"{CROSS}nm", str(ELF)])
    if nm.returncode != 0:
        raise CheckError(f"nm failed: {nm.stderr}")
    symbols = {}
    for line in nm.stdout.splitlines():
        parts = line.split()
        if len(parts) == 3:
            symbols[parts[2]] = int(parts[0], 16)
    required = [
        "_start", "__bss_end", "__signature_start", "__signature_end",
        "__page_table_start", "__page_table_end", "__layout_gap_start",
        "__layout_gap_end", "__stack_limit", "_stack_top", "tohost", "fromhost",
    ]
    for name in required:
        if name not in symbols:
            raise CheckError(f"ELF missing symbol {name}")
    if symbols["_start"] != base:
        raise CheckError(f"_start 0x{symbols['_start']:x} != RAM base 0x{base:x}")
    if not (symbols["__bss_end"] <= symbols["__signature_start"]
            <= symbols["__signature_end"] <= symbols["__page_table_start"]
            <= symbols["__page_table_end"] <= symbols["__stack_limit"]
            <= symbols["_stack_top"] < end):
        raise CheckError("reserved region ordering is invalid")
    if symbols["__page_table_start"] != 0x8001a000:
        raise CheckError(f"page table base 0x{symbols['__page_table_start']:x} != 0x8001a000")
    if symbols["__page_table_end"] != 0x8001e000:
        raise CheckError(f"page table end 0x{symbols['__page_table_end']:x} != 0x8001e000")
    if symbols["__page_table_end"] - symbols["__page_table_start"] != 0x4000:
        raise CheckError("page table size is not 0x4000")
    if symbols["__signature_end"] != symbols["__page_table_start"]:
        raise CheckError("signature end does not meet page table base")
    if symbols["__layout_gap_start"] != symbols["__page_table_end"]:
        raise CheckError("layout gap start does not meet page table end")
    if symbols["__layout_gap_end"] != symbols["__stack_limit"]:
        raise CheckError("layout gap end does not meet stack limit")
    if symbols["_stack_top"] >= end:
        raise CheckError("stack top outside RAM")

    # Verify the executable LOAD segment sits entirely inside RAM.
    readelf = run([f"{CROSS}readelf", "-l", str(ELF)])
    if readelf.returncode != 0:
        raise CheckError(f"readelf failed: {readelf.stderr}")
    for line in readelf.stdout.splitlines():
        fields = line.split()
        if len(fields) >= 6 and fields[0] == "LOAD":
            vaddr = int(fields[2], 16)
            memsz = int(fields[5], 16)
            if vaddr < base or vaddr + memsz > end:
                raise CheckError(
                    f"LOAD segment [0x{vaddr:x},0x{vaddr+memsz:x}) outside RAM")
    print(f"PLATFORM_CHECK_ELF_OK entry=0x{symbols['_start']:08x} "
          f"bss_end=0x{symbols['__bss_end']:08x} "
          f"signature=[0x{symbols['__signature_start']:08x},"
          f"0x{symbols['__signature_end']:08x}) "
          f"page_tables=[0x{symbols['__page_table_start']:08x},"
          f"0x{symbols['__page_table_end']:08x}) "
          f"gap=[0x{symbols['__layout_gap_start']:08x},"
          f"0x{symbols['__layout_gap_end']:08x}) "
          f"stack_limit=0x{symbols['__stack_limit']:08x} "
          f"stack_top=0x{symbols['_stack_top']:08x}")


def spike_run() -> None:
    args = SPIKE_ARGS.read_text(encoding="utf-8").split()
    result = run(["spike", *args, str(ELF)], timeout=60)
    if result.returncode != 0:
        raise CheckError(f"Spike platform run failed (exit={result.returncode}):\n"
                         f"{result.stdout}\n{result.stderr}")
    print("PLATFORM_CHECK_SPIKE_RUN_OK")


def check_spike_features() -> None:
    """Probe the installed Spike's support for the final ISA/Svade string.

    Acceptance of the ISA string is not proof of full functionality; it records
    the actual command/options and the DTS view for the P0-02 baseline.
    """
    cfg = load_config()
    final_isa = cfg["isa"]["final_isa"] + "_svade"
    mem = cfg["reference"]["spike"]["memory_arg"]
    # --dump-dts generates the DTB, so it must not be combined with
    # --disable-dtb (Spike then fails reading the blob).
    cmd = ["spike", f"--isa={final_isa}", "--priv=msu",
           f"-m{mem}", "--dump-dts", str(ELF)]
    result = run(cmd, timeout=60)
    if result.returncode != 0:
        raise CheckError(f"Spike rejected final ISA/priv/Svade ({final_isa}):\n"
                         f"{result.stdout}\n{result.stderr}")
    dts = result.stdout
    if "riscv,sv32" not in dts:
        raise CheckError("Spike DTS does not expose riscv,sv32")
    if f"memory@{cfg['memory']['base'][2:]}" not in dts:
        raise CheckError("Spike DTS does not show the configured RAM base")
    if f"0x{int(cfg['memory']['size'], 0):x}" not in dts:
        raise CheckError("Spike DTS does not show the configured RAM size")
    cmd_run = ["spike", f"--isa={final_isa}", "--priv=msu", "--disable-dtb",
               f"-m{mem}", str(ELF)]
    run_result = run(cmd_run, timeout=60)
    if run_result.returncode != 0:
        raise CheckError(f"Spike final-config smoke run failed: {run_result.stderr}")
    print(f"PLATFORM_CHECK_SPIKE_FEATURES_OK: isa={final_isa} priv=msu "
          f"memory={mem} mmu=sv32 (ISA string accepted; not full verification)")


def negative_probe(name: str, mutate, reason: str) -> None:
    """Validate a mutated config and require the semantic config error.

    Uses --validate-only so generated-file drift cannot masquerade as a
    semantic rejection. Exit 2 is the config error code.
    """
    import tempfile

    cfg = load_config()
    mutate(cfg)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        json.dump(cfg, handle)
        path = handle.name
    try:
        result = run([sys.executable, str(ROOT / "scripts" / "gen_platform.py"),
                      "--config", path, "--validate-only"])
    finally:
        Path(path).unlink(missing_ok=True)
    if result.returncode != 2:
        raise CheckError(
            f"negative config '{name}' did not return semantic error 2 "
            f"(got {result.returncode}): {result.stderr or result.stdout}")
    if reason not in (result.stderr or result.stdout):
        raise CheckError(f"negative config '{name}' missing reason '{reason}': "
                         f"{result.stderr or result.stdout}")
    print(f"PLATFORM_CHECK_NEGATIVE_OK: {name} (exit=2, reason='{reason}')")


def drift_probe() -> None:
    """Prove generated-file drift is a distinct failure (exit 3)."""
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        gen = out / "software" / "generated"
        cfg_out = out / "config"
        gen.mkdir(parents=True)
        cfg_out.mkdir(parents=True)
        for src, dst in (
            (GEN_H, gen / "platform.h"),
            (GEN_LD, gen / "platform.ld"),
            (SPIKE_ARGS, cfg_out / "platform.spike.args"),
            (ROOT / "config" / "platform.generated.json",
             cfg_out / "platform.generated.json"),
        ):
            dst.write_bytes(src.read_bytes())
        # Mutate only the copied header; the config itself stays valid.
        with (gen / "platform.h").open("a", encoding="utf-8") as handle:
            handle.write("\n/* drift */\n")
        result = run([sys.executable, str(ROOT / "scripts" / "gen_platform.py"),
                      "--check", "--out-dir", tmp])
        if result.returncode != 3:
            raise CheckError(
                f"generated drift was not rejected with exit 3 "
                f"(got {result.returncode}): {result.stderr or result.stdout}")
        print("PLATFORM_CHECK_DRIFT_OK: generated drift rejected with exit=3")


def run_negative_probes() -> None:
    def overlap_mmio(cfg):
        cfg["mmio"].append({
            "name": "overlap_ram", "base": "0x80000000", "size": "0x1000",
            "p1": "reserved", "final": "reserved", "access": "rw",
            "cacheable": False, "note": "negative overlap probe",
        })

    def wrong_size(cfg):
        cfg["memory"]["size"] = "0x40000"

    def misaligned_mmio(cfg):
        cfg["mmio"][0]["base"] = "0x02000100"

    def spike_mismatch(cfg):
        cfg["reference"]["spike"]["memory_arg"] = "0x80000000:0x40000"

    def bad_pa(cfg):
        cfg["isa"]["pa_bits"] = 32

    def stack_overflow(cfg):
        cfg["software"]["stack_reserve"] = "0x40000"

    def mmio_duplicate(cfg):
        cfg["mmio"].append(dict(cfg["mmio"][2]))

    def non_page_granular(cfg):
        cfg["software"]["page_table_reserve"] = "0x2800"

    negative_probe("mmio_overlaps_ram", overlap_mmio, "range overlaps ram")
    negative_probe("wrong_ram_size", wrong_size, "memory.size must be 0x20000")
    negative_probe("misaligned_mmio", misaligned_mmio, "4 KiB aligned")
    negative_probe("spike_memory_mismatch", spike_mismatch, "memory_arg must be")
    negative_probe("wrong_pa_bits", bad_pa, "pa_bits must be 34")
    negative_probe("stack_exceeds_ram", stack_overflow, "reserved regions")
    negative_probe("duplicate_mmio_name", mmio_duplicate, "duplicate")
    negative_probe("page_table_not_page_granular", non_page_granular,
                   "page_table_reserve must be")
    drift_probe()


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--negative", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.negative:
            run_negative_probes()
            print("PLATFORM_CHECK_NEGATIVE_ALL_PASS")
            return 0
        check_generated()
        check_linker_script()
        check_header()
        check_rtl_package()
        check_spike_args()
        check_elf_layout()
        spike_run()
        check_spike_features()
        print("PLATFORM_CHECK_PASS")
        return 0
    except CheckError as exc:
        print(f"PLATFORM_CHECK_FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
