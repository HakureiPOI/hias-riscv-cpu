// Reproduce F02 against the old P1-B frontend (commit 278f6f7).
#include "Vfrontend_tb_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>

static constexpr uint32_t RESET = 0x80000000u;
static constexpr uint32_t NOP = 0x00000013u;

static void tick(Vfrontend_tb_top* d) {
  d->clk = 0; d->eval();
  d->clk = 1; d->eval();
  d->clk = 0; d->eval();
}

static void defaults(Vfrontend_tb_top* d) {
  d->redirect_valid = 0; d->redirect_target = 0; d->redirect_cause = 0;
  d->redirect_flush_all = 1;
  d->load_valid = 0; d->load_word_addr = 0; d->load_data = 0;
  d->resp_delay_i = 0; d->req_gate = 0; d->fault_mode = 0;
  d->decoded_accept = 0;
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vfrontend_tb_top* d = new Vfrontend_tb_top;
  defaults(d);
  d->reset = 1;
  d->load_valid = 1;
  for (int i = 0; i < 32; ++i) {
    d->load_word_addr = static_cast<uint16_t>(i);
    d->load_data = NOP;
    tick(d);
  }
  d->load_valid = 0;
  d->reset = 0;
  d->clk = 0; d->eval();

  // F02a: a held decoded result must be suppressed/not accepted when an
  // effective redirect and accept=1 happen in the same cycle.
  d->redirect_valid = 1; d->redirect_target = RESET + 8u;
  tick(d);
  d->redirect_valid = 0;
  for (int i = 0; i < 50 && !d->dec_valid; ++i) tick(d);
  const uint32_t old_pc = d->dec_pc;
  d->decoded_accept = 1;
  d->redirect_valid = 1; d->redirect_target = RESET + 32u;
  d->clk = 0; d->eval();
  const bool leak = d->dec_valid && (d->dec_pc == old_pc);
  std::printf("OLD_F02A old_pc=0x%08x dec_valid=%u dec_pc=0x%08x leak=%u\n",
              old_pc, d->dec_valid, d->dec_pc, leak);
  if (!leak) { delete d; std::printf("OLD_F02A_NOT_REPRODUCED\n"); return 1; }
  std::printf("OLD_F02A_REDIRECT_ACCEPT_LEAK\n");

  // Reset for the cancelled last-generation request test.
  defaults(d);
  d->reset = 1;
  for (int i = 0; i < 2; ++i) tick(d);
  d->reset = 0;
  d->decoded_accept = 1;
  bool accepted_last = false;
  for (int i = 0; i < 100; ++i) {
    d->clk = 0; d->eval();
    const bool fire = d->mem_req_valid_o && d->mem_req_ready_o;
    const uint32_t gen = d->mem_req_gen_o;
    if (fire && gen == 3u) {
      accepted_last = true;
      d->clk = 1; d->eval(); d->clk = 0; d->eval();
      break;
    }
    tick(d);
  }
  if (!accepted_last) { delete d; std::printf("OLD_F02B_LAST_GEN_NOT_ACCEPTED\n"); return 1; }

  d->fault_mode = 1;                 // wrong ID and generation, real next
  d->redirect_valid = 1;
  d->redirect_target = RESET + 16u;
  d->decoded_accept = 0;
  tick(d);                           // cancel the last-generation request
  d->redirect_valid = 0;

  bool saw_wrong = false;
  bool released_early = false;
  uint64_t requests_before = 0;
  for (int i = 0; i < 20; ++i) {
    d->clk = 0; d->eval();
    if (d->mem_req_valid_o && d->mem_req_ready_o) ++requests_before;
    d->clk = 1; d->eval();
    d->clk = 0; d->eval();
    if (d->fault_used_o) {
      saw_wrong = true;
      if (!d->req_pending_o) { released_early = true; break; }
    }
  }
  std::printf("OLD_F02B saw_wrong=%u pending_after_wrong=%u early_release=%u\n",
              saw_wrong, d->req_pending_o, released_early);
  const bool bad = saw_wrong && released_early;
  if (bad) std::printf("OLD_F02B_CANCEL_WRONG_RESPONSE_RELEASED\n");
  else std::printf("OLD_F02B_NOT_REPRODUCED\n");
  delete d;
  return bad ? 0 : 1;
}
