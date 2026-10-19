// P0-02 type self-check driver.
#include "Vtype_selfcheck.h"
#include "verilated.h"

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vtype_selfcheck* dut = new Vtype_selfcheck;
  dut->eval();
  dut->final();
  delete dut;
  return 0;
}
