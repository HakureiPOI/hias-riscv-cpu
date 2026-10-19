// P1-A RAM/bridge module test. Independent byte-array memory model.
#include "Vram_bridge_tb_top.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <csignal>
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
  uint64_t accepted_count = 0;
  uint64_t completed_count = 0;
  uint64_t write_events = 0;
  uint64_t expected_writes = 0;
  uint64_t stability_errors = 0;
  uint64_t comparison_errors = 0;
  uint64_t reference_errors = 0;
  bool no_cycle_limit = false;
  struct Expected {
    Req req;
    bool legal;
    uint8_t cause;
    uint32_t rdata;
  };
  std::deque<Expected> pending_resp;

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

  static bool size_valid(int size) { return size >= 0 && size <= 2; }

  static int size_bytes(int size) { return size_valid(size) ? (1 << size) : 0; }

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
    if (!size_valid(r.size)) return false;
    return r.pa >= RAM_BASE && r.pa < RAM_END &&
           (RAM_END - r.pa) >= static_cast<uint64_t>(size_bytes(r.size));
  }

  static bool legal(const Req& r) {
    return size_valid(r.size) && in_range(r) && aligned(r) &&
           mask_ok(r) && wdata_ok(r);
  }

  static uint8_t error_cause(const Req& r) {
    if (!size_valid(r.size) || !in_range(r)) return r.store ? 7 : 5;
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

  void low() {
    dut->clk = 0; dut->eval();
  }

  void edge() {
    dut->clk = 1; dut->eval();
    ++cycles;
    dut->clk = 0; dut->eval();
    if (!no_cycle_limit && cycles > 200000) {
      std::fprintf(stderr, "P1-A_RAM_TB_FAIL: cycle budget exhausted\n");
      std::exit(1);
    }
  }

  void tick() {
    low();
    edge();
  }

  void reset() {
    dut->reset = 1;
    dut->load_valid = 0;
    dut->load_word_addr = 0;
    dut->load_data = 0;
    dut->flush_i = 0;
    dut->resp_delay_i = 0;
    dut->fault_mode = 0;
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

  void note_request(const Req& r) {
    ++transactions;
    if (legal(r)) ++legal_count; else ++illegal_count;
  }

  void note_accept(const Req& r) {
    ++accepted_count;
    const bool is_legal = legal(r);
    if (is_legal && r.store) {
      apply_store(r);
      ++expected_writes;
    }
    Expected e;
    e.req = r;
    e.legal = is_legal;
    e.cause = is_legal ? 0 : error_cause(r);
    e.rdata = (is_legal && !r.store) ? expected_rdata(r) : 0;
    pending_resp.push_back(e);
  }

  void note_complete(const Resp& got) {
    ++completed_count;
    if (pending_resp.empty()) {
      check(false, "response without accepted request");
      return;
    }
    const Expected e = pending_resp.front();
    pending_resp.pop_front();
    if (got.id != e.req.id || got.gen != e.req.gen) ++reference_errors;
    check(got.id == e.req.id && got.gen == e.req.gen,
          "reference queue ID/generation mismatch");
    if (e.legal) {
      if (got.error || got.rdata != e.rdata) ++reference_errors;
      check(!got.error, "reference queue: legal request error");
      check(got.rdata == e.rdata, "reference queue: data mismatch", got.rdata);
    } else {
      if (!got.error || got.cause != e.cause || got.rdata != 0) ++reference_errors;
      check(got.error, "reference queue: illegal request not error");
      check(got.cause == e.cause, "reference queue: cause mismatch", got.cause);
      check(got.rdata == 0, "reference queue: illegal request data");
    }
  }

  void stability_fail(const char* msg) {
    ++stability_errors;
    check(false, msg);
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
    note_request(r);
    const bool is_legal = legal(r);
    uint32_t want_rdata = is_legal && !r.store ? expected_rdata(r) : 0;
    if (mismatch && is_legal && !r.store) want_rdata ^= 1u;
    const uint8_t want_cause = is_legal ? 0 : error_cause(r);

    auto same_resp = [](const Resp& a, const Resp& b) {
      return a.valid == b.valid && a.error == b.error &&
             a.cause == b.cause && a.id == b.id && a.gen == b.gen &&
             a.rdata == b.rdata;
    };
    auto same_req = [](const Req& a, const Req& b) {
      return a.store == b.store && a.pa == b.pa && a.size == b.size &&
             a.mask == b.mask && a.wdata == b.wdata && a.id == b.id &&
             a.gen == b.gen;
    };

    for (int i = 0; i < req_delay; ++i) {
      dut->req_valid = 0;
      tick();
    }
    drive(r);
    dut->resp_delay_i = static_cast<uint8_t>(delay);
    dut->resp_ready = (resp_stall == 0);
    bool accepted = false;
    bool done = false;
    bool held_valid = false;
    bool req_held = false;
    uint8_t held_id = 0, held_gen = 0;
    uint64_t held_pa = 0;
    uint8_t held_size = 0, held_mask = 0;
    uint32_t held_wdata = 0;
    Resp held;
    Resp got;
    int wait = 0;
    while (!done) {
      low();
      const bool acc = dut->req_valid && dut->req_ready;
      const bool rv = dut->resp_valid;
      const bool rr = dut->resp_ready;
      if (dut->req_valid && !dut->req_ready) {
        if (!req_held) {
          req_held = true;
          held_id = dut->req_id; held_gen = dut->req_gen;
          held_pa = dut->req_pa; held_size = dut->req_size;
          held_mask = dut->req_byte_mask; held_wdata = dut->req_wdata;
        } else if (dut->req_id != held_id || dut->req_gen != held_gen ||
                   dut->req_pa != held_pa || dut->req_size != held_size ||
                   dut->req_byte_mask != held_mask ||
                   dut->req_wdata != held_wdata) {
          stability_fail("request payload changed while stalled");
        }
      } else if (req_held) {
        // The final handshake cycle must also preserve the stalled payload.
        if (!dut->req_valid) {
          stability_fail("request valid dropped before final handshake");
        } else if (dut->req_id != held_id || dut->req_gen != held_gen ||
                   dut->req_pa != held_pa || dut->req_size != held_size ||
                   dut->req_byte_mask != held_mask ||
                   dut->req_wdata != held_wdata) {
          stability_fail("request payload changed at final handshake");
        }
        req_held = false;
      }
      if (rv) {
        Resp cur;
        cur.valid = true;
        cur.error = dut->resp_error;
        cur.cause = dut->resp_cause;
        cur.id = dut->resp_id;
        cur.gen = dut->resp_gen;
        cur.rdata = dut->resp_rdata;
        if (held_valid && !same_resp(held, cur)) {
          stability_fail("held response changed at final handshake");
        }
        if (!rr) {
          if (!held_valid) {
            held = cur;
            held_valid = true;
          }
        } else {
          got = cur;
          held_valid = false;
        }
      } else if (held_valid) {
        stability_fail("response valid dropped before handshake");
      }
      if (dut->ram_write_o) ++write_events;
      if (dut->ram_write_o && !(is_legal && r.store))
        check(false, "illegal request produced a RAM write");
      edge();
      if (acc) {
        accepted = true;
        note_accept(r);
        dut->req_valid = 0;
        if (flush_after_accept) {
          dut->flush_i = 1;
          tick();
          dut->flush_i = 0;
        }
      }
      if (rv && rr) {
        done = true;
        note_complete(got);
      }
      if (!done) {
        if (resp_stall > 0 && rv) --resp_stall;
        dut->resp_ready = (resp_stall == 0);
      }
      if (++wait > 2000) {
        fail("transaction timeout");
        break;
      }
    }
    // Idle observation: no stray or duplicate response may survive the
    // handshake. This also catches a second response for the same request.
    dut->req_valid = 0;
    dut->resp_ready = 1;
    for (int i = 0; i < 2; ++i) {
      low();
      if (dut->resp_valid) check(false, "stray/duplicate response in idle window");
      edge();
    }
    check(accepted, "request was not accepted");
    check(got.valid, "response missing");

    if (force_error) {
      check(got.error, "negative probe: error bit not set");
      return got;
    }
    if (is_legal) {
      check(!got.error, "legal request returned error");
      if (!r.store && got.rdata != want_rdata)
        ++comparison_errors;
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
    if (id > 0x3f) check(false, "request ID exceeds 6 bits");
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

    // Accepted Store + upstream Flush: the write must survive and respond once.
    transact(mk(true, RAM_BASE + 0x60, 2, 0xf, 0x13579bdfu, 48, 1),
             2, 0, 0, true);
    transact(mk(false, RAM_BASE + 0x60, 2, 0xf, 0, 49, 1), 0, 0, 0, false);

    // Top-of-34-bit PA must not wrap into the RAM tail. The model must not
    // replicate RTL overflow; these are access faults and must not write.
    const uint32_t tail_before = read_word(RAM_END - 4);
    transact(mk(false, 0x3ffffffffull, 0, 0x8, 0, 40, 1));
    transact(mk(false, 0x3fffffffeull, 1, 0xC, 0, 41, 1));
    transact(mk(false, 0x3fffffffcull, 2, 0xF, 0, 42, 1));
    transact(mk(true, 0x3ffffffffull, 0, 0x8, 0x5a, 43, 1));
    transact(mk(true, 0x3fffffffeull, 1, 0xC, 0x1234, 44, 1));
    transact(mk(true, 0x3fffffffcull, 2, 0xF, 0xdeadbeefu, 45, 1));
    // size=3 is an interface-illegal request: access fault, not misaligned.
    transact(mk(false, RAM_BASE, 3, 0xf, 0, 46, 1));
    transact(mk(true, RAM_BASE, 3, 0xf, 0, 47, 1));
    check(read_word(RAM_END - 4) == tail_before,
          "top-PA/size3 illegal requests changed RAM tail");
    dut_readback(RAM_END - 4, "tail_after_illegal", 0x30);
    dut_readback(RAM_END - 8, "guard_after_illegal", 0x31);

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

  void dut_readback(uint64_t pa, const char* name, uint8_t id) {
    Req r = mk(false, pa, 2, 0xf, 0, id, 0x33);
    const uint32_t want = expected_rdata(r);
    Resp got = transact(r, 0, 0, 0, false, false, false);
    const bool ok = !got.error && got.rdata == want;
    std::printf("P1-A_RAM_DUT_READBACK %s pa=0x%llx got=0x%08x expected=0x%08x result=%s\n",
                name, static_cast<unsigned long long>(pa), got.rdata, want,
                ok ? "PASS" : "FAIL");
    if (!ok) check(false, "DUT physical readback mismatch");
  }

  void pipeline_stall() {
    // A response is held (resp_ready=0); a second request is presented and
    // must remain stable while req_ready=0. Consuming A and accepting B happen
    // at the same edge. Both responses are checked against the model.
    Req a = mk(false, RAM_BASE + 0x70, 2, 0xf, 0, 60, 1);
    Req b = mk(false, RAM_BASE + 0x74, 2, 0xf, 0, 61, 2);
    note_request(a);
    note_request(b);
    const uint32_t want_a = expected_rdata(a);
    const uint32_t want_b = expected_rdata(b);
    auto load_resp = [&](Resp& r) {
      r.valid = true; r.error = dut->resp_error; r.cause = dut->resp_cause;
      r.id = dut->resp_id; r.gen = dut->resp_gen; r.rdata = dut->resp_rdata;
    };

    drive(a);
    dut->resp_ready = 0;
    low();
    check(dut->req_ready, "pipeline: A not accepted");
    edge();
    note_accept(a);
    dut->req_valid = 0;

    int guard = 0;
    while (!dut->resp_valid && guard++ < 200) { low(); edge(); }
    check(dut->resp_valid, "pipeline: A response missing");
    Resp held_a;
    load_resp(held_a);
    if (held_a.rdata != want_a) check(false, "pipeline: A data mismatch", held_a.rdata);

    drive(b);
    dut->req_valid = 1;
    for (int i = 0; i < 3; ++i) {
      low();
      check(!dut->req_ready, "pipeline: B accepted while A response held");
      check(dut->resp_valid && dut->resp_rdata == held_a.rdata,
            "pipeline: A response changed");
      if (i > 0) {
        check(dut->req_id == b.id && dut->req_gen == b.gen &&
              dut->req_pa == b.pa && dut->req_size == b.size &&
              dut->req_byte_mask == b.mask && dut->req_wdata == b.wdata,
              "pipeline: B payload changed while stalled");
      }
      edge();
    }

    dut->resp_ready = 1;
    low();
    check(dut->req_valid && dut->req_ready, "pipeline: B not ready at consume edge");
    check(dut->resp_valid && dut->resp_rdata == held_a.rdata,
          "pipeline: A payload changed at final handshake");
    check(dut->req_id == b.id && dut->req_gen == b.gen &&
          dut->req_pa == b.pa && dut->req_size == b.size &&
          dut->req_byte_mask == b.mask && dut->req_wdata == b.wdata,
          "pipeline: B payload changed at final handshake");
    edge();
    note_accept(b);
    note_complete(held_a);  // A response handshake at this edge
    dut->req_valid = 0;
    if (held_a.id != a.id || held_a.gen != a.gen) check(false, "pipeline: A ID/gen");

    guard = 0;
    while (!dut->resp_valid && guard++ < 200) { low(); edge(); }
    low();
    check(dut->resp_valid, "pipeline: B response missing");
    check(dut->resp_rdata == want_b, "pipeline: B data mismatch", dut->resp_rdata);
    check(dut->resp_id == b.id && dut->resp_gen == b.gen,
          "pipeline: B ID/gen mismatch");
    Resp got_b;
    got_b.valid = true; got_b.error = dut->resp_error; got_b.cause = dut->resp_cause;
    got_b.id = dut->resp_id; got_b.gen = dut->resp_gen; got_b.rdata = dut->resp_rdata;
    note_complete(got_b);  // B response handshake
    edge();
    dut->resp_ready = 1;
    // Same idle observation as the serial path.
    dut->req_valid = 0;
    for (int i = 0; i < 2; ++i) {
      low();
      if (dut->resp_valid) check(false, "pipeline: stray/duplicate response");
      edge();
    }
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
  bool hang_ignore_term = false;
  bool mismatch_hang = false;
  bool stability_probe = false;
  bool final_handshake_probe = false;
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "+mismatch") == 0) mismatch_probe = true;
    if (std::strcmp(argv[i], "+hang") == 0) hang = true;
    if (std::strcmp(argv[i], "+hang_ignore_term") == 0) hang_ignore_term = true;
    if (std::strcmp(argv[i], "+mismatch_hang") == 0) mismatch_hang = true;
    if (std::strcmp(argv[i], "+stability_probe") == 0) stability_probe = true;
    if (std::strcmp(argv[i], "+final_handshake_probe") == 0) final_handshake_probe = true;
  }
  Verilated::commandArgs(argc, argv);
  Vram_bridge_tb_top* dut = new Vram_bridge_tb_top;
  Tb tb(dut);
  tb.reset();
  tb.preload();

  if (hang_ignore_term) {
    std::signal(SIGTERM, SIG_IGN);
    tb.no_cycle_limit = true;
    std::printf("P1-A_RAM_TB_TIMEOUT_IGNORE_TERM_PROBE: entering intentional hang\n");
    std::fflush(stdout);
    for (;;) tb.tick();
  }
  if (hang) {
    tb.no_cycle_limit = true;
    std::printf("P1-A_RAM_TB_TIMEOUT_PROBE: entering intentional hang\n");
    std::fflush(stdout);
    for (;;) tb.tick();
  }
  if (mismatch_hang) {
    // Exercise the comparison path first, then hang in the same entry.
    Req r = tb.mk(false, RAM_BASE, 2, 0xf, 0, 0x22, 0x12);
    tb.transact(r, 0, 0, 0, false, false, true);
    std::printf("P1-A_RAM_TB_NEGATIVE_MISMATCH_DETECTED\n");
    tb.no_cycle_limit = true;
    std::printf("P1-A_RAM_TB_MISMATCH_HANG_PROBE: entering comparison-path hang\n");
    std::fflush(stdout);
    for (;;) tb.tick();
  }
  if (stability_probe) {
    Req r = tb.mk(false, RAM_BASE + 0x80, 2, 0xf, 0, 0x12, 0x11);
    tb.transact(r, 3, 0);  // normal control
    if (tb.errors != 0) {
      std::fprintf(stderr, "P1-A_RAM_TB_STABILITY_CONTROL_FAIL errors=%llu\n",
                   static_cast<unsigned long long>(tb.errors));
      delete dut;
      return 1;
    }
    dut->fault_mode = 1;
    tb.transact(r, 3, 0);
    if (tb.stability_errors > 0 && tb.errors == tb.stability_errors) {
      std::printf("P1-A_RAM_TB_STABILITY_DETECTED stability_errors=%llu\n",
                  static_cast<unsigned long long>(tb.stability_errors));
      delete dut;
      return 1;
    }
    std::fprintf(stderr, "P1-A_RAM_TB_STABILITY_NOT_DETECTED errors=%llu stability=%llu\n",
                 static_cast<unsigned long long>(tb.errors),
                 static_cast<unsigned long long>(tb.stability_errors));
    delete dut;
    return 1;
  }
  if (final_handshake_probe) {
    dut->fault_mode = 2;
    Req r = tb.mk(false, RAM_BASE + 0x84, 2, 0xf, 0, 0x13, 0x11);
    tb.transact(r, 3, 0);
    if (tb.stability_errors > 0 &&
        tb.errors == tb.stability_errors + tb.comparison_errors +
                     tb.reference_errors) {
      std::printf("P1-A_RAM_TB_FINAL_HANDSHAKE_DETECTED stability_errors=%llu comparison_errors=%llu\n",
                  static_cast<unsigned long long>(tb.stability_errors),
                  static_cast<unsigned long long>(tb.comparison_errors));
      delete dut;
      return 1;
    }
    std::fprintf(stderr, "P1-A_RAM_TB_FINAL_HANDSHAKE_NOT_DETECTED errors=%llu stability=%llu comparison=%llu reference=%llu\n",
                 static_cast<unsigned long long>(tb.errors),
                 static_cast<unsigned long long>(tb.stability_errors),
                 static_cast<unsigned long long>(tb.comparison_errors),
                 static_cast<unsigned long long>(tb.reference_errors));
    delete dut;
    return 1;
  }

  tb.directed();
  tb.pipeline_stall();
  tb.random_run(0x1a2b3c4du, 450);
  tb.random_run(0x5e6f7a8bu, 450);
  tb.random_run(0x9c0d1e2fu, 450);

  if (tb.transactions < 1000) tb.check(false, "transaction budget too small");
  if (tb.cycles > 200000) tb.check(false, "cycle budget exhausted");

  if (tb.accepted_count != tb.completed_count)
    tb.check(false, "accepted/completed count mismatch");
  if (tb.legal_count + tb.illegal_count != tb.transactions)
    tb.check(false, "transaction classification count mismatch");
  if (tb.write_events != tb.expected_writes)
    tb.check(false, "RAM write event count mismatch");
  if (!tb.pending_resp.empty())
    tb.check(false, "reference response queue not empty");

  if (mismatch_probe) {
    Req r = tb.mk(false, RAM_BASE, 2, 0xf, 0, 0x3f, 0x7f);
    tb.transact(r, 0, 0, 0, false, false, true);
    if (tb.comparison_errors > 0 && tb.errors == tb.comparison_errors) {
      std::printf("P1-A_RAM_TB_NEGATIVE_MISMATCH_DETECTED comparison_errors=%llu\n",
                  static_cast<unsigned long long>(tb.comparison_errors));
      delete dut;
      return 1;
    }
    std::fprintf(stderr,
                 "P1-A_RAM_TB_NEGATIVE_MISMATCH_NOT_DETECTED errors=%llu comparison=%llu\n",
                 static_cast<unsigned long long>(tb.errors),
                 static_cast<unsigned long long>(tb.comparison_errors));
    delete dut;
    return 1;
  }

  if (tb.errors != 0) {
    std::fprintf(stderr, "P1-A_RAM_TB_FAIL errors=%d\n", tb.errors);
    delete dut;
    return 1;
  }
  std::printf("P1-A_RAM_TB_PASS transactions=%llu legal=%llu illegal=%llu "
              "accepted=%llu completed=%llu writes=%llu expected_writes=%llu cycles=%llu\n",
              static_cast<unsigned long long>(tb.transactions),
              static_cast<unsigned long long>(tb.legal_count),
              static_cast<unsigned long long>(tb.illegal_count),
              static_cast<unsigned long long>(tb.accepted_count),
              static_cast<unsigned long long>(tb.completed_count),
              static_cast<unsigned long long>(tb.write_events),
              static_cast<unsigned long long>(tb.expected_writes),
              static_cast<unsigned long long>(tb.cycles));
  delete dut;
  return 0;
}
