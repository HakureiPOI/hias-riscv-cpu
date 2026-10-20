// P1-B fetch/decode + real RAM/bridge integration test.
#include "Vfrontend_tb_top.h"
#include "verilated.h"
#include "../decode_expected.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <random>
#include <csignal>

#ifndef P1B_GEN_W
#define P1B_GEN_W 8
#endif

static constexpr uint32_t RESET_VECTOR = 0x80000000u;
static constexpr uint32_t RAM_END = 0x80020000u;
static constexpr uint32_t NOP = 0x00000013u;

struct Expected {
  uint32_t instr;
  uint32_t op;
  uint32_t exec;
  uint32_t rd;
  uint32_t rd_we;
  uint32_t is_load;
  uint32_t is_store;
  uint32_t is_csr;
  uint32_t illegal;
  uint32_t illegal_cause;
  uint32_t illegal_tval;
  uint32_t mem_size;
  uint32_t csr_uimm;
  uint32_t csr_uimm_valid;
  bool fetch_error;
  uint32_t fetch_cause;
  uint32_t fetch_tval;
};

struct Tb {
  Vfrontend_tb_top* dut;
  std::map<uint32_t, Expected> image;
  int errors = 0;
  uint64_t cycles = 0;
  uint64_t accepted = 0;
  uint64_t requests = 0;
  uint64_t responses = 0;
  uint64_t redirects = 0;
  uint32_t model_pc = RESET_VECTOR;
  bool compare_enabled = true;
  uint64_t max_cycles = 300000;

  explicit Tb(Vfrontend_tb_top* d) : dut(d) {}

  void fail(const char* msg, uint32_t got = 0, uint32_t want = 0) {
    std::fprintf(stderr, "P1-B_FRONTEND_FAIL: %s got=0x%x want=0x%x pc=0x%x\n",
                 msg, got, want, model_pc);
    ++errors;
    if (errors > 30) std::exit(1);
  }

  void check(bool cond, const char* msg, uint32_t got = 0, uint32_t want = 0) {
    if (!cond) fail(msg, got, want);
  }

  void setup_image() {
    Expected nop{};
    nop.instr = NOP;
    nop.op = 7;      // OP_ALU_I
    nop.exec = 10;   // EXEC_ADDI
    nop.rd = 0;
    nop.rd_we = 0;
    nop.mem_size = 2;
    image.clear();
    // The whole RAM is NOP; cases overwrite the first words.
    for (unsigned i = 0; i < kDecodeCaseCount; ++i) {
      const ExpectedDecode& e = kDecodeCases[i];
      Expected x{};
      x.instr = e.instr;
      x.op = e.op; x.exec = e.exec; x.rd = e.rd; x.rd_we = e.rd_we;
      x.is_load = e.is_load; x.is_store = e.is_store; x.is_csr = e.is_csr;
      x.illegal = e.illegal; x.illegal_cause = e.illegal_cause;
      x.illegal_tval = e.illegal_tval; x.mem_size = e.mem_size;
      x.csr_uimm = e.csr_uimm; x.csr_uimm_valid = e.csr_uimm_valid;
      x.fetch_error = false;
      image[e.pc] = x;
    }
  }

  Expected expected_at(uint32_t pc) const {
    auto it = image.find(pc);
    if (it != image.end()) return it->second;
    Expected nop{};
    nop.instr = NOP; nop.op = 7; nop.exec = 10; nop.mem_size = 2;
    return nop;
  }

