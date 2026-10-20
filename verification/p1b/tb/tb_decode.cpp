// P1-B decode unit test using the independent generated expectation table.
#include "Vdecode_tb_top.h"
#include "verilated.h"
#include "../decode_expected.h"

#include <cstdio>
#include <cstring>

struct Tb {
  Vdecode_tb_top* dut;
  int errors = 0;
  bool mismatch_probe = false;

  explicit Tb(Vdecode_tb_top* d) : dut(d) {}

  void check(bool cond, const char* msg, uint32_t got = 0, uint32_t want = 0) {
    if (!cond) {
      std::fprintf(stderr, "P1-B_DECODE_FAIL: %s got=0x%x want=0x%x\n",
                   msg, got, want);
      ++errors;
    }
  }

  void drive(uint32_t instr, uint32_t pc, bool exc = false,
             uint32_t exc_tval = 0, uint8_t exc_cause = 1) {
    dut->fetch_valid = 1;
    dut->fetch_pc = pc;
    dut->fetch_instr = instr;
    dut->fetch_pred_taken = 0;
    dut->fetch_pred_target = pc + 4;
    dut->fetch_pred_index = 0x5a;
    dut->fetch_exc_valid = exc;
    dut->fetch_exc_cause = exc_cause;
    dut->fetch_exc_tval = exc_tval;
    dut->fetch_gen = 0x3c;
    dut->eval();
  }
};

