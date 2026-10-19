// P1-A supplement: cancelled token + generation wrap joint case.
#include "Vinterface_fixture.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <map>

struct Tb {
  Vinterface_fixture* dut;
  std::map<uint8_t, uint8_t> active;
  int errors = 0;
  explicit Tb(Vinterface_fixture* d) : dut(d) {}
  void fail(const char* msg) {
    std::fprintf(stderr, "P1-A_TOKEN_JOINT_FAIL: %s\n", msg);
    ++errors;
  }
  void tick() { dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); dut->clk=0; dut->eval(); }
  void reset() {
    dut->reset=1; dut->flush=0; dut->in_valid=0; dut->resources=2;
    dut->alloc_req=0; dut->resp_valid=0;
    tick(); dut->reset=0; tick();
  }
  void alloc_expect(uint8_t idx, uint8_t gen) {
    dut->alloc_req=1; dut->clk=0; dut->eval();
    if (!dut->alloc_ready) fail("allocation unexpectedly blocked");
    if (dut->alloc_idx != idx || dut->alloc_gen != gen) fail("token sequence mismatch");
    tick(); dut->alloc_req=0;
    if (active.count(idx)) fail("active index reused");
    active[idx]=gen;
  }
  bool alloc_ready() { dut->clk=0; dut->eval(); return dut->alloc_ready; }
  bool free_token(uint8_t idx, uint8_t gen) {
    dut->resp_valid=1; dut->resp_idx=idx; dut->resp_gen=gen;
    dut->clk=0; dut->eval();
    bool a=dut->resp_accept;
    tick(); dut->resp_valid=0;
    if (a) active.erase(idx);
    return a;
  }
};

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vinterface_fixture* dut = new Vinterface_fixture;
  Tb tb(dut);
  tb.reset();

  // GEN_W=3, DEPTH=4: allocate/free through generation 6, then hold gen 7.
  for (int i = 0; i < 7; ++i) {
    uint8_t idx = static_cast<uint8_t>(i % 4);
    uint8_t gen = static_cast<uint8_t>(i); // generation advances per allocation
    tb.alloc_expect(idx, gen);
    if (!tb.free_token(idx, gen)) tb.fail("normal drain response rejected");
  }
  if (!tb.active.empty()) tb.fail("normal drain left active tokens");
  // 8th allocation has generation 7 (the maximum), then flush.
  tb.alloc_expect(3, 7);
  dut->flush = 1;
  tb.tick();
  dut->flush = 0;
  tb.tick();
  if (dut->active_count != 1) tb.fail("cancelled token lost from active count");
  if (dut->cancelled_count != 1) tb.fail("cancelled token not marked cancelled");
  for (int i = 0; i < 4; ++i) {
    if (tb.alloc_ready()) tb.fail("allocation not blocked before wrap drain");
    tb.tick();
  }
  if (!tb.free_token(3, 7)) tb.fail("cancelled token response rejected");
  tb.tick();
  if (!tb.active.empty()) tb.fail("drain left active tokens");
  if (dut->active_count != 0 || dut->cancelled_count != 0)
    tb.fail("counts not zero after cancelled-token drain");
  if (!tb.alloc_ready()) tb.fail("allocation did not resume after wrap drain");
  tb.alloc_expect(0, 0);
  if (!tb.free_token(0, 0)) tb.fail("post-wrap token response rejected");

  dut->final();
  delete dut;
  if (tb.errors == 0) {
    std::printf("P1-A_TOKEN_JOINT_PASS flush_wrap_drain=ok\n");
    return 0;
  }
  return 1;
}