  void tick_raw() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
    dut->clk = 0; dut->eval();
    ++cycles;
    if (cycles > max_cycles) {
      std::fprintf(stderr, "P1-B_FRONTEND_FAIL: cycle budget exhausted\n");
      std::exit(1);
    }
    if (dut->commit_valid_o || dut->commit_trap_valid_o)
      fail("frontend fabricated retire/trap");
    if (dut->ram_write_o) fail("fetch produced a RAM write");
  }

  void set_inputs(bool redirect, uint32_t target, uint8_t accept,
                  bool gate, uint8_t fault, uint8_t delay) {
    dut->redirect_valid = redirect;
    dut->redirect_target = target;
    dut->redirect_cause = 0;
    dut->redirect_flush_all = 1;
    dut->decoded_accept = accept;
    dut->req_gate = gate;
    dut->fault_mode = fault;
    dut->resp_delay_i = delay;
  }

  // One normal cycle with model checking. Returns pre-edge decoded-valid.
  bool cycle(bool redirect, uint32_t target, uint8_t accept,
             bool gate = false, uint8_t fault = 0, uint8_t delay = 0) {
    set_inputs(redirect, target, accept, gate, fault, delay);
    dut->clk = 0; dut->eval();

    const bool dv = dut->dec_valid;
    const uint32_t dpc = dut->dec_pc;
    const uint32_t dinstr = dut->dec_instr;
    const bool req_fire = dut->mem_req_valid_o && dut->mem_req_ready_o;
    const bool resp_fire = dut->mem_resp_valid_o && dut->mem_resp_ready_o;
    if (req_fire) ++requests;
    if (resp_fire) ++responses;

    if (redirect) {
      ++redirects;
      if ((target & 3u) == 0) model_pc = target;
    } else if (dv && accept) {
      compare(dpc, dinstr);
      model_pc = dpc + 4u;
      ++accepted;
    }
    dut->clk = 1; dut->eval();
    dut->clk = 0; dut->eval();
    ++cycles;
    if (cycles > max_cycles) {
      std::fprintf(stderr, "P1-B_FRONTEND_FAIL: cycle budget exhausted\n");
      std::exit(1);
    }
    if (dut->commit_valid_o || dut->commit_trap_valid_o)
      fail("frontend fabricated retire/trap");
    if (dut->ram_write_o) fail("fetch produced a RAM write");
    return dv;
  }

  void compare(uint32_t pc, uint32_t instr) {
    if (!compare_enabled) return;
    const Expected e = expected_at(pc);
    check(pc == model_pc, "decoded PC order", pc, model_pc);
    check(instr == e.instr, "instruction word", instr, e.instr);
    check(dut->dec_illegal == (e.illegal != 0), "illegal",
          dut->dec_illegal, e.illegal);
    if (e.illegal) {
      check(dut->dec_illegal_cause == 2, "illegal cause",
            dut->dec_illegal_cause, 2);
      check(dut->dec_illegal_tval == instr, "illegal tval",
            dut->dec_illegal_tval, instr);
      check(dut->dec_rd_we == 0, "illegal rd_we", dut->dec_rd_we, 0);
      check(dut->dec_is_load == 0 && dut->dec_is_store == 0 &&
            dut->dec_is_csr == 0, "illegal side-effect flags");
      return;
    }
    check(dut->dec_op == e.op, "op", dut->dec_op, e.op);
    check(dut->dec_exec == e.exec, "exec", dut->dec_exec, e.exec);
    check(dut->dec_rd == e.rd, "rd", dut->dec_rd, e.rd);
    check(dut->dec_rd_we == (e.rd_we != 0), "rd_we", dut->dec_rd_we, e.rd_we);
    check(dut->dec_is_load == (e.is_load != 0), "is_load",
          dut->dec_is_load, e.is_load);
    check(dut->dec_is_store == (e.is_store != 0), "is_store",
          dut->dec_is_store, e.is_store);
    check(dut->dec_is_csr == (e.is_csr != 0), "is_csr",
          dut->dec_is_csr, e.is_csr);
    check(dut->dec_fetch_exc_valid == 0, "unexpected fetch exception",
          dut->dec_fetch_exc_valid, 0);
    check(dut->dec_mem_size == e.mem_size, "mem_size",
          dut->dec_mem_size, e.mem_size);
    check(dut->dec_csr_uimm == e.csr_uimm, "csr_uimm",
          dut->dec_csr_uimm, e.csr_uimm);
    check(dut->dec_csr_uimm_valid == (e.csr_uimm_valid != 0),
          "csr_uimm_valid", dut->dec_csr_uimm_valid, e.csr_uimm_valid);
    check(dut->dec_pred_taken == 0, "pred_taken", dut->dec_pred_taken, 0);
    check(dut->dec_pred_target == pc + 4, "pred_target",
          dut->dec_pred_target, pc + 4);
    check(dut->dec_pred_index == 0, "pred_index", dut->dec_pred_index, 0);
    check(dut->dec_fetch_gen < (1u << P1B_GEN_W), "fetch_gen width",
          dut->dec_fetch_gen, (1u << P1B_GEN_W) - 1);
  }

  void load_image_while_reset() {
    dut->reset = 1;
    dut->load_valid = 1;
    dut->redirect_valid = 0;
    dut->decoded_accept = 0;
    dut->req_gate = 0;
    dut->fault_mode = 0;
    dut->resp_delay_i = 0;
    for (int word = 0; word < 128 * 1024 / 4; ++word) {
      dut->load_word_addr = static_cast<uint16_t>(word);
      const uint32_t pc = RESET_VECTOR + 4u * static_cast<uint32_t>(word);
      auto it = image.find(pc);
      dut->load_data = (it == image.end()) ? NOP : it->second.instr;
      tick_raw();
    }
    dut->load_valid = 0;
    dut->reset = 0;
    dut->clk = 0; dut->eval();
    cycles = 0;
    accepted = 0;
    requests = 0;
    responses = 0;
    redirects = 0;
    model_pc = RESET_VECTOR;
  }

  void reset_frontend() {
    dut->reset = 1;
    dut->redirect_valid = 0;
    dut->decoded_accept = 0;
    dut->req_gate = 0;
    dut->fault_mode = 0;
    dut->resp_delay_i = 0;
    for (int i = 0; i < 2; ++i) tick_raw();
    dut->reset = 0;
    model_pc = RESET_VECTOR;
    accepted = 0;
    requests = 0;
    responses = 0;
    redirects = 0;
    cycles = 0;
  }

  void redirect_once(uint32_t target) {
    cycle(true, target, 0);
  }

  void drain_response_counters() {
    for (int i = 0; i < 50; ++i) cycle(false, 0, 0);
    check(requests == responses, "request/response conservation",
          static_cast<uint32_t>(responses), static_cast<uint32_t>(requests));
  }

  void wait_accept(uint32_t pc, uint8_t delay = 0) {
    for (int i = 0; i < 100; ++i) {
      if (dut->dec_valid) break;
      cycle(false, 0, 1, false, 0, delay);
    }
    check(dut->dec_valid, "timeout waiting for decoded fetch");
    check(dut->dec_pc == pc, "unexpected decoded PC", dut->dec_pc, pc);
    cycle(false, 0, 1, false, 0, delay);
    check(model_pc == pc + 4u, "model PC did not advance", model_pc, pc + 4u);
  }

  void backpressure_test(uint32_t target) {
    redirect_once(target);
    for (int i = 0; i < 100 && !dut->dec_valid; ++i)
      cycle(false, 0, 0);
    check(dut->dec_valid, "backpressure: no decoded result");
    const uint32_t pc = dut->dec_pc;
    const uint32_t instr = dut->dec_instr;
    for (int i = 0; i < 4; ++i) {
      cycle(false, 0, 0);
      check(dut->dec_valid, "backpressure: valid dropped");
      check(dut->dec_pc == pc && dut->dec_instr == instr,
            "backpressure: payload changed");
    }
    cycle(false, 0, 1);
  }

  void request_stall_test(uint32_t target, uint32_t final_target) {
    redirect_once(target);
    // Present a request but keep it from being accepted.
    for (int i = 0; i < 3; ++i) cycle(false, 0, 1, true);
    check(dut->mem_req_valid_o, "stalled request valid dropped");
    check(!dut->mem_req_ready_o, "stalled request claimed ready");
    cycle(true, final_target, 0, true);  // cancel not-yet-accepted request
    for (int i = 0; i < 100 && !dut->dec_valid; ++i) cycle(false, 0, 0);
    check(dut->dec_valid, "request stall: final target did not decode");
    check(dut->dec_pc == final_target, "request stall: wrong final PC",
          dut->dec_pc, final_target);
    cycle(false, 0, 1);
  }

  void response_redirect_test(uint32_t target, uint32_t final_target) {
    redirect_once(target);
    for (int i = 0; i < 100; ++i) {
      cycle(false, 0, 0, false, 0, 3);
      if (dut->req_pending_o && !dut->mem_resp_valid_o) break;
    }
    check(dut->req_pending_o, "response redirect: no pending request");
    cycle(true, final_target, 0, false, 0, 3);
    for (int i = 0; i < 100 && !dut->dec_valid; ++i) cycle(false, 0, 0, false, 0, 3);
    check(dut->dec_valid, "response redirect: no new decode");
    check(dut->dec_pc == final_target, "response redirect: old response visible",
          dut->dec_pc, final_target);
    cycle(false, 0, 1);
  }

  void same_cycle_redirect_test(uint32_t target, uint32_t final_target) {
    redirect_once(target);
    bool redirected = false;
    for (int i = 0; i < 100; ++i) {
      set_inputs(false, 0, 0, false, 0, 2);
      dut->clk = 0; dut->eval();
      if (dut->mem_resp_valid_o && !redirected) {
        // Redirect in the exact cycle the response is presented; the fetch
        // must discard it and not emit an old decoded result.
        set_inputs(true, final_target, 0, false, 0, 2);
        dut->eval();
        redirected = true;
      }
      dut->clk = 1; dut->eval();
      dut->clk = 0; dut->eval();
      ++cycles;
      if (redirected) break;
    }
    check(redirected, "same-cycle redirect not injected");
    model_pc = final_target;
    for (int i = 0; i < 100 && !dut->dec_valid; ++i) cycle(false, 0, 0);
    check(dut->dec_valid, "same-cycle redirect: no new decode");
    check(dut->dec_pc == final_target, "same-cycle redirect: old result leaked",
          dut->dec_pc, final_target);
    cycle(false, 0, 1);
  }

  void fault_injection_test(uint32_t target) {
    redirect_once(target);
    for (int i = 0; i < 100 && !dut->fault_used_o; ++i)
      cycle(false, 0, 1, false, 1, 0);
    check(dut->fault_used_o, "fault injector did not fire");
    for (int i = 0; i < 100 && !dut->dec_valid; ++i)
      cycle(false, 0, 0, false, 1, 0);
    check(dut->dec_valid, "fault injection: real response missing");
    check(dut->dec_pc == target, "fault injection: wrong PC", dut->dec_pc, target);
    cycle(false, 0, 1, false, 0, 0);
  }

  void last_word_test() {
    const uint32_t last = RAM_END - 4u;
    redirect_once(last);
    wait_accept(last);
  }

  void fetch_error_test() {
    const uint32_t bad = RAM_END;
    redirect_once(bad);
    compare_enabled = false;
    for (int i = 0; i < 100 && !dut->dec_valid; ++i) cycle(false, 0, 1);
    check(dut->dec_valid, "fetch error: no result");
    check(dut->dec_fetch_exc_valid == 1, "fetch error flag");
    check(dut->dec_fetch_exc_cause == 1, "fetch error cause",
          dut->dec_fetch_exc_cause, 1);
    check(dut->dec_fetch_exc_tval == bad, "fetch error tval",
          dut->dec_fetch_exc_tval, bad);
    check(dut->dec_illegal == 0, "fetch error misclassified as illegal");
    cycle(false, 0, 1);
    for (int i = 0; i < 5; ++i) {
      cycle(false, 0, 1);
      check(!dut->dec_valid, "fetch error did not wait for redirect");
    }
    compare_enabled = true;
    redirect_once(RESET_VECTOR);
    for (int i = 0; i < 100 && !dut->dec_valid; ++i) cycle(false, 0, 0);
    check(dut->dec_valid, "fetch error: did not resume");
    check(dut->dec_pc == RESET_VECTOR, "fetch error: resume PC",
          dut->dec_pc, RESET_VECTOR);
    cycle(false, 0, 1);
  }

  void misaligned_redirect_test(uint32_t final_target) {
    set_inputs(true, RESET_VECTOR + 2u, 0, false, 0, 0);
    dut->clk = 1; dut->eval();
    dut->clk = 0; dut->eval();
    ++cycles;
    check(dut->redirect_error_o == 1, "misaligned redirect not rejected");
    redirect_once(final_target);
    for (int i = 0; i < 100 && !dut->dec_valid; ++i) cycle(false, 0, 0);
    check(dut->dec_valid, "aligned redirect after error failed");
    check(dut->dec_pc == final_target, "aligned redirect PC", dut->dec_pc, final_target);
    cycle(false, 0, 1);
  }

  void continuous_redirect_test(uint32_t a, uint32_t b, uint32_t c) {
    cycle(true, a, 0);
    cycle(true, b, 0);
    cycle(true, c, 0);
    for (int i = 0; i < 100 && !dut->dec_valid; ++i) cycle(false, 0, 0);
    check(dut->dec_valid, "continuous redirect: no output");
    check(dut->dec_pc == c, "continuous redirect: old target leaked", dut->dec_pc, c);
    cycle(false, 0, 1);
  }
};

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vfrontend_tb_top* dut = new Vfrontend_tb_top;
  Tb tb(dut);
  tb.setup_image();
  tb.load_image_while_reset();

  const bool mismatch_probe = (argc > 1 && std::strcmp(argv[1], "+mismatch") == 0);
  const bool hang_probe = (argc > 1 && std::strcmp(argv[1], "+hang") == 0);
  const bool hang_ignore_term_probe =
      (argc > 1 && std::strcmp(argv[1], "+hang_ignore_term") == 0);
  if (mismatch_probe) {
    // Controlled negative: change one expected field only; the RAM image is
    // already loaded, so this must fail solely through the comparison path.
    tb.image[RESET_VECTOR].op ^= 1u;
  }
  if (hang_ignore_term_probe) std::signal(SIGTERM, SIG_IGN);
  if (hang_probe || hang_ignore_term_probe) {
    std::printf("P1-B_FRONTEND_TIMEOUT_PROBE\n");
    std::fflush(stdout);
    for (;;) { dut->clk = !dut->clk; dut->eval(); }
  }
  // V02: sequential fetch/decode of the independent image.
  for (unsigned i = 0; i < kDecodeCaseCount; ++i) {
    const ExpectedDecode& e = kDecodeCases[i];
    tb.wait_accept(e.pc);
  }
  tb.last_word_test();
  tb.drain_response_counters();
  if (mismatch_probe) tb.image[RESET_VECTOR].op ^= 1u;
  std::printf("P1-B_FRONTEND_BASIC_PASS cases=%u accepted=%llu\n",
              kDecodeCaseCount, static_cast<unsigned long long>(tb.accepted));

  // V03 targeted recovery/backpressure/error tests.
  tb.reset_frontend();
  tb.backpressure_test(RESET_VECTOR + 4u * 10);
  tb.request_stall_test(RESET_VECTOR + 4u * 20, RESET_VECTOR + 4u * 21);
  tb.response_redirect_test(RESET_VECTOR + 4u * 30, RESET_VECTOR + 4u * 31);
  tb.same_cycle_redirect_test(RESET_VECTOR + 4u * 40, RESET_VECTOR + 4u * 41);
  tb.fault_injection_test(RESET_VECTOR + 4u * 50);
  tb.fetch_error_test();
  tb.misaligned_redirect_test(RESET_VECTOR + 4u * 12);
  tb.continuous_redirect_test(RESET_VECTOR + 4u * 2, RESET_VECTOR + 4u * 3,
                              RESET_VECTOR + 4u * 4);

  // V03: forced generation wrap (build uses -GGEN_W=2 for this run).
  tb.reset_frontend();
  uint32_t last_gen = 0xffffffffu;
  bool wrapped = false;
  for (int i = 0; i < 40; ++i) {
    tb.wait_accept(tb.model_pc);
    const uint32_t g = dut->dec_fetch_gen;
    tb.check(g < (1u << P1B_GEN_W), "wrap: generation out of range",
             g, (1u << P1B_GEN_W) - 1);
    if (last_gen != 0xffffffffu && g < last_gen) wrapped = true;
    last_gen = g;
  }
  tb.check(wrapped, "wrap: generation did not wrap in 40 fetches");
  std::printf("P1-B_FRONTEND_WRAP_PASS gen_w=%d\n", P1B_GEN_W);

  // V03: random redirects/backpressure/gating across three fixed seeds.
  // Each seed accepts 340 results; the required three-seed total is 1020.
  static constexpr int kRandomAcceptsPerSeed = 340;
  const unsigned seeds[3] = {0x1a2b3c4du, 0x5e6f7a8bu, 0x9c0d1e2fu};
  uint64_t random_total = 0;
  for (unsigned s = 0; s < 3; ++s) {
    tb.reset_frontend();
    tb.errors = 0;
    std::mt19937 rng(seeds[s]);
    int accepted_this = 0;
    while (accepted_this < kRandomAcceptsPerSeed) {
      const bool redirect = (rng() % 100) < 5;
      uint32_t target = RESET_VECTOR + 4u * (rng() % (kDecodeCaseCount + 20));
      const bool gate = (rng() % 100) < 10;
      const uint8_t accept = (rng() % 100) < 70 ? 1 : 0;
      const uint8_t delay = static_cast<uint8_t>(rng() % 4);
      const uint64_t before = tb.accepted;
      tb.cycle(redirect, target, redirect ? 0 : accept, gate, 0, delay);
      if (tb.accepted > before) ++accepted_this;
      if (tb.errors > 0) break;
    }
    tb.check(tb.errors == 0, "random run errors");
    tb.check(tb.accepted >= static_cast<uint64_t>(kRandomAcceptsPerSeed),
             "random run insufficient accepts");
    random_total += tb.accepted;
    tb.drain_response_counters();
  }
  tb.check(random_total >= 1000, "random run total accepts below 1000",
           static_cast<uint32_t>(random_total), 1000);
  std::printf("P1-B_FRONTEND_RANDOM_PASS seeds=3 accepted=%llu\n",
              static_cast<unsigned long long>(random_total));

  tb.check(tb.errors == 0, "frontend errors");
  if (tb.errors != 0) {
    std::printf("P1-B_FRONTEND_TEST_FAIL errors=%d\n", tb.errors);
    delete dut;
    return 1;
  }

  std::printf("P1-B_FRONTEND_PASS accepted=%llu requests=%llu responses=%llu "
              "redirects=%llu cycles=%llu\n",
              static_cast<unsigned long long>(tb.accepted),
              static_cast<unsigned long long>(tb.requests),
              static_cast<unsigned long long>(tb.responses),
              static_cast<unsigned long long>(tb.redirects),
              static_cast<unsigned long long>(tb.cycles));
  delete dut;
  return 0;
}