static void compare_common(Tb& tb, const ExpectedDecode& e, bool illegal_ok) {
  tb.check(tb.dut->dec_valid == 1, "valid");
  tb.check(tb.dut->dec_pc == e.pc, "pc", tb.dut->dec_pc, e.pc);
  tb.check(tb.dut->dec_instr == e.instr, "instr", tb.dut->dec_instr, e.instr);
  tb.check(tb.dut->dec_pred_index == 0x5a, "pred_index", tb.dut->dec_pred_index, 0x5a);
  tb.check(tb.dut->dec_pred_taken == 0, "pred_taken", tb.dut->dec_pred_taken, 0);
  tb.check(tb.dut->dec_pred_target == e.pc + 4, "pred_target",
           tb.dut->dec_pred_target, e.pc + 4);
  tb.check(tb.dut->dec_fetch_gen == 0x3c, "fetch_gen", tb.dut->dec_fetch_gen, 0x3c);
  tb.check(tb.dut->dec_fetch_exc_valid == 0, "unexpected fetch exception");
  if (illegal_ok && e.illegal) {
    tb.check(tb.dut->dec_illegal == 1, "illegal", tb.dut->dec_illegal, 1);
    tb.check(tb.dut->dec_illegal_cause == 2, "illegal_cause",
             tb.dut->dec_illegal_cause, 2);
    tb.check(tb.dut->dec_illegal_tval == e.instr, "illegal_tval",
             tb.dut->dec_illegal_tval, e.instr);
    tb.check(tb.dut->dec_rd_we == 0, "illegal rd_we", tb.dut->dec_rd_we, 0);
    tb.check(tb.dut->dec_is_branch == 0 && tb.dut->dec_is_jump == 0 &&
             tb.dut->dec_is_load == 0 && tb.dut->dec_is_store == 0 &&
             tb.dut->dec_is_csr == 0 && tb.dut->dec_is_fence == 0 &&
             tb.dut->dec_is_fence_i == 0 && tb.dut->dec_is_mret == 0 &&
             tb.dut->dec_is_sret == 0 && tb.dut->dec_is_wfi == 0,
             "illegal side-effect flags");
    return;
  }
  tb.check(tb.dut->dec_illegal == e.illegal, "illegal flag",
           tb.dut->dec_illegal, e.illegal);
  tb.check(tb.dut->dec_op == e.op, "op", tb.dut->dec_op, e.op);
  tb.check(tb.dut->dec_exec == e.exec, "exec", tb.dut->dec_exec, e.exec);
  tb.check(tb.dut->dec_rd == e.rd, "rd", tb.dut->dec_rd, e.rd);
  tb.check(tb.dut->dec_rs1 == e.rs1, "rs1", tb.dut->dec_rs1, e.rs1);
  tb.check(tb.dut->dec_rs2 == e.rs2, "rs2", tb.dut->dec_rs2, e.rs2);
  tb.check(tb.dut->dec_uses1 == (e.uses1 != 0), "uses1", tb.dut->dec_uses1, e.uses1);
  tb.check(tb.dut->dec_uses2 == (e.uses2 != 0), "uses2", tb.dut->dec_uses2, e.uses2);
  tb.check(tb.dut->dec_rd_we == (e.rd_we != 0), "rd_we", tb.dut->dec_rd_we, e.rd_we);
  tb.check(tb.dut->dec_imm == e.imm, "imm", tb.dut->dec_imm, e.imm);
  tb.check(tb.dut->dec_mem_size == e.mem_size, "mem_size",
           tb.dut->dec_mem_size, e.mem_size);
  tb.check(tb.dut->dec_csr_op == e.csr_op, "csr_op", tb.dut->dec_csr_op, e.csr_op);
  tb.check(tb.dut->dec_csr_addr == e.csr_addr, "csr_addr",
           tb.dut->dec_csr_addr, e.csr_addr);
  tb.check(tb.dut->dec_csr_uimm == e.csr_uimm, "csr_uimm",
           tb.dut->dec_csr_uimm, e.csr_uimm);
  tb.check(tb.dut->dec_csr_uimm_valid == (e.csr_uimm_valid != 0),
           "csr_uimm_valid", tb.dut->dec_csr_uimm_valid, e.csr_uimm_valid);
  tb.check(tb.dut->dec_is_branch == (e.is_branch != 0), "is_branch",
           tb.dut->dec_is_branch, e.is_branch);
  tb.check(tb.dut->dec_is_jump == (e.is_jump != 0), "is_jump",
           tb.dut->dec_is_jump, e.is_jump);
  tb.check(tb.dut->dec_is_load == (e.is_load != 0), "is_load",
           tb.dut->dec_is_load, e.is_load);
  tb.check(tb.dut->dec_is_store == (e.is_store != 0), "is_store",
           tb.dut->dec_is_store, e.is_store);
  tb.check(tb.dut->dec_is_csr == (e.is_csr != 0), "is_csr",
           tb.dut->dec_is_csr, e.is_csr);
  tb.check(tb.dut->dec_is_fence == (e.is_fence != 0), "is_fence",
           tb.dut->dec_is_fence, e.is_fence);
  tb.check(tb.dut->dec_is_fence_i == (e.is_fence_i != 0), "is_fence_i",
           tb.dut->dec_is_fence_i, e.is_fence_i);
  tb.check(tb.dut->dec_is_mret == (e.is_mret != 0), "is_mret",
           tb.dut->dec_is_mret, e.is_mret);
  tb.check(tb.dut->dec_is_sret == (e.is_sret != 0), "is_sret",
           tb.dut->dec_is_sret, e.is_sret);
  tb.check(tb.dut->dec_is_wfi == (e.is_wfi != 0), "is_wfi",
           tb.dut->dec_is_wfi, e.is_wfi);
}

static void check_jal_anchor(Tb& tb, uint32_t instr, uint32_t rd,
                             int32_t imm) {
  tb.drive(instr, 0x80000200u);
  tb.check(tb.dut->dec_valid == 1, "JAL anchor valid");
  tb.check(tb.dut->dec_illegal == 0, "JAL anchor illegal", tb.dut->dec_illegal, 0);
  tb.check(tb.dut->dec_pc == 0x80000200u, "JAL anchor pc",
           tb.dut->dec_pc, 0x80000200u);
  tb.check(tb.dut->dec_op == 2, "JAL anchor op", tb.dut->dec_op, 2);
  tb.check(tb.dut->dec_exec == 21, "JAL anchor exec", tb.dut->dec_exec, 21);
  tb.check(tb.dut->dec_rd == rd, "JAL anchor rd", tb.dut->dec_rd, rd);
  tb.check(tb.dut->dec_imm == static_cast<uint32_t>(imm), "JAL anchor imm",
           tb.dut->dec_imm, static_cast<uint32_t>(imm));
  tb.check(tb.dut->dec_is_jump == 1, "JAL anchor is_jump",
           tb.dut->dec_is_jump, 1);
  tb.check(tb.dut->dec_rd_we == (rd != 0), "JAL anchor rd_we",
           tb.dut->dec_rd_we, rd != 0);
  tb.check(tb.dut->dec_uses1 == 0 && tb.dut->dec_uses2 == 0,
           "JAL anchor source use");
}

