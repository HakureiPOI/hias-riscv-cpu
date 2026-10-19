// P1-A RAM/bridge module test. Independent byte-array memory model.
#include "Vram_bridge_tb_top.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <vector>

static constexpr uint64_t RAM_BASE = 0x80000000ull;
static constexpr uint64_t RAM_END = 0x80020000ull;

struct Req {
  bool store = false;
  uint32_t va = 0;
  uint64_t pa = 0;
  int size = 2;       // 0=byte, 1=half, 2=word
  uint8_t mask = 0xF;
  uint32_t wdata = 0;
  uint8_t id = 0;
  uint8_t gen = 0;
};

struct Resp {
  bool valid = false;
  bool error = false;
  uint8_t cause = 0;
  uint8_t id = 0;
  uint8_t gen = 0;
  uint32_t rdata = 0;
};

struct Tb {
  Vram_bridge_tb_top* dut;
  std::vector<uint8_t> mem;
  int errors = 0;
  uint64_t transactions = 0;
  uint64_t legal_count = 0;
  uint64_t illegal_count = 0;
  uint64_t cycles = 0;

  explicit Tb(Vram_bridge_tb_top* d) : dut(d), mem(128 * 1024) {
    for (size_t i = 0; i < mem.size(); ++i)
      mem[i] = static_cast<uint8_t>((i * 37 + 11) & 0xff);
  }

  void fail(const char* msg, uint64_t value = ~0ull) {
    if (value != ~0ull)
      std::fprintf(stderr, "P1-A_RAM_TB_FAIL: %s (0x%llx)\n", msg,
                   static_cast<unsigned long long>(value));
    else
      std::fprintf(stderr, "P1-A_RAM_TB_FAIL: %s\n", msg);
    ++errors;
  }

  void check(bool cond, const char* msg, uint64_t value = ~0ull) {
    if (!cond) fail(msg, value);
  }

  static int size_bytes(int size) { return 1 << size; }

  static uint32_t lane_wdata(const Req& r) {
    unsigned lane = r.pa & 3;
    if (r.size == 0) return (r.wdata & 0xffu) << (8 * lane);
    if (r.size == 1) return (r.wdata & 0xffffu) << (8 * lane);
    return r.wdata;
  }

  static bool aligned(const Req& r) {
    if (r.size == 0) return true;
    if (r.size == 1) return (r.pa & 1) == 0;
    return (r.pa & 3) == 0;
  }

  static bool mask_ok(const Req& r) {
    unsigned lane = r.pa & 3;
    if (r.size == 0) return r.mask == (1u << lane);
    if (r.size == 1) return r.mask == (3u << lane);
    return r.mask == 0xf;
  }

  static bool wdata_ok(const Req& r) {
    if (!r.store) return true;
    if (r.size == 0) return (r.wdata & 0xffffff00u) == 0;
    if (r.size == 1) return (r.wdata & 0xffff0000u) == 0;
    return true;
  }

  static bool in_range(const Req& r) {
    return r.pa >= RAM_BASE && (r.pa + size_bytes(r.size)) <= RAM_END;
  }

  static bool legal(const Req& r) {
    return in_range(r) && aligned(r) && mask_ok(r) && wdata_ok(r);
  }

  static uint8_t error_cause(const Req& r) {
    if (!in_range(r)) return r.store ? 7 : 5;
    if (!aligned(r)) return r.store ? 6 : 4;
    return r.store ? 7 : 5;
  }

  static uint64_t word_base(uint64_t pa) { return pa & ~3ull; }

  uint32_t read_word(uint64_t base) const {
    const uint64_t off = base - RAM_BASE;
    return static_cast<uint32_t>(mem[off]) |
           (static_cast<uint32_t>(mem[off + 1]) << 8) |
           (static_cast<uint32_t>(mem[off + 2]) << 16) |
           (static_cast<uint32_t>(mem[off + 3]) << 24);
  }

  uint32_t expected_rdata(const Req& r) const {
    uint32_t raw = read_word(word_base(r.pa));
    unsigned lane = r.pa & 3;
    uint32_t mask = static_cast<uint32_t>((1ull << (8 * size_bytes(r.size))) - 1ull);
    return (raw >> (8 * lane)) & mask;
  }

