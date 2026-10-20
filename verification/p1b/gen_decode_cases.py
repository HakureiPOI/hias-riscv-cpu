#!/usr/bin/env python3
"""Generate an independent P1-B decode expectation table.

The encoders/decoder below are written from the RV32I/Zicsr/Zifencei table and
are not imported from the RTL. They generate a C++ header used by both the
decode unit test and the fetch integration image.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "verification" / "p1b" / "decode_expected.h"

# Enumeration values from the frozen core_types_pkg.
OP = {"LUI": 0, "AUIPC": 1, "JAL": 2, "JALR": 3, "BRANCH": 4, "LOAD": 5,
      "STORE": 6, "ALU_I": 7, "ALU_R": 8, "MULDIV": 9, "CSR": 10,
      "FENCE": 11, "FENCEI": 12, "ECALL": 13, "EBREAK": 14, "MRET": 15,
      "SRET": 16, "WFI": 17}
EX = {"ADD": 0, "SUB": 1, "SLL": 2, "SLT": 3, "SLTU": 4, "XOR": 5, "SRL": 6,
      "SRA": 7, "OR": 8, "AND": 9, "ADDI": 10, "SLTI": 11, "SLTIU": 12,
      "XORI": 13, "ORI": 14, "ANDI": 15, "SLLI": 16, "SRLI": 17,
      "SRAI": 18, "LUI": 19, "AUIPC": 20, "JAL": 21, "JALR": 22,
      "BEQ": 23, "BNE": 24, "BLT": 25, "BGE": 26, "BLTU": 27, "BGEU": 28,
      "LB": 29, "LH": 30, "LW": 31, "LBU": 32, "LHU": 33, "SB": 34,
      "SH": 35, "SW": 36, "MUL": 37, "CSR": 45, "FENCE": 46,
      "FENCEI": 47, "ECALL": 48, "EBREAK": 49, "MRET": 50, "WFI": 52}
MEM = {"BYTE": 0, "HALF": 1, "WORD": 2}
CSR = {"RW": 0, "RS": 1, "RC": 2}
CAUSE = {"ILLEGAL": 2}


def sext(value, bits):
    value &= (1 << bits) - 1
    sign = 1 << (bits - 1)
    if value & sign:
        value -= (1 << bits)
    return value


def r(opcode, rd, f3, rs1, rs2, f7):
    return ((f7 & 0x7f) << 25) | ((rs2 & 31) << 20) | ((rs1 & 31) << 15) | \
           ((f3 & 7) << 12) | ((rd & 31) << 7) | (opcode & 0x7f)


def i(opcode, rd, f3, rs1, imm):
    return ((imm & 0xfff) << 20) | ((rs1 & 31) << 15) | ((f3 & 7) << 12) | \
           ((rd & 31) << 7) | (opcode & 0x7f)


def s(opcode, f3, rs1, rs2, imm):
    return (((imm >> 5) & 0x7f) << 25) | ((rs2 & 31) << 20) | \
           ((rs1 & 31) << 15) | ((f3 & 7) << 12) | ((imm & 31) << 7) | \
           (opcode & 0x7f)


def b(opcode, f3, rs1, rs2, imm):
    imm &= 0x1fff
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3f) << 25) | \
           ((rs2 & 31) << 20) | ((rs1 & 31) << 15) | ((f3 & 7) << 12) | \
           (((imm >> 1) & 0xf) << 8) | (((imm >> 11) & 1) << 7) | \
           (opcode & 0x7f)


def u(opcode, rd, imm20):
    return ((imm20 & 0xfffff) << 12) | ((rd & 31) << 7) | (opcode & 0x7f)


def j(opcode, rd, imm):
    imm &= 0x1fffff
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3ff) << 21) | \
           (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xff) << 12) | \
           ((rd & 31) << 7) | (opcode & 0x7f)


def decode(instr):
    """Independent reference decode, written from the locked ISA tables."""
    opcode = instr & 0x7f
    rd = (instr >> 7) & 31
    f3 = (instr >> 12) & 7
    rs1 = (instr >> 15) & 31
    rs2 = (instr >> 20) & 31
    f7 = (instr >> 25) & 0x7f
    out = {
        "valid": 1, "instr": instr, "op": OP["ALU_I"], "exec": EX["ADDI"],
        "rd": rd, "rs1": rs1, "rs2": rs2, "uses1": 0, "uses2": 0,
        "rd_we": 0, "imm": 0, "mem_size": MEM["WORD"], "csr_op": CSR["RW"],
        "csr_addr": 0, "csr_uimm": 0, "csr_uimm_valid": 0,
        "is_branch": 0, "is_jump": 0, "is_load": 0, "is_store": 0,
        "is_csr": 0, "is_fence": 0, "is_fence_i": 0, "is_mret": 0,
        "is_sret": 0, "is_wfi": 0, "illegal": 0, "illegal_cause": 0,
        "illegal_tval": 0,
    }

    def imm_i():
        return sext(instr >> 20, 12)

    def imm_s():
        return sext(((instr >> 25) << 5) | ((instr >> 7) & 0x1f), 12)

    def imm_b():
        return sext((((instr >> 31) & 1) << 12) |
                    (((instr >> 7) & 1) << 11) |
                    (((instr >> 25) & 0x3f) << 5) |
                    (((instr >> 8) & 0xf) << 1), 13)

    def imm_u():
        return sext(instr & 0xfffff000, 32)

    def imm_j():
        return sext((((instr >> 31) & 1) << 20) |
                    (((instr >> 12) & 0xff) << 12) |
                    (((instr >> 20) & 1) << 11) |
                    (((instr >> 21) & 0x3ff) << 1), 21)

    def illegal():
        out["illegal"] = 1
        out["illegal_cause"] = CAUSE["ILLEGAL"]
        out["illegal_tval"] = instr
        out["rd_we"] = 0
        for flag in ("is_branch", "is_jump", "is_load", "is_store", "is_csr",
                     "is_fence", "is_fence_i", "is_mret", "is_sret", "is_wfi"):
            out[flag] = 0
        return out

    if opcode == 0x37:  # LUI
        out.update(op=OP["LUI"], exec=EX["LUI"], imm=imm_u(), rd_we=int(rd != 0))
    elif opcode == 0x17:  # AUIPC
        out.update(op=OP["AUIPC"], exec=EX["AUIPC"], imm=imm_u(),
                   rd_we=int(rd != 0))
    elif opcode == 0x6f:  # JAL
        if f3 != 0:
            return illegal()
        out.update(op=OP["JAL"], exec=EX["JAL"], imm=imm_j(),
                   rd_we=int(rd != 0), is_jump=1)
    elif opcode == 0x67:  # JALR
        if f3 != 0:
            return illegal()
        out.update(op=OP["JALR"], exec=EX["JALR"], imm=imm_i(), uses1=1,
                   rd_we=int(rd != 0), is_jump=1)
    elif opcode == 0x63:  # BRANCH
        mapping = {0: "BEQ", 1: "BNE", 4: "BLT", 5: "BGE", 6: "BLTU", 7: "BGEU"}
        if f3 not in mapping:
            return illegal()
        out.update(op=OP["BRANCH"], exec=EX[mapping[f3]], imm=imm_b(),
                   uses1=1, uses2=1, is_branch=1)
    elif opcode == 0x03:  # LOAD
        mapping = {0: ("LB", "BYTE"), 1: ("LH", "HALF"), 2: ("LW", "WORD"),
                   4: ("LBU", "BYTE"), 5: ("LHU", "HALF")}
        if f3 not in mapping:
            return illegal()
        name, size = mapping[f3]
        out.update(op=OP["LOAD"], exec=EX[name], imm=imm_i(), uses1=1,
                   is_load=1, rd_we=int(rd != 0), mem_size=MEM[size])
    elif opcode == 0x23:  # STORE
        mapping = {0: ("SB", "BYTE"), 1: ("SH", "HALF"), 2: ("SW", "WORD")}
        if f3 not in mapping:
            return illegal()
        name, size = mapping[f3]
        out.update(op=OP["STORE"], exec=EX[name], imm=imm_s(), uses1=1,
                   uses2=1, is_store=1, mem_size=MEM[size])
    elif opcode == 0x13:  # OP-IMM
        out.update(op=OP["ALU_I"], uses1=1, rd_we=int(rd != 0))
        if f3 == 0:
            out.update(exec=EX["ADDI"], imm=imm_i())
        elif f3 == 2:
            out.update(exec=EX["SLTI"], imm=imm_i())
        elif f3 == 3:
            out.update(exec=EX["SLTIU"], imm=imm_i())
        elif f3 == 4:
            out.update(exec=EX["XORI"], imm=imm_i())
        elif f3 == 6:
            out.update(exec=EX["ORI"], imm=imm_i())
        elif f3 == 7:
            out.update(exec=EX["ANDI"], imm=imm_i())
        elif f3 == 1:
            if f7 != 0:
                return illegal()
            out.update(exec=EX["SLLI"], imm=rs2)
        elif f3 == 5:
            if f7 == 0:
                out.update(exec=EX["SRLI"], imm=rs2)
            elif f7 == 0x20:
                out.update(exec=EX["SRAI"], imm=rs2)
            else:
                return illegal()
        else:
            return illegal()
    elif opcode == 0x33:  # OP
        out.update(op=OP["ALU_R"], uses1=1, uses2=1, rd_we=int(rd != 0))
        if f7 == 0:
            names = ["ADD", "SLL", "SLT", "SLTU", "XOR", "SRL", "OR", "AND"]
            out["exec"] = EX[names[f3]]
        elif f7 == 0x20 and f3 in (0, 5):
            out["exec"] = EX["SUB" if f3 == 0 else "SRA"]
        else:
            out["op"] = OP["MULDIV"]
            out["exec"] = EX["MUL"]
            return illegal()
    elif opcode == 0x0f:  # FENCE / FENCE.I
        if f3 == 0:
            out.update(op=OP["FENCE"], exec=EX["FENCE"], is_fence=1)
        elif f3 == 1:
            out.update(op=OP["FENCEI"], exec=EX["FENCEI"], is_fence_i=1)
        else:
            return illegal()
    elif opcode == 0x73:  # SYSTEM
        out["rd_we"] = 0
        if f3 == 0:
            if instr == 0x00000073:
                out.update(op=OP["ECALL"], exec=EX["ECALL"])
            elif instr == 0x00100073:
                out.update(op=OP["EBREAK"], exec=EX["EBREAK"])
            elif instr == 0x30200073:
                out.update(op=OP["MRET"], exec=EX["MRET"], is_mret=1)
            elif instr == 0x10500073:
                out.update(op=OP["WFI"], exec=EX["WFI"], is_wfi=1)
            else:
                return illegal()
        elif f3 == 4:
            return illegal()
        else:
            out.update(op=OP["CSR"], exec=EX["CSR"], is_csr=1,
                       csr_addr=(instr >> 20) & 0xfff,
                       rd_we=int(rd != 0),
                       csr_uimm_valid=int(f3 >= 5),
                       csr_uimm=rs1,
                       rs1=0 if f3 >= 5 else rs1,
                       uses1=int(f3 < 5 and rs1 != 0))
            out["csr_op"] = CSR["RW" if f3 in (1, 5) else
                                ("RS" if f3 in (2, 6) else "RC")]
    else:
        return illegal()
    return out


def enc_cases():
    cases = []
    def add(name, instr, note=""):
        cases.append((name, instr, note))

    # RV32I 40 instructions.
    add("LUI", u(0x37, 5, 0x12345))
    add("AUIPC", u(0x17, 5, 0x12345))
    add("JAL", j(0x6f, 5, 0x20))
    add("JALR", i(0x67, 5, 0, 6, 0x10))
    for name, f3 in (("BEQ", 0), ("BNE", 1), ("BLT", 4), ("BGE", 5),
                     ("BLTU", 6), ("BGEU", 7)):
        add(name, b(0x63, f3, 6, 7, 0x20))
    for name, f3, size in (("LB", 0, "BYTE"), ("LH", 1, "HALF"),
                           ("LW", 2, "WORD"), ("LBU", 4, "BYTE"),
                           ("LHU", 5, "HALF")):
        add(name, i(0x03, 5, f3, 6, 0x123))
    for name, f3 in (("SB", 0), ("SH", 1), ("SW", 2)):
        add(name, s(0x23, f3, 6, 7, 0x123))
    for name, f3 in (("ADDI", 0), ("SLTI", 2), ("SLTIU", 3), ("XORI", 4),
                     ("ORI", 6), ("ANDI", 7)):
        add(name, i(0x13, 5, f3, 6, -0x123))
    add("SLLI", i(0x13, 5, 1, 6, 0x1f))
    add("SRLI", i(0x13, 5, 5, 6, 0x1f))
    add("SRAI", i(0x13, 5, 5, 6, 0x41f))
    add("ADDI_min", i(0x13, 5, 0, 6, -2048))
    add("ADDI_max", i(0x13, 5, 0, 6, 2047))
    add("SLLI_0", i(0x13, 5, 1, 6, 0))
    add("SRLI_0", i(0x13, 5, 5, 6, 0))
    add("LB_x0", i(0x03, 0, 0, 6, 0x10))
    add("JAL_neg", j(0x6f, 5, -4))
    add("BEQ_neg", b(0x63, 0, 6, 7, -8))
    for name, f3, f7 in (("ADD", 0, 0), ("SLL", 1, 0), ("SLT", 2, 0),
                         ("SLTU", 3, 0), ("XOR", 4, 0), ("SRL", 5, 0),
                         ("OR", 6, 0), ("AND", 7, 0), ("SUB", 0, 0x20),
                         ("SRA", 5, 0x20)):
        add(name, r(0x33, 5, f3, 6, 7, f7))
    add("FENCE", 0x0ff0000f)
    add("FENCE.I", 0x0000100f)
    add("ECALL", 0x00000073)
    add("EBREAK", 0x00100073)
    # Zicsr six forms.
    add("CSRRW", i(0x73, 5, 1, 6, 0x300))
    add("CSRRS", i(0x73, 5, 2, 6, 0x300))
    add("CSRRC", i(0x73, 5, 3, 6, 0x300))
    add("CSRRWI", i(0x73, 5, 5, 31, 0x300))
    add("CSRRSI", i(0x73, 5, 6, 31, 0x300))
    add("CSRRCI", i(0x73, 5, 7, 31, 0x300))
    add("CSRRWI_0", i(0x73, 5, 5, 0, 0x300))
    add("CSRRS_rd0", i(0x73, 0, 2, 6, 0x300))
    add("MRET", 0x30200073)
    add("WFI", 0x10500073)
    # Legal hints / ignored FENCE fields.
    add("HINT_NOP", i(0x13, 0, 0, 0, 0))
    add("FENCE_fields", 0x0ff0000f | (5 << 7) | (6 << 15))
    # Illegal / unsupported encodings.
    add("ILL_MUL", r(0x33, 5, 0, 6, 7, 1))
    add("ILL_SRET", 0x10200073)
    add("ILL_SFENCE_VMA", 0x12000073)
    add("ILL_JAL_F3", i(0x6f, 5, 1, 0, 0))
    add("ILL_JALR_F3", i(0x67, 5, 1, 6, 0))
    add("ILL_BRANCH_F3", b(0x63, 2, 6, 7, 0))
    add("ILL_LOAD_F3", i(0x03, 5, 3, 6, 0))
    add("ILL_STORE_F3", s(0x23, 3, 6, 7, 0))
    add("ILL_OP_F7", r(0x33, 5, 1, 6, 7, 0x20))
    add("ILL_SLLI_F7", i(0x13, 5, 1, 6, 0x400 | 1))
    add("ILL_FENCE_F3", i(0x0f, 0, 2, 0, 0))
    add("ILL_SYSTEM_F3", i(0x73, 0, 4, 0, 0))
    add("ILL_OPCODE", 0x0000007f)
    add("ILL_C", 0x00000001)
    add("ILL_AMO", r(0x2f, 5, 2, 6, 7, 0))
    add("ILL_FP_LOAD", i(0x07, 5, 2, 6, 0))
    return cases


def main():
    cases = []
    for index, (name, instr, note) in enumerate(enc_cases()):
        d = decode(instr)
        pc = 0x80000000 + 4 * index
        cases.append((name, instr, pc, d, note))
    lines = []
    lines.append("// AUTO-GENERATED by verification/p1b/gen_decode_cases.py")
    lines.append("#pragma once")
    lines.append("#include <cstdint>")
    lines.append("struct ExpectedDecode {")
    for field in ("name", "instr", "pc", "op", "exec", "rd", "rs1", "rs2",
                  "uses1", "uses2", "rd_we", "imm", "mem_size", "csr_op",
                  "csr_addr", "csr_uimm", "csr_uimm_valid", "is_branch",
                  "is_jump", "is_load", "is_store", "is_csr", "is_fence",
                  "is_fence_i", "is_mret", "is_sret", "is_wfi", "illegal",
                  "illegal_cause", "illegal_tval"):
        if field in ("name",):
            lines.append("  const char* name;")
        elif field == "pc":
            lines.append("  uint32_t pc;")
        else:
            lines.append(f"  uint32_t {field};")
    lines.append("};")
    lines.append("static const ExpectedDecode kDecodeCases[] = {")
    for name, instr, pc, d, note in cases:
        vals = [f'"{name}"', f'0x{instr:08x}u', f'0x{pc:08x}u']
        for field in ("op", "exec", "rd", "rs1", "rs2", "uses1", "uses2",
                      "rd_we", "imm", "mem_size", "csr_op", "csr_addr",
                      "csr_uimm", "csr_uimm_valid", "is_branch", "is_jump",
                      "is_load", "is_store", "is_csr", "is_fence",
                      "is_fence_i", "is_mret", "is_sret", "is_wfi",
                      "illegal", "illegal_cause", "illegal_tval"):
            vals.append(f"0x{d[field] & 0xffffffff:x}u")
        lines.append("  {" + ", ".join(vals) + "},")
    lines.append("};")
    lines.append(f"static const unsigned kDecodeCaseCount = {len(cases)};")
    OUT.write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT.relative_to(ROOT)} cases={len(cases)}")


if __name__ == "__main__":
    main()
