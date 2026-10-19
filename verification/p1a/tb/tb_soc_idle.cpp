// P1-A SoC idle skeleton check: no fabricated memory request or retirement.
#include "Vsoc_idle_tb_top.h"
#include "verilated.h"

#include <cstdio>

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vsoc_idle_tb_top* dut = new Vsoc_idle_tb_top;
  int errors = 0;

  auto tick = [&]() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
    dut->clk = 0; dut->eval();
  };
  dut->reset = 1;
  for (int i = 0; i < 3; ++i) tick();
  dut->reset = 0;
  for (int i = 0; i < 16; ++i) {
    tick();
    if (dut->mem_req_valid_o) {
      std::fprintf(stderr, "P1-A_CORE_IDLE_FAIL: memory request in idle skeleton\n");
      ++errors;
    }
    if (dut->commit_slot_valid || dut->commit_trap_valid) {
      std::fprintf(stderr, "P1-A_CORE_IDLE_FAIL: fabricated retire/trap event\n");
      ++errors;
    }
    if (!dut->core_idle_o || !dut->mem_resp_ready_o) {
      std::fprintf(stderr, "P1-A_CORE_IDLE_FAIL: idle/ready state wrong\n");
      ++errors;
    }
  }
  dut->final();
  delete dut;
  if (errors == 0) {
    std::printf("P1-A_CORE_IDLE_PASS cycles=16 retire=0 trap=0 mem_req=0\n");
    return 0;
  }
  return 1;
}