  void apply_store(const Req& r) {
    uint32_t data = lane_wdata(r);
    uint64_t off = word_base(r.pa) - RAM_BASE;
    for (int i = 0; i < 4; ++i) {
      if (r.mask & (1u << i))
        mem[off + i] = static_cast<uint8_t>((data >> (8 * i)) & 0xff);
    }
  }

  void tick() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
    dut->clk = 0; dut->eval();
    ++cycles;
  }

  void reset() {
    dut->reset = 1;
    dut->load_valid = 0;
    dut->load_word_addr = 0;
    dut->load_data = 0;
    dut->flush_i = 0;
    dut->resp_delay_i = 0;
    dut->req_valid = 0;
    dut->req_is_store = 0;
    dut->req_va = 0;
    dut->req_pa = 0;
    dut->req_size = 0;
    dut->req_byte_mask = 0;
    dut->req_wdata = 0;
    dut->req_cacheable = 1;
    dut->req_priv = 3;
    dut->req_id = 0;
    dut->req_gen = 0;
    dut->resp_ready = 0;
    tick();
    dut->reset = 0;
    tick();
  }

  void preload() {
    // Explicit simulation image load: fill the RAM with the same independent
    // byte pattern used by the model. This is a testbench-only load port; the
    // RAM is not cleared by reset and has no implicit initial contents.
    dut->load_valid = 1;
    for (int word = 0; word < 128 * 1024 / 4; ++word) {
      const size_t off = static_cast<size_t>(word) * 4;
      uint32_t data = static_cast<uint32_t>(mem[off]) |
                      (static_cast<uint32_t>(mem[off + 1]) << 8) |
                      (static_cast<uint32_t>(mem[off + 2]) << 16) |
                      (static_cast<uint32_t>(mem[off + 3]) << 24);
      dut->load_word_addr = static_cast<uint16_t>(word);
      dut->load_data = data;
      tick();
    }
    dut->load_valid = 0;
    tick();
  }

  void drive(const Req& r) {
    dut->req_valid = 1;
    dut->req_is_store = r.store;
    dut->req_va = r.va;
    dut->req_pa = r.pa;
    dut->req_size = r.size;
    dut->req_byte_mask = r.mask;
    dut->req_wdata = r.wdata;
    dut->req_cacheable = 1;
    dut->req_priv = 3;
    dut->req_id = r.id;
    dut->req_gen = r.gen;
  }

  // Run one transaction. force_error/mismatch are for negative probes.
  Resp transact(Req r, int resp_stall = 0, int delay = 0,
                int req_delay = 0, bool flush_after_accept = false,
                bool force_error = false, bool mismatch = false) {
    ++transactions;
    const bool is_legal = legal(r);
    if (is_legal) ++legal_count; else ++illegal_count;
    uint32_t want_rdata = is_legal && !r.store ? expected_rdata(r) : 0;
    if (mismatch && is_legal && !r.store) want_rdata ^= 1u;
    const uint8_t want_cause = is_legal ? 0 : error_cause(r);

    for (int i = 0; i < req_delay; ++i) {
      dut->req_valid = 0;
      tick();
    }
    drive(r);
    dut->resp_delay_i = static_cast<uint8_t>(delay);
    dut->resp_ready = (resp_stall == 0);
    bool accepted = false;
    bool done = false;
    Resp got;
    int wait = 0;
    while (!done) {
      dut->clk = 0; dut->eval();
      const bool acc = dut->req_valid && dut->req_ready;
      const bool rv = dut->resp_valid;
      const bool rr = dut->resp_ready;
      if (rv) {
        got.valid = true;
        got.error = dut->resp_error;
        got.cause = dut->resp_cause;
        got.id = dut->resp_id;
        got.gen = dut->resp_gen;
        got.rdata = dut->resp_rdata;
      }
      dut->clk = 1; dut->eval();
      if (acc) {
        accepted = true;
        if (is_legal && r.store) apply_store(r);
        dut->req_valid = 0;
        if (flush_after_accept) {
          dut->flush_i = 1;
          tick();
          dut->flush_i = 0;
        }
      }
      if (rv && rr) done = true;
      dut->clk = 0; dut->eval();
      if (!done) {
        if (resp_stall > 0 && rv) --resp_stall;
        dut->resp_ready = (resp_stall == 0);
      }
      if (++wait > 2000) {
        fail("transaction timeout");
        break;
      }
    }
    check(accepted, "request was not accepted");
    check(got.valid, "response missing");

    if (force_error) {
      check(got.error, "negative probe: error bit not set");
      return got;
    }
    if (is_legal) {
      check(!got.error, "legal request returned error");
      if (got.rdata != want_rdata)
        std::fprintf(stderr, "  expect=0x%x got=0x%x pa=0x%llx size=%d\n",
                     want_rdata, got.rdata,
                     static_cast<unsigned long long>(r.pa), r.size);
      check(got.rdata == want_rdata, "read data mismatch", got.rdata);
    } else {
      check(got.error, "illegal request did not return error");
      check(got.cause == want_cause, "illegal request cause mismatch", got.cause);
      check(got.rdata == 0, "illegal request returned data", got.rdata);
    }
    check(got.id == r.id, "response ID mismatch", got.id);
    check(got.gen == r.gen, "response generation mismatch", got.gen);
    return got;
  }

  Req mk(bool store, uint64_t pa, int size, uint8_t mask, uint32_t wdata,
         uint8_t id = 1, uint8_t gen = 1) {
    Req r;
    r.store = store;
    r.va = static_cast<uint32_t>(pa);
    r.pa = pa;
    r.size = size;
    r.mask = mask;
    r.wdata = wdata;
    r.id = id;
    r.gen = gen;
    return r;
  }

  void directed() {
    // First/last byte, all lanes, half positions, word.
    for (int lane = 0; lane < 4; ++lane) {
      transact(mk(true, RAM_BASE + lane, 0, 1u << lane, 0xa0 + lane,
                  2 + lane, 1));
      transact(mk(false, RAM_BASE + lane, 0, 1u << lane, 0, 2 + lane, 1));
    }
    for (int lane : {0, 2}) {
      transact(mk(true, RAM_BASE + lane, 1, 3u << lane, 0x1234, 7, 2));
      transact(mk(false, RAM_BASE + lane, 1, 3u << lane, 0, 7, 2));
    }
    transact(mk(true, RAM_BASE + 4, 2, 0xf, 0x89abcdefu, 8, 3));
    transact(mk(false, RAM_BASE + 4, 2, 0xf, 0, 8, 3));
    transact(mk(true, RAM_END - 1, 0, 0x8, 0x5a, 9, 4));
    transact(mk(false, RAM_END - 1, 0, 0x8, 0, 9, 4));
    transact(mk(true, RAM_END - 4, 2, 0xf, 0x01020304u, 10, 5));
    transact(mk(false, RAM_END - 4, 2, 0xf, 0, 10, 5));

    // Partial write must preserve neighbours.
    transact(mk(true, RAM_BASE + 0x20, 2, 0xf, 0x11223344u, 11, 1));
    transact(mk(true, RAM_BASE + 0x21, 0, 0x2, 0xaa, 12, 1));
    transact(mk(false, RAM_BASE + 0x20, 2, 0xf, 0, 13, 1));

    // Backpressure, delay,
    transact(mk(false, RAM_BASE + 0x30, 2, 0xf, 0, 14, 2), 4, 2);
    transact(mk(true, RAM_BASE + 0x30, 2, 0xf, 0x55667788u, 15, 2), 3, 0);
    transact(mk(false, RAM_BASE + 0x30, 2, 0xf, 0, 16, 2), 2, 3);
    // Request stall.
    transact(mk(false, RAM_BASE + 0x34, 2, 0xf, 0, 17, 3), 0, 0, 3);
    // Accepted load survives an upstream flush.
    transact(mk(false, RAM_BASE + 0x34, 2, 0xf, 0, 18, 3), 2, 0, 0, true);
    // Same address repeated.
    for (int i = 0; i < 3; ++i) {
      transact(mk(false, RAM_BASE + 0x30, 2, 0xf, 0, 19, 4));
      transact(mk(true, RAM_BASE + 0x30, 2, 0xf, 0xa0000000u + i, 20, 4));
    }

    // Illegal address/alignment/mask/data. Memory must not change.
    transact(mk(false, 0x1'80000000ull, 2, 0xf, 0, 21, 1));
    transact(mk(true, 0x1'80000000ull, 2, 0xf, 0x12345678u, 21, 1));
    transact(mk(false, RAM_END, 2, 0xf, 0, 22, 1));
    transact(mk(false, 0x7fffffffull, 2, 0xf, 0, 23, 1));
    transact(mk(true, 0x10000000ull, 2, 0xf, 0x1, 24, 1));
    transact(mk(false, RAM_BASE + 1, 1, 0x6, 0, 25, 1));
    transact(mk(false, RAM_BASE + 2, 2, 0xf, 0, 26, 1));
    transact(mk(true, RAM_BASE, 0, 0x3, 0xaa, 27, 1));
    transact(mk(true, RAM_BASE, 0, 0x1, 0x100, 28, 1));
    transact(mk(false, RAM_BASE, 2, 0xf, 0, 29, 1));
  }

  void random_run(unsigned seed, int count) {
    std::mt19937 rng(seed);
    for (int i = 0; i < count; ++i) {
      const bool store = (rng() & 1) != 0;
      int size = static_cast<int>(rng() % 3);
      uint64_t pa;
      if (rng() % 10 == 0) {
        pa = (rng() & 1) ? (RAM_END + (rng() % 0x100))
                         : (0x10000000ull + (rng() % 0x1000));
      } else {
        pa = RAM_BASE + (rng() % (128 * 1024));
      }
      uint8_t lane = pa & 3;
      uint8_t mask;
      if (size == 0) mask = static_cast<uint8_t>(1u << lane);
      else if (size == 1) mask = static_cast<uint8_t>(3u << lane);
      else mask = 0xf;
      uint32_t wdata;
      if (size == 0) wdata = rng() & 0xff;
      else if (size == 1) wdata = rng() & 0xffff;
      else wdata = rng();
      // Occasionally corrupt mask/data/alignment to exercise errors.
      if (rng() % 13 == 0) mask ^= 0x1;
      if (rng() % 17 == 0) wdata |= 0x80000000u;
      if (rng() % 19 == 0) pa += 1;
      Req r = mk(store, pa, size, mask, wdata,
                 static_cast<uint8_t>(rng() & 0x3f),
                 static_cast<uint8_t>(rng() & 0xff));
      transact(r, static_cast<int>(rng() % 4), static_cast<int>(rng() % 4),
               static_cast<int>(rng() % 3));
    }
  }
};

int main(int argc, char** argv) {
  bool mismatch_probe = false;
  bool hang = false;
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "+mismatch") == 0) mismatch_probe = true;
    if (std::strcmp(argv[i], "+hang") == 0) hang = true;
  }
  Verilated::commandArgs(argc, argv);
  Vram_bridge_tb_top* dut = new Vram_bridge_tb_top;
  Tb tb(dut);
  tb.reset();
  tb.preload();

  if (hang) {
    std::printf("P1-A_RAM_TB_TIMEOUT_PROBE: entering intentional hang\n");
    std::fflush(stdout);
    for (;;) tb.tick();
  }

  tb.directed();
  tb.random_run(0x1a2b3c4du, 450);
  tb.random_run(0x5e6f7a8bu, 450);
  tb.random_run(0x9c0d1e2fu, 450);

  if (tb.transactions < 1000) tb.check(false, "transaction budget too small");
  if (tb.cycles > 200000) tb.check(false, "cycle budget exhausted");

  if (mismatch_probe) {
    Req r = tb.mk(false, RAM_BASE, 2, 0xf, 0, 0x3f, 0x7f);
    tb.transact(r, 0, 0, 0, false, false, true);
    if (tb.errors > 0) {
      std::printf("P1-A_RAM_TB_NEGATIVE_MISMATCH_DETECTED errors=%d\n", tb.errors);
      delete dut;
      return 1;
    }
    std::fprintf(stderr, "P1-A_RAM_TB_NEGATIVE_MISMATCH_NOT_DETECTED\n");
    delete dut;
    return 1;
  }

  if (tb.errors != 0) {
    std::fprintf(stderr, "P1-A_RAM_TB_FAIL errors=%d\n", tb.errors);
    delete dut;
    return 1;
  }
  std::printf("P1-A_RAM_TB_PASS transactions=%llu legal=%llu illegal=%llu cycles=%llu\n",
              static_cast<unsigned long long>(tb.transactions),
              static_cast<unsigned long long>(tb.legal_count),
              static_cast<unsigned long long>(tb.illegal_count),
              static_cast<unsigned long long>(tb.cycles));
  delete dut;
  return 0;
}
