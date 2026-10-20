// P1-C ARF unit test: reset, dual read, commit write, x0 suppression.
#include "Varf_tb_top.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>

static int errors = 0;
static void check(bool c, const char* m, uint32_t g, uint32_t w) {
  if (!c) { std::fprintf(stderr, "P1C_ARF_FAIL: %s got=0x%x want=0x%x\n", m, g, w); ++errors; }
}
static void tick(Varf_tb_top* d) {
  d->clk = 0; d->eval(); d->clk = 1; d->eval(); d->clk = 0; d->eval();
}
static void write(Varf_tb_top* d, uint32_t r, uint32_t v) {
  d->we = 1; d->rd_addr = r; d->rd_data = v; tick(d); d->we = 0; d->eval();
}
static uint32_t read1(Varf_tb_top* d, uint32_t r) {
  d->rs1_addr = r; d->eval(); return d->rs1_data;
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Varf_tb_top* d = new Varf_tb_top;
  d->reset = 1; d->we = 0; d->rs1_addr = 0; d->rs2_addr = 0;
  d->rd_addr = 0; d->rd_data = 0;
  tick(d); tick(d);
  d->reset = 0; d->eval();
  for (uint32_t r = 0; r < 32; ++r) {
    check(read1(d, r) == 0, "reset zero", read1(d, r), 0);
  }
  write(d, 1, 0x11111111u);
  write(d, 2, 0x22222222u);
  write(d, 0, 0xdeadbeefu);  // suppressed
  check(read1(d, 1) == 0x11111111u, "write x1", read1(d, 1), 0x11111111u);
  check(read1(d, 2) == 0x22222222u, "write x2", read1(d, 2), 0x22222222u);
  check(read1(d, 0) == 0, "x0 read", read1(d, 0), 0);
  d->rs1_addr = 1; d->rs2_addr = 2; d->eval();
  check(d->rs1_data == 0x11111111u && d->rs2_data == 0x22222222u,
        "dual read", d->rs1_data ^ d->rs2_data, 0x33333333u);
  write(d, 1, 0x33333333u);
  check(read1(d, 1) == 0x33333333u, "WAW last write", read1(d, 1), 0x33333333u);
  delete d;
  if (errors) { std::printf("P1C_ARF_FAIL errors=%d\n", errors); return 1; }
  std::printf("P1C_ARF_PASS\n");
  return 0;
}
