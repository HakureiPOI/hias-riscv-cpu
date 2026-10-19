// P0-01 self-checking testbench for the valid/ready fixture.
// The scoreboard is an independent std::deque, not derived from DUT state.
#include "Vsmoke_buffer.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <random>

struct Inputs {
  bool reset;
  bool flush;
  bool in_valid;
  uint16_t in_data;
  bool out_ready;
};

struct Outputs {
  bool in_ready;
  bool out_valid;
  uint16_t out_data;
};

struct Tb {
  Vsmoke_buffer* dut;
  std::deque<uint16_t> expected;
  uint64_t accepted = 0;
  uint64_t produced = 0;
  uint64_t flush_dropped = 0;
  uint64_t reset_dropped = 0;
  uint64_t cycles = 0;
  uint64_t max_cycles = 50000;
  bool no_cycle_limit = false;
  int errors = 0;

  explicit Tb(Vsmoke_buffer* d) : dut(d) {}

  void error(const char* msg) {
    std::fprintf(stderr, "P0-01_RTL_SMOKE_FAIL: %s (cycle=%llu)\n", msg,
                 static_cast<unsigned long long>(cycles));
    ++errors;
    if (errors >= 10) {
      std::fprintf(stderr, "P0-01_RTL_SMOKE_FAIL: too many errors\n");
      std::exit(1);
    }
  }

  void check(bool cond, const char* msg) {
    if (!cond) error(msg);
  }

  Outputs tick(const Inputs& in) {
    dut->reset = in.reset;
    dut->flush = in.flush;
    dut->in_valid = in.in_valid;
    dut->in_data = in.in_data;
    dut->out_ready = in.out_ready;

    dut->clk = 0;
    dut->eval();

    Outputs out;
    out.in_ready = dut->in_ready;
    out.out_valid = dut->out_valid;
    out.out_data = dut->out_data;

    dut->clk = 1;
    dut->eval();
    ++cycles;

    if (!no_cycle_limit && cycles > max_cycles) {
      std::fprintf(stderr,
                   "P0-01_TIMEOUT: cycle budget exhausted (max_cycles=%llu)\n",
                   static_cast<unsigned long long>(max_cycles));
      std::exit(1);
    }

    const bool reset = in.reset;
    const bool flush = in.flush;
    const bool do_accept = !reset && !flush && in.in_valid && out.in_ready;
    const bool do_transfer = !reset && !flush && out.out_valid && in.out_ready;

    if (do_transfer) {
      if (expected.empty()) {
        error("output transfer with empty scoreboard");
      } else {
        const uint16_t want = expected.front();
        expected.pop_front();
        if (want != out.out_data) {
          char buf[128];
          std::snprintf(buf, sizeof(buf),
                        "output mismatch: got 0x%04x expected 0x%04x",
                        static_cast<unsigned>(out.out_data),
                        static_cast<unsigned>(want));
          error(buf);
        }
      }
      ++produced;
    }

    if (reset) {
      reset_dropped += expected.size();
      expected.clear();
    } else if (flush) {
      flush_dropped += expected.size();
      expected.clear();
    }

    if (do_accept) {
      expected.push_back(in.in_data);
      ++accepted;
    }

    return out;
  }
};

static Inputs idle_inputs() {
  Inputs in;
  in.reset = false;
  in.flush = false;
  in.in_valid = false;
  in.in_data = 0;
  in.out_ready = false;
  return in;
}

static void reset_dut(Tb& tb) {
  Inputs in = idle_inputs();
  in.reset = true;
  for (int i = 0; i < 3; ++i) tb.tick(in);
  in.reset = false;
  in.out_ready = true;
  Outputs out = tb.tick(in);
  tb.check(!out.out_valid, "out_valid asserted after reset");
  tb.check(tb.expected.empty(), "scoreboard not empty after reset");
}

static void push_one(Tb& tb, uint16_t data) {
  Inputs in = idle_inputs();
  in.in_valid = true;
  in.in_data = data;
  Outputs out = tb.tick(in);
  tb.check(out.in_ready, "single push unexpectedly backpressured");
}

static void pop_one(Tb& tb, uint16_t want) {
  Inputs in = idle_inputs();
  in.out_ready = true;
  Outputs out = tb.tick(in);
  tb.check(out.out_valid, "expected output valid");
  tb.check(out.out_data == want, "pop_one data mismatch");
}

