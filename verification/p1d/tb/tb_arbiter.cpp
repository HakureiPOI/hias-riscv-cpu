// P1-D shared fetch/data arbiter protocol test.
#include "Varbiter_tb_top.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>

static int errors = 0;
static void check(bool c, const char* m, uint32_t g = 0, uint32_t w = 0) {
  if (!c) { std::fprintf(stderr, "P1D_ARB_FAIL: %s got=0x%x want=0x%x\n", m, g, w); ++errors; }
}
static void tick(Varbiter_tb_top* d) {
  d->clk = 0; d->eval(); d->clk = 1; d->eval(); d->clk = 0; d->eval();
}
static void base_inputs(Varbiter_tb_top* d) {
  d->reset = 0; d->fetch_valid = 0; d->lsu_valid = 0;
  d->fetch_resp_ready = 1; d->lsu_resp_ready = 1;
  d->bus_ready = 1; d->bus_resp_valid = 0;
  d->bus_resp_id = 0; d->bus_resp_gen = 0; d->bus_resp_rdata = 0; d->bus_resp_error = 0;
}
static void set_fetch(Varbiter_tb_top* d, bool v, uint32_t id, uint32_t gen) {
  d->fetch_valid = v; d->fetch_is_store = 0; d->fetch_va = 0x80000000u + id*4;
  d->fetch_pa = d->fetch_va; d->fetch_size = 2; d->fetch_mask = 0xf;
  d->fetch_wdata = 0; d->fetch_id = id; d->fetch_gen = gen;
}
static void set_lsu(Varbiter_tb_top* d, bool v, uint32_t id, uint32_t gen) {
  d->lsu_valid = v; d->lsu_is_store = 1; d->lsu_va = 0x80018000u + id*4;
  d->lsu_pa = d->lsu_va; d->lsu_size = 2; d->lsu_mask = 0xf;
  d->lsu_wdata = 0x12345678u; d->lsu_id = id; d->lsu_gen = gen;
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Varbiter_tb_top* d = new Varbiter_tb_top;
  base_inputs(d);
  d->reset = 1; tick(d); tick(d); d->reset = 0; d->eval();

  // Both clients wait: first grant goes to LSU (last=0), fetch stays unready.
  set_fetch(d, 1, 1, 0x11); set_lsu(d, 1, 2, 0x22); d->bus_ready = 1; d->eval();
  check(d->lsu_ready == 1 && d->fetch_ready == 0, "first fairness grant");
  check(d->bus_req_valid == 1 && d->bus_req_id == 2 && d->bus_req_gen == 0x22,
        "first bus owner payload");
  tick(d);
  set_lsu(d, 0, 2, 0x22); d->eval();
  check(d->lsu_outstanding == 1 && d->fetch_outstanding == 0, "lsu ownership");

  // Wrong identity response is drained but must not release the owner.
  d->bus_resp_valid = 1; d->bus_resp_id = 9; d->bus_resp_gen = 0x99;
  d->eval();
  check(d->lsu_resp_valid == 0 && d->fetch_resp_valid == 0, "wrong id not routed");
  check(d->lsu_outstanding == 1, "wrong id keeps owner");
  tick(d);
  check(d->lsu_outstanding == 1, "wrong id after edge keeps owner");
  d->bus_resp_valid = 1; d->bus_resp_id = 2; d->bus_resp_gen = 0x22;
  d->bus_resp_rdata = 0xabcd; d->lsu_resp_ready = 0; d->fetch_resp_ready = 1;
  d->eval();
  check(d->lsu_resp_valid == 1 && d->fetch_resp_valid == 0, "response owner");
  check(d->bus_resp_ready == 0, "response backpressure");
  d->lsu_resp_ready = 1; d->eval();
  check(d->bus_resp_ready == 1, "response release");
  tick(d);
  d->bus_resp_valid = 0; d->eval();
  check(d->lsu_outstanding == 0, "owner released");

  // Second grant goes to fetch, proving round-robin fairness.
  set_fetch(d, 1, 1, 0x11); set_lsu(d, 1, 3, 0x33); d->bus_ready = 1; d->eval();
  check(d->fetch_ready == 1 && d->lsu_ready == 0, "second fairness grant");
  tick(d);
  set_fetch(d, 0, 1, 0x11); d->eval();
  check(d->fetch_outstanding == 1, "fetch ownership");
  d->bus_resp_valid = 1; d->bus_resp_id = 1; d->bus_resp_gen = 0x11; d->eval();
  check(d->fetch_resp_valid == 1 && d->lsu_resp_valid == 0, "fetch response route");
  tick(d); d->bus_resp_valid = 0; set_lsu(d, 0, 3, 0x33); d->eval();

  // Selected request must be stable while bus not ready; a new LSU request
  // cannot steal the selection.
  set_fetch(d, 1, 7, 0x77); d->bus_ready = 0; d->eval();
  check(d->fetch_ready == 0, "fetch stalled");
  const uint32_t id0 = d->bus_req_id, gen0 = d->bus_req_gen;
  tick(d);  // lock the unaccepted selection
  set_lsu(d, 1, 8, 0x88); d->bus_ready = 0; d->eval();
  check(d->bus_req_id == id0 && d->bus_req_gen == gen0,
        "selected request stable", d->bus_req_id, id0);
  d->bus_ready = 1; d->eval();
  check(d->fetch_ready == 1 && d->lsu_ready == 0, "locked fetch ready");
  tick(d);
  check(d->fetch_outstanding == 1, "stalled fetch accepted");
  d->bus_resp_valid = 1; d->bus_resp_id = 7; d->bus_resp_gen = 0x77;
  d->eval(); tick(d); d->bus_resp_valid = 0; set_fetch(d, 0, 7, 0x77); d->eval();

  // A locked fetch request canceled before acceptance must not create a
  // false owner; LSU can then use the bus.
  d->bus_resp_valid = 0; set_fetch(d, 1, 4, 0x44); set_lsu(d, 0, 5, 0x55);
  d->bus_ready = 0; d->eval(); tick(d);
  set_fetch(d, 0, 4, 0x44); d->bus_ready = 1; d->eval();
  check(d->fetch_outstanding == 0 && d->lsu_outstanding == 0,
        "canceled lock no owner");
  check(!d->bus_req_valid, "canceled lock no bus request");
  tick(d);  // clear the canceled selection
  set_lsu(d, 1, 5, 0x55); d->bus_ready = 1; d->eval(); tick(d);
  check(d->lsu_outstanding == 1, "lsu after canceled lock");
  d->bus_resp_valid = 1; d->bus_resp_id = 5; d->bus_resp_gen = 0x55;
  d->eval(); tick(d); d->bus_resp_valid = 0; set_lsu(d, 0, 5, 0x55); d->eval();

  // Reset clears ownership; no old response is routed.
  d->reset = 1; tick(d); d->reset = 0; base_inputs(d); d->eval();
  check(d->fetch_outstanding == 0 && d->lsu_outstanding == 0, "reset ownership");
  check(d->fetch_resp_valid == 0 && d->lsu_resp_valid == 0, "reset response");

  delete d;
  if (errors) { std::printf("P1D_ARB_FAIL errors=%d\n", errors); return 1; }
  std::printf("P1D_ARB_PASS fairness routing stability backpressure reset\n");
  return 0;
}
