// P0-02-R2 interface fixture driver: contract checks only, not a CPU.
#include "Vinterface_fixture.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <map>
#include <vector>

struct Fixture {
  Vinterface_fixture* dut;
  int errors = 0;

  explicit Fixture(Vinterface_fixture* d) : dut(d) {}

  void fail(const char* msg, int value = -1) {
    if (value >= 0)
      std::fprintf(stderr, "P0-02_IF_FAIL: %s (%d)\n", msg, value);
    else
      std::fprintf(stderr, "P0-02_IF_FAIL: %s\n", msg);
    ++errors;
    if (errors > 30) {
      std::fprintf(stderr, "P0-02_IF_FAIL: too many errors\n");
      std::exit(1);
    }
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

  void sample() {
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

  // ---- two-slot prefix sender/receiver scoreboard -------------------------
  void prefix_tests() {
    std::deque<uint8_t> pending;
    std::deque<uint8_t> expected;
    for (uint8_t i = 0; i < 6; ++i) {
      pending.push_back(static_cast<uint8_t>(0x40 + i));
      expected.push_back(static_cast<uint8_t>(0x40 + i));
    }
    uint8_t accepted_count = 0;

    auto drive_pending = [&]() {
      dut->in_valid = 0;
      dut->in0_tag = 0;
      dut->in1_tag = 0;
      if (!pending.empty()) {
        dut->in_valid = 1;
        dut->in0_tag = pending[0];
        if (pending.size() > 1) {
          dut->in_valid = 3;
          dut->in1_tag = pending[1];
        }
      }
    };

    auto step = [&]() {
      drive_pending();
      sample();
      const uint8_t n = dut->accept_count;
      const uint8_t av = dut->accepted_valid;
      const uint8_t tag0 = dut->accepted0;
      const uint8_t tag1 = dut->accepted1;
      check(n <= dut->resources, "accept_count exceeds resources");
      check(av == ((n == 2) ? 3 : (n == 1 ? 1 : 0)),
            "accepted_valid is not a prefix");
      if (n > static_cast<uint8_t>(pending.size())) {
        fail("accepted more slots than pending");
      }
      for (uint8_t i = 0; i < n; ++i) {
        const uint8_t got = (i == 0) ? tag0 : tag1;
        if (got != expected[i]) fail("accepted tag/order mismatch", got);
      }
      for (uint8_t i = 0; i < n; ++i) {
        pending.pop_front();
        expected.pop_front();
      }
      accepted_count = static_cast<uint8_t>(accepted_count + n);
      tick();
    };

    // First step: two slots; second: two slots.
    dut->resources = 2;
    step();
    step();
    check(accepted_count == 4, "first prefix transfers");

    // Two slots but only one resource: exactly S0, then the retained S1.
    dut->resources = 1;
    step();
    check(accepted_count == 5, "resource=1 accepts exactly S0");
    dut->resources = 2;
    step();
    check(accepted_count == 6, "retained S1 accepted once");
    check(expected.empty() && pending.empty(), "pending queue not drained");

    // Four cycles of zero resources, then one slot is accepted once.
    pending.push_back(0x50);
    expected.push_back(0x50);
    dut->resources = 0;
    for (int i = 0; i < 4; ++i) step();
    check(accepted_count == 6, "accept under zero resources");
    dut->resources = 2;
    step();
    check(accepted_count == 7, "pending slot lost after backpressure");

    // Flush suppresses acceptance and the source drops the transaction.
    pending.push_back(0x60);
    expected.push_back(0x60);
    dut->flush = 1;
    step();
    dut->flush = 0;
    check(accepted_count == 7, "flush accepted a slot");
    pending.clear();
    expected.clear();
    step();
  }

  // ---- token ownership ----------------------------------------------------
  struct Token { uint8_t idx; uint8_t gen; };
  std::map<uint8_t, uint8_t> active;

  Token alloc_ok() {
    dut->alloc_req = 1;
    sample();
    check(dut->alloc_ready, "allocation unexpectedly blocked");
    Token tok{static_cast<uint8_t>(dut->alloc_idx),
              static_cast<uint8_t>(dut->alloc_gen)};
    tick();
    dut->alloc_req = 0;
    if (active.count(tok.idx)) fail("allocation reused an active index", tok.idx);
    active[tok.idx] = tok.gen;
    return tok;
  }

  bool alloc_ready() {
    sample();
    return dut->alloc_ready;
  }

  bool free_token(uint8_t idx, uint8_t gen) {
    dut->resp_valid = 1;
    dut->resp_idx = idx;
    dut->resp_gen = gen;
    sample();
    const bool accept = dut->resp_accept;
    tick();
    dut->resp_valid = 0;
    if (accept) active.erase(idx);
    return accept;
  }

  bool free_expect(uint8_t idx, uint8_t gen, bool want) {
    const bool got = free_token(idx, gen);
    if (got != want) fail("response acceptance mismatch", got);
    return got;
  }

  void check_count(const char* where) {
    if (dut->active_count != active.size())
      fail(where, static_cast<int>(dut->active_count));
  }

  void token_tests() {
    // Flush: cancelled identity stays in flight; a different token is assigned.
    reset_fixture();
    if (!active.empty()) active.clear();
    Token a = alloc_ok();
    dut->flush = 1;
    tick();
    dut->flush = 0;
    check_count("flush changed in-flight count");
    Token b = alloc_ok();
    check(a.idx != b.idx || a.gen != b.gen, "identity reused after flush");
    free_expect(a.idx, a.gen, true);
    free_expect(b.idx, b.gen, true);
    check_count("drain after flush");

    // Same-cycle allocation + completion: net count must not change.
    reset_fixture();
    active.clear();
    Token t0 = alloc_ok();
    Token t1 = alloc_ok();
    free_expect(t0.idx, t0.gen, true);
    Token t2 = alloc_ok();
    // next index is free; complete t1 on the same edge as allocating t3.
    const uint8_t before = dut->active_count;
    dut->alloc_req = 1;
    sample();
    check(dut->alloc_ready, "same-cycle allocation blocked unexpectedly");
    const Token t3{static_cast<uint8_t>(dut->alloc_idx),
                   static_cast<uint8_t>(dut->alloc_gen)};
    dut->resp_valid = 1;
    dut->resp_idx = t1.idx;
    dut->resp_gen = t1.gen;
    tick();
    dut->alloc_req = 0;
    dut->resp_valid = 0;
    if (dut->active_count != before)
      fail("same-cycle alloc/free changed net count",
           static_cast<int>(dut->active_count));
    active.erase(t1.idx);
    if (active.count(t3.idx)) fail("same-cycle allocation overwrote active index");
    active[t3.idx] = t3.gen;
    check(dut->active_count == active.size(), "same-cycle accounting mismatch");
    (void)t2;
    while (!active.empty()) {
      auto it = active.begin();
      free_expect(it->first, it->second, true);
    }

    // Non-head completion must not allow overwriting the active head.
    reset_fixture();
    active.clear();
    Token a0 = alloc_ok(), a1 = alloc_ok(), a2 = alloc_ok(), a3 = alloc_ok();
    free_expect(a1.idx, a1.gen, true);
    check(!alloc_ready(), "allocation overwrote an active non-head target");
    free_expect(a0.idx, a0.gen, true);
    check(alloc_ready(), "allocation did not restart after head freed");
    Token a4 = alloc_ok();
    (void)a2; (void)a3; (void)a4;
    while (!active.empty()) {
      auto it = active.begin();
      free_expect(it->first, it->second, true);
    }

    // Flush and completion in the same cycle: completion is accounted, no
    // new allocation, and no cleared item is resurrected.
    reset_fixture();
    active.clear();
    Token f0 = alloc_ok(), f1 = alloc_ok();
    dut->flush = 1;
    dut->resp_valid = 1;
    dut->resp_idx = f0.idx;
    dut->resp_gen = f0.gen;
    dut->alloc_req = 1;
    sample();
    check(!dut->alloc_ready, "allocation allowed during flush");
    tick();
    dut->flush = 0;
    dut->resp_valid = 0;
    dut->alloc_req = 0;
    active.erase(f0.idx);
    check(dut->active_count == active.size(), "flush+completion accounting");
    check(!free_token(f0.idx, f0.gen), "duplicate completion accepted");
    free_expect(f1.idx, f1.gen, true);
    check_count("flush+completion drain");

    // Drain-before-wrap, including a cancelled final token.
    reset_fixture();
    active.clear();
    for (int i = 0; i < 8; ++i) {
      Token t = alloc_ok();
      if (i == 7) {
        // Generation 7 is the last value for GEN_W=3.
        check(!alloc_ready(), "wrap freeze did not stop allocation");
        free_expect(t.idx, t.gen, true);
        tick();
        check(alloc_ready(), "allocation did not restart after wrap drain");
        Token again = alloc_ok();
        check(again.gen == 0, "generation did not restart after wrap");
        free_expect(again.idx, again.gen, true);
      } else {
        free_expect(t.idx, t.gen, true);
      }
    }
    active.clear();
  }
};

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vinterface_fixture* dut = new Vinterface_fixture;
  Fixture fx(dut);
  fx.prefix_tests();
  fx.token_tests();
  dut->final();
  delete dut;
  if (fx.errors == 0) {
    std::printf("P0-02_INTERFACE_FIXTURE_PASS\n");
    return 0;
  }
  std::fprintf(stderr, "P0-02_INTERFACE_FIXTURE_FAIL errors=%d\n", fx.errors);
  return 1;
}