static void directed_tests(Tb& tb) {
  // Reset: empty, ready to accept.
  reset_dut(tb);
  {
    Inputs in = idle_inputs();
    in.out_ready = true;
    Outputs out = tb.tick(in);
    tb.check(out.in_ready, "input not ready after reset");
    tb.check(!out.out_valid, "output valid after reset");
  }

  // Single transfer.
  push_one(tb, 0xA5A5);
  pop_one(tb, 0xA5A5);

  // Back-to-back fill with output stalled, then drain in order.
  for (int i = 0; i < 4; ++i) push_one(tb, static_cast<uint16_t>(0x1000 + i));
  {
    Inputs in = idle_inputs();
    Outputs out = tb.tick(in);
    tb.check(!out.in_ready, "FIFO did not report full");
  }
  for (int i = 0; i < 4; ++i) pop_one(tb, static_cast<uint16_t>(0x1000 + i));

  // Full must not overwrite. Hold the source valid while full (the protocol
  // requires a stalled source to keep valid/data), then pop and accept it.
  for (int i = 0; i < 4; ++i) push_one(tb, static_cast<uint16_t>(0x2000 + i));
  {
    const uint64_t accepted_before = tb.accepted;
    Inputs in = idle_inputs();
    in.in_valid = true;
    in.in_data = 0xDEAD;
    for (int i = 0; i < 3; ++i) {
      Outputs out = tb.tick(in);
      tb.check(!out.in_ready, "full FIFO asserted in_ready");
      tb.check(!out.out_valid || out.out_data == 0x2000,
               "full FIFO corrupted oldest entry");
    }
    tb.check(tb.accepted == accepted_before,
             "full FIFO accepted an extra item");
    // Make room while keeping the source valid. in_ready is still low on the
    // drain cycle (the FIFO is full until the edge), so the held item is
    // accepted on the following cycle.
    in.out_ready = true;
    Outputs out = tb.tick(in);
    tb.check(out.out_valid && out.out_data == 0x2000,
             "drain did not return oldest entry");
    out = tb.tick(in);
    tb.check(out.in_ready, "FIFO did not become ready after drain");
    tb.check(tb.accepted == accepted_before + 1,
             "held item was not accepted after drain");
  }
  // The held item was accepted on the same cycle that 0x2001 was drained;
  // three items remain (0x2002, 0x2003, 0xDEAD).
  pop_one(tb, 0x2002);
  pop_one(tb, 0x2003);
  pop_one(tb, 0xDEAD);

  // Output backpressure: valid/data must be held.
  push_one(tb, 0xBEEF);
  for (int i = 0; i < 5; ++i) {
    Inputs in = idle_inputs();
    Outputs out = tb.tick(in);
    tb.check(out.out_valid, "output valid dropped under backpressure");
    tb.check(out.out_data == 0xBEEF, "output data changed under backpressure");
  }
  pop_one(tb, 0xBEEF);

  // Same-cycle input/output (first word fall-through is NOT used; this checks
  // a simultaneous pop+push after priming the FIFO).
  push_one(tb, 0x0100);
  for (int i = 0; i < 16; ++i) {
    Inputs in = idle_inputs();
    in.in_valid = true;
    in.in_data = static_cast<uint16_t>(0x0100 + i + 1);
    in.out_ready = true;
    Outputs out = tb.tick(in);
    tb.check(out.out_valid, "same-cycle transfer missing output valid");
    tb.check(out.out_data == static_cast<uint16_t>(0x0100 + i),
             "same-cycle transfer order mismatch");
  }
  pop_one(tb, 0x0110);

  // Flush drops pending items and clears the interface. Flush is sampled on
  // the rising edge, so the check is made on the following cycle.
  for (int i = 0; i < 3; ++i) push_one(tb, static_cast<uint16_t>(0x3000 + i));
  {
    Inputs in = idle_inputs();
    in.flush = true;
    tb.tick(in);
    tb.check(tb.expected.empty(), "scoreboard not cleared by flush");
  }
  {
    Inputs in = idle_inputs();
    in.out_ready = true;
    Outputs out = tb.tick(in);
    tb.check(!out.out_valid, "flush did not clear pending output");
  }
  push_one(tb, 0xCAFE);
  pop_one(tb, 0xCAFE);

  // Reset also drops pending items.
  for (int i = 0; i < 2; ++i) push_one(tb, static_cast<uint16_t>(0x4000 + i));
  {
    Inputs in = idle_inputs();
    in.reset = true;
    tb.tick(in);
    tb.check(tb.expected.empty(), "scoreboard not cleared by reset");
  }
  {
    Inputs in = idle_inputs();
    in.out_ready = true;
    Outputs out = tb.tick(in);
    tb.check(!out.out_valid, "reset did not clear pending output");
  }
}

