// P0-02 invalid-parameter probe driver.
#include "Vtype_invalid_probe.h"
#include "verilated.h"

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vtype_invalid_probe* dut = new Vtype_invalid_probe;
  dut->eval();
  dut->final();
  delete dut;
  return 0;
}