static void check_jal_anchors(Tb& tb) {
  // Fixed field values manually checked against the locked RV32I J-type
  // encoding and the assembler/objdump anchor in verification/p1b/spec.
  check_jal_anchor(tb, 0x000010efu, 1, 4096);
  check_jal_anchor(tb, 0x000012efu, 5, 4096);
  check_jal_anchor(tb, 0x0020006fu, 0, 2);
  check_jal_anchor(tb, 0xffdfffefu, 31, -4);
  check_jal_anchor(tb, 0x7fffffefu, 31, 1048574);
  check_jal_anchor(tb, 0x800002efu, 5, -1048576);
  static const struct { uint32_t instr; uint32_t rd; int32_t imm; } f3[8] = {
    {0x000000efu, 1, 0},       {0x0000116fu, 2, 0x1000},
    {0x000021efu, 3, 0x2000},  {0x0000326fu, 4, 0x3000},
    {0x000042efu, 5, 0x4000},  {0x0000536fu, 6, 0x5000},
    {0x000063efu, 7, 0x6000},  {0x0000f46fu, 8, 0xf000},
  };
  for (unsigned i = 0; i < 8; ++i) {
    tb.check(((f3[i].instr >> 12) & 7u) == i, "JAL field value");
    check_jal_anchor(tb, f3[i].instr, f3[i].rd, f3[i].imm);
  }
}

int main(int argc, char** argv) {
  bool mismatch = false;
  for (int i = 1; i < argc; ++i)
    if (std::strcmp(argv[i], "+mismatch") == 0) mismatch = true;
  Verilated::commandArgs(argc, argv);
  Vdecode_tb_top* dut = new Vdecode_tb_top;
  Tb tb(dut);
  tb.mismatch_probe = mismatch;

  for (unsigned i = 0; i < kDecodeCaseCount; ++i) {
    const ExpectedDecode& e = kDecodeCases[i];
    tb.drive(e.instr, e.pc);
    if (mismatch && i == 0) {
      // Deliberately corrupt one expected field; the normal field comparator
      // must reject it.
      ExpectedDecode bad = e;
      bad.op ^= 1u;
      compare_common(tb, bad, true);
    } else {
      compare_common(tb, e, true);
    }
  }

  check_jal_anchors(tb);

  // Fetch exception takes precedence and preserves its metadata.
  tb.drive(0xffffffffu, 0x80000100u, true, 0x80000100u, 1);
  tb.check(dut->dec_valid == 1, "exception valid");
  tb.check(dut->dec_instr == 0xffffffffu, "exception instr", dut->dec_instr, 0xffffffffu);
  tb.check(dut->dec_fetch_exc_valid == 1, "exception flag");
  tb.check(dut->dec_fetch_exc_cause == 1, "exception cause", dut->dec_fetch_exc_cause, 1);
  tb.check(dut->dec_fetch_exc_tval == 0x80000100u, "exception tval",
           dut->dec_fetch_exc_tval, 0x80000100u);
  tb.check(dut->dec_illegal == 0, "exception misclassified as illegal");
  tb.check(dut->dec_rd_we == 0, "exception rd_we", dut->dec_rd_we, 0);
  tb.check(dut->dec_fetch_gen == 0x3c, "exception fetch_gen", dut->dec_fetch_gen, 0x3c);

  dut->fetch_valid = 0;
  dut->fetch_instr = 0;
  dut->eval();
  tb.check(dut->dec_valid == 0, "invalid fetch produced decoded valid");

  if (mismatch) {
    if (tb.errors > 0) {
      std::printf("P1-B_DECODE_NEGATIVE_MISMATCH_DETECTED errors=%d\n", tb.errors);
      delete dut;
      return 1;
    }
    std::fprintf(stderr, "P1-B_DECODE_NEGATIVE_MISMATCH_NOT_DETECTED\n");
    delete dut;
    return 1;
  }
  if (tb.errors != 0) {
    std::fprintf(stderr, "P1-B_DECODE_FAIL errors=%d\n", tb.errors);
    delete dut;
    return 1;
  }
  std::printf("P1-B_DECODE_PASS cases=%u\n", kDecodeCaseCount);
  delete dut;
  return 0;
}
