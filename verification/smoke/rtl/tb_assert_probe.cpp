// P0-01 negative assertion probe driver. The DUT assertion fires on the
// first rising edge and must abort the process with a non-zero status.
#include "Vassert_probe.h"
#include "verilated.h"

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vassert_probe* dut = new Vassert_probe;

  dut->clk = 0;
  dut->eval();
  dut->clk = 1;
  dut->eval();
  dut->clk = 0;
  dut->eval();

  dut->final();
  delete dut;
  return 0;
}
