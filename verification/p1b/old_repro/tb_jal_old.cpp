// Reproduce F01 against the old P1-B decode (commit 278f6f7).
#include "Vdecode_tb_top.h"
#include "verilated.h"
#include <cstdio>

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vdecode_tb_top* dut = new Vdecode_tb_top;
  const unsigned words[2] = {0x000010efu, 0x000012efu};
  int illegal = 0;
  for (unsigned i = 0; i < 2; ++i) {
    dut->fetch_valid = 1;
    dut->fetch_pc = 0x80000300u + 4u * i;
    dut->fetch_instr = words[i];
    dut->fetch_pred_taken = 0;
    dut->fetch_pred_target = dut->fetch_pc + 4u;
    dut->fetch_pred_index = 0;
    dut->fetch_exc_valid = 0;
    dut->fetch_exc_cause = 0;
    dut->fetch_exc_tval = 0;
    dut->fetch_gen = 0;
    dut->eval();
    std::printf("OLD_F01 instr=0x%08x illegal=%u rd=%u imm=0x%08x\n",
                words[i], dut->dec_illegal, dut->dec_rd, dut->dec_imm);
    illegal += dut->dec_illegal;
  }
  delete dut;
  if (illegal != 0) {
    std::printf("OLD_F01_JAL_ILLEGAL reproduced=%d\n", illegal);
    return 0;
  }
  std::printf("OLD_F01_JAL_NOT_REPRODUCED\n");
  return 1;
}