static void random_test(Tb& tb, unsigned seed, uint64_t cycles) {
  std::mt19937 rng(seed);
  bool pending_valid = false;
  uint16_t pending_data = 0;

  for (uint64_t i = 0; i < cycles; ++i) {
    const bool flush = (rng() % 257) == 0;
    const bool out_ready = (rng() % 100) < 60;

    if (flush) {
      // Flush cancels a pending source transaction.
      pending_valid = false;
    } else if (!pending_valid && ((rng() % 100) < 75)) {
      pending_valid = true;
      pending_data = static_cast<uint16_t>(rng());
    }

    Inputs in = idle_inputs();
    in.flush = flush;
    in.in_valid = pending_valid;
    in.in_data = pending_data;
    in.out_ready = out_ready;
    Outputs out = tb.tick(in);

    if (!flush && pending_valid && out.in_ready) pending_valid = false;
  }

  // Drain with no new input.
  uint64_t drain_cycles = 0;
  while (!tb.expected.empty() && drain_cycles < 4 * 1024) {
    Inputs in = idle_inputs();
    in.out_ready = true;
    tb.tick(in);
    ++drain_cycles;
  }

  tb.check(tb.expected.empty(), "FIFO did not drain after random stimulus");
  tb.check(tb.accepted == tb.produced + tb.flush_dropped + tb.reset_dropped,
           "conservation failure: accepted != produced + dropped");
  tb.check(tb.accepted >= 1000, "random test moved too few items");
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);

  uint64_t max_cycles = 50000;
  bool hang = false;
  bool no_cycle_limit = false;
  bool checker_probe = false;
  unsigned seed = 0x5EED1234u;

  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "+hang") == 0) {
      hang = true;
    } else if (std::strcmp(argv[i], "+no_cycle_limit") == 0) {
      no_cycle_limit = true;
    } else if (std::strcmp(argv[i], "+checker_probe") == 0) {
      checker_probe = true;
    } else if (std::strncmp(argv[i], "+max_cycles=", 12) == 0) {
      max_cycles = std::strtoull(argv[i] + 12, nullptr, 0);
    }
  }

  Vsmoke_buffer* dut = new Vsmoke_buffer;
  Tb tb(dut);
  tb.max_cycles = max_cycles;
  tb.no_cycle_limit = no_cycle_limit;

  std::printf("P0-01_RTL_SMOKE: start seed=0x%08x random_cycles=10000\n", seed);
  std::fflush(stdout);

  reset_dut(tb);

  if (hang) {
    std::printf("P0-01_TIMEOUT_PROBE: entering intentional hang\n");
    std::fflush(stdout);
    Inputs in = idle_inputs();
    in.in_valid = true;
    in.in_data = 0x1234;
    for (;;) tb.tick(in);
  }

  directed_tests(tb);

  if (checker_probe) {
    // Negative control for the scoreboard: deliberately compare against a
    // wrong expected value. The checker must report an error and exit 1.
    std::printf("P0-01_CHECKER_PROBE: expecting deliberate mismatch\n");
    push_one(tb, 0x1111);
    pop_one(tb, 0x2222);
    if (tb.errors > 0) {
      std::printf("P0-01_CHECKER_PROBE_DETECTED errors=%d\n", tb.errors);
      delete dut;
      return 1;
    }
    std::fprintf(stderr,
                 "P0-01_CHECKER_PROBE_NOT_DETECTED: checker missed mismatch\n");
    delete dut;
    return 0;
  }

  random_test(tb, seed, 10000);

  if (tb.errors != 0) {
    std::fprintf(stderr, "P0-01_RTL_SMOKE_FAIL: %d error(s)\n", tb.errors);
    delete dut;
    return 1;
  }

  std::printf(
      "P0-01_RTL_SMOKE_PASS cycles=%llu accepted=%llu produced=%llu "
      "flush_dropped=%llu remaining=0\n",
      static_cast<unsigned long long>(tb.cycles),
      static_cast<unsigned long long>(tb.accepted),
      static_cast<unsigned long long>(tb.produced),
      static_cast<unsigned long long>(tb.flush_dropped));

  delete dut;
  return 0;
}
