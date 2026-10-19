// P0-02-R1 interface fixture driver.
#include "Vinterface_fixture.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>

struct Fixture {
  Vinterface_fixture* dut;
  int errors = 0;

  explicit Fixture(Vinterface_fixture* d) : dut(d) {}

  void fail(const char* msg) {
    std::fprintf(stderr, "P0-02_IF_FAIL: %s\n", msg);
    ++errors;
  }

  void check(bool cond, const char* msg) {
    if (!cond) fail(msg);
  }

  void tick() {
    dut->clk = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();
    dut->clk = 0;
    dut->eval();
  }

  void reset_fixture() {
    dut->reset = 1;
    dut->flush = 0;
    dut->in_valid = 0;
    dut->in0_tag = 0;
    dut->in1_tag = 0;
    dut->resources = 2;
    dut->alloc_req = 0;
    dut->resp_valid = 0;
    dut->resp_idx = 0;
    dut->resp_gen = 0;
    tick();
    dut->reset = 0;
    tick();
  }

  void set_slots(uint8_t valid, uint8_t tag0, uint8_t tag1) {
    dut->in_valid = valid;
    dut->in0_tag = tag0;
    dut->in1_tag = tag1;
  }

  void alloc_expect(uint8_t idx, uint8_t gen, const char* name) {
    dut->alloc_req = 1;
    // Sample combinational token before the edge.
    dut->clk = 0;
    dut->eval();
    const bool ready = dut->alloc_ready;
    const uint8_t got_idx = dut->alloc_idx;
    const uint8_t got_gen = dut->alloc_gen;
    check(ready, name);
    if (got_idx != idx) std::fprintf(stderr, "  %s: idx got=%u want=%u\n", name, got_idx, idx);
    if (got_gen != gen) std::fprintf(stderr, "  %s: gen got=%u want=%u\n", name, got_gen, gen);
    check(got_idx == idx, "token index mismatch");
    check(got_gen == gen, "token generation mismatch");
    tick();
    dut->alloc_req = 0;
  }

  void free_token(uint8_t idx, uint8_t gen, bool expect_accept, const char* name) {
    dut->resp_valid = 1;
    dut->resp_idx = idx;
    dut->resp_gen = gen;
    dut->clk = 0;
    dut->eval();
    check(dut->resp_accept == expect_accept, name);
    tick();
    dut->resp_valid = 0;
  }
};

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vinterface_fixture* dut = new Vinterface_fixture;
  Fixture fx(dut);
  fx.reset_fixture();

  // --- prefix acceptance / backpressure -----------------------------------
  fx.set_slots(0b00, 0x10, 0x11);
  dut->resources = 2;
  dut->clk = 0;
  dut->eval();
  fx.check(dut->accept_count == 0, "empty bundle accepted");
  fx.check(dut->accepted_valid == 0b00, "empty accepted_valid");

  fx.set_slots(0b11, 0x20, 0x21);
  dut->resources = 1;
  dut->clk = 0;
  dut->eval();
  fx.check(dut->accept_count == 1, "resource=1 must accept only S0");
  fx.check(dut->accepted_valid == 0b01, "S0+S1 partly accepted must be prefix 01");
  fx.tick();

  // Sender keeps S1 pending; it is now the only valid slot.
  fx.set_slots(0b01, 0x21, 0x22);
  dut->resources = 2;
  dut->clk = 0;
  dut->eval();
  fx.check(dut->accept_count == 1, "pending S1 must be accepted once");
  fx.check(dut->accepted0 == 0x21, "pending S1 tag changed");
  fx.tick();

  fx.set_slots(0b11, 0x30, 0x31);
  dut->resources = 2;
  dut->clk = 0;
  dut->eval();
  fx.check(dut->accept_count == 2, "resource=2 must accept both slots");
  fx.check(dut->accepted_valid == 0b11, "both accepted must be prefix 11");

  // Continuous backpressure must not accept anything.
  for (int i = 0; i < 4; ++i) {
    dut->resources = 0;
    dut->clk = 0;
    dut->eval();
    fx.check(dut->accept_count == 0, "accept under zero resources");
    fx.tick();
  }
  dut->resources = 2;
  dut->clk = 0;
  dut->eval();
  fx.check(dut->accept_count == 2, "bundle lost after backpressure");

  // Flush suppresses acceptance.
  dut->flush = 1;
  dut->clk = 0;
  dut->eval();
  fx.check(dut->accept_count == 0, "flush did not suppress acceptance");
  fx.tick();
  dut->flush = 0;
  fx.set_slots(0b00, 0, 0);
  fx.tick();

  // --- token allocation / stale response / wrap ---------------------------
  // GEN_W=1, DEPTH=4: allocate/free sequentially. The final token of the
  // maximum generation must freeze allocation even though the bank is not full.
  for (uint8_t idx = 0; idx < 4; ++idx) {
    fx.alloc_expect(idx, 0, "alloc gen0");
    fx.free_token(idx, 0, true, "free gen0");
  }
  for (uint8_t idx = 0; idx < 3; ++idx) {
    fx.alloc_expect(idx, 1, "alloc gen1");
    fx.free_token(idx, 1, true, "free gen1");
  }
  fx.alloc_expect(3, 1, "alloc final gen1 idx3");
  // Would wrap on the next allocation: freeze, but the bank is not full.
  dut->alloc_req = 1;
  dut->clk = 0;
  dut->eval();
  fx.check(!dut->alloc_ready, "allocation continued into generation wrap");
  dut->alloc_req = 0;

  // A stale response from an old generation/epoch must be rejected.
  fx.free_token(2, 0, false, "stale response rejected");
  fx.free_token(3, 1, true, "drain final token");
  fx.tick();  // wrap-unblock is visible on the cycle after the drain edge
  dut->clk = 0;
  dut->eval();
  fx.check(dut->alloc_ready, "allocation did not restart after drain");
  fx.alloc_expect(0, 0, "post-wrap alloc idx0 gen0");

  // Free it and prove a duplicate/late response is rejected.
  fx.free_token(0, 0, true, "post-wrap response accepted");
  fx.free_token(0, 0, false, "duplicate/late response rejected");

  dut->final();
  delete dut;

  if (fx.errors == 0) {
    std::printf("P0-02_INTERFACE_FIXTURE_PASS\n");
    return 0;
  }
  std::fprintf(stderr, "P0-02_INTERFACE_FIXTURE_FAIL errors=%d\n", fx.errors);
  return 1;
}
