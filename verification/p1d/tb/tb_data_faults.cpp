// P1-D Load/Store fault and stopped-state probes.
#include "Vinteger_tb_top.h"
#include "Vinteger_tb_top___024root.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>

static constexpr uint32_t BASE = 0x80000000u;
static constexpr uint32_t DATA = 0x80018000u;
struct Write { int rd; uint32_t data; };
struct Case {
  std::vector<uint32_t> words;
  uint32_t kind, cause, tval, pc, instr;
  std::vector<uint32_t> commit_pcs;
  std::vector<Write> writes;
  bool force_error;
};
static void edge(Vinteger_tb_top* d) {
  d->clk = 1; d->eval(); d->clk = 0; d->eval();
}
static uint8_t ram_byte(Vinteger_tb_top* d, uint32_t addr) {
  return d->rootp->integer_tb_top__DOT__u_top__DOT__u_bridge__DOT__u_ram__DOT__mem[addr - BASE];
}
int main(int argc, char** argv) {
  std::string name = "load_misalign", negative;
  for (int i = 1; i < argc; ++i) {
    if (std::strncmp(argv[i], "+case=", 6) == 0) name = argv[i] + 6;
    if (std::strncmp(argv[i], "+negative=", 10) == 0) negative = argv[i] + 10;
  }
  Verilated::commandArgs(argc, argv);
  Case c;
  if (name == "load_misalign") {
    c = {{0x00202083u}, 4, 4, 2, 0x80000000u, 0x00202083u, {}, {}, false};
  } else if (name == "load_x0_misalign") {
    c = {{0x00202003u}, 4, 4, 2, 0x80000000u, 0x00202003u, {}, {}, false};
  } else if (name == "load_access") {
    c = {{0x00002083u}, 5, 5, 0, 0x80000000u, 0x00002083u, {}, {}, false};
  } else if (name == "store_misalign") {
    c = {{0x800182b7u, 0x07f00313u, 0x0062a123u}, 6, 6, 0x80018002u,
         0x80000008u, 0x0062a123u, {0x80000000u, 0x80000004u},
         {{5, 0x80018000u}, {6, 0x7fu}}, false};
  } else if (name == "store_access") {
    c = {{0x100002b7u, 0x07f00313u, 0x0062a023u}, 7, 7, 0x10000000u,
         0x80000008u, 0x0062a023u, {0x80000000u, 0x80000004u},
         {{5, 0x10000000u}, {6, 0x7fu}}, false};
  } else if (name == "bridge_load_error") {
    c = {{0x800182b7u, 0x0002a083u}, 5, 5, 0x80018000u, 0x80000004u,
         0x0002a083u, {0x80000000u}, {{5, 0x80018000u}}, true};
  } else if (name == "ram_end_load_byte") {
    c = {{0x800202b7u, 0x00028083u}, 5, 5, 0x80020000u, 0x80000004u,
         0x00028083u, {0x80000000u}, {{5, 0x80020000u}}, false};
  } else if (name == "ram_end_load_half") {
    c = {{0x800202b7u, 0x00029083u}, 5, 5, 0x80020000u, 0x80000004u,
         0x00029083u, {0x80000000u}, {{5, 0x80020000u}}, false};
  } else if (name == "ram_end_load_word") {
    c = {{0x800202b7u, 0x0002a083u}, 5, 5, 0x80020000u, 0x80000004u,
         0x0002a083u, {0x80000000u}, {{5, 0x80020000u}}, false};
  } else if (name == "ram_end_store_byte") {
    c = {{0x800202b7u, 0x07f00313u, 0x00628023u}, 7, 7, 0x80020000u,
         0x80000008u, 0x00628023u, {0x80000000u, 0x80000004u},
         {{5, 0x80020000u}, {6, 0x7fu}}, false};
  } else if (name == "ea_wrap_load") {
    c = {{0xfffff2b7u, 0x7ff28293u, 0x7fd28293u, 0x0042a083u}, 5, 5,
         0x00000000u, 0x8000000cu, 0x0042a083u,
         {0x80000000u, 0x80000004u, 0x80000008u},
         {{5, 0xfffff000u}, {5, 0xfffff7ffu}, {5, 0xfffffffcu}}, false};
  } else if (name == "mmio_load") {
    c = {{0x100002b7u, 0x0002a083u}, 5, 5, 0x10000000u, 0x80000004u,
         0x0002a083u, {0x80000000u}, {{5, 0x10000000u}}, false};
  } else {
    std::fprintf(stderr, "P1D_FAULT_FAIL: unknown case %s\n", name.c_str());
    return 2;
  }

  Vinteger_tb_top* d = new Vinteger_tb_top;
  d->reset = 1; d->accept_stall_i = 0; d->req_gate_i = 0; d->lsu_gate_i = 0;
  d->force_lsu_error_i = c.force_error ? 1 : 0;
  d->load_valid = 1; d->resp_delay_i = 0;
  for (uint32_t w = 0; w < c.words.size(); ++w) {
    d->load_word_addr = static_cast<uint16_t>(w);
    d->load_data = c.words[w];
    d->clk = 0; d->eval(); edge(d);
  }
  d->load_valid = 0; d->reset = 0; d->clk = 0; d->eval();

  uint32_t mirror[32] = {0};
  std::map<uint32_t, uint32_t> fetch_gen_by_pc;
  uint8_t data_before[16];
  for (int i = 0; i < 16; ++i) data_before[i] = ram_byte(d, DATA + i);
  int commits = 0, errors = 0;
  bool fault = false;
  auto check = [&](bool ok, const char* m, uint32_t g = 0, uint32_t w = 0) {
    if (!ok) { std::fprintf(stderr, "P1D_FAULT_FAIL: case=%s %s got=0x%x want=0x%x\n",
                             name.c_str(), m, g, w); ++errors; }
  };
  for (int cycle = 0; cycle < 500; ++cycle) {
    d->clk = 0; d->eval();
    if (d->fetch_req_valid && d->fetch_req_ready)
      fetch_gen_by_pc[d->fetch_req_va] = d->fetch_req_gen;
    if (d->fault_valid) {
      fault = true;
      check(!d->commit_valid && !d->commit_trap_valid && !d->ram_write,
            "side effect at first fault");
      if (negative == "first_event")
        check(d->ram_write, "injected first-fault RAM event", d->ram_write, 1);
      if (negative == "first_event")
        check(d->commit_valid, "injected first-fault commit", d->commit_valid, 1);
      break;
    }
    if (d->commit_valid) {
      if (commits >= static_cast<int>(c.commit_pcs.size())) {
        check(false, "extra normal commit", commits, c.commit_pcs.size());
        break;
      }
      const uint32_t want_pc = c.commit_pcs[commits];
      const uint32_t want_instr = c.words[(want_pc - BASE) / 4];
      const Write& w = c.writes[commits];
      check(d->commit_pc == want_pc, "commit pc", d->commit_pc, want_pc);
      check(d->commit_instr == want_instr, "commit instr", d->commit_instr, want_instr);
      if (w.rd >= 0) {
        check(d->commit_rd_we, "commit rd_we", d->commit_rd_we, 1);
        check(d->commit_rd == static_cast<unsigned>(w.rd), "commit rd", d->commit_rd, w.rd);
        check(d->commit_rd_data == w.data, "commit data", d->commit_rd_data, w.data);
        mirror[w.rd] = w.data;
      } else {
        check(!d->commit_rd_we, "unexpected commit rd_we", d->commit_rd_we, 0);
      }
      ++commits;
    }
    edge(d);
    d->clk = 0; d->eval();
  }

  check(fault, "fault not observed", 0, 1);
  check(commits == static_cast<int>(c.commit_pcs.size()), "prefix commits",
        commits, c.commit_pcs.size());
  check(d->fault_kind == c.kind, "fault kind", d->fault_kind, c.kind);
  check(d->fault_cause == c.cause, "fault cause", d->fault_cause, c.cause);
  check(d->fault_tval == c.tval, "fault tval", d->fault_tval, c.tval);
  check(d->fault_pc == c.pc, "fault pc", d->fault_pc, c.pc);
  check(d->fault_instr == c.instr, "fault instr", d->fault_instr, c.instr);
  check(d->fault_token_idx == 0, "fault token idx", d->fault_token_idx, 0);
  check(d->fault_token_gen == static_cast<unsigned>(commits), "fault token gen",
        d->fault_token_gen, commits);
  auto fg = fetch_gen_by_pc.find(c.pc);
  check(fg != fetch_gen_by_pc.end() && d->fault_fetch_gen == fg->second,
        "fault fetch_gen", d->fault_fetch_gen,
        fg == fetch_gen_by_pc.end() ? 0xffffffffu : fg->second);
  for (int r = 0; r < 32; ++r)
    check(d->arf_debug_o[r] == mirror[r], "fault ARF", d->arf_debug_o[r], mirror[r]);
  const unsigned f_kind = d->fault_kind, f_cause = d->fault_cause;
  const uint32_t f_tval = d->fault_tval, f_pc = d->fault_pc,
                 f_instr = d->fault_instr, f_tidx = d->fault_token_idx,
                 f_tgen = d->fault_token_gen, f_fetch = d->fault_fetch_gen;
  for (int i = 0; i < 16; ++i) {
    edge(d); d->clk = 0; d->eval();
    check(d->fault_valid, "fault dropped", d->fault_valid, 1);
    check(d->fault_kind == f_kind && d->fault_cause == f_cause &&
          d->fault_tval == f_tval && d->fault_pc == f_pc &&
          d->fault_instr == f_instr && d->fault_token_idx == f_tidx &&
          d->fault_token_gen == f_tgen && d->fault_fetch_gen == f_fetch,
          "fault metadata changed");
    check(!d->commit_valid && !d->commit_trap_valid, "commit/trap during hold");
    check(!d->ram_write, "RAM write during hold", d->ram_write, 0);
    for (int r = 0; r < 32; ++r) {
      uint32_t obs = d->arf_debug_o[r];
      if (negative == "hold_change" && i == 3 && r == 5) obs ^= 1u;
      check(obs == mirror[r], "ARF changed during hold", obs, mirror[r]);
    }
  }
  for (int i = 0; i < 16; ++i)
    check(ram_byte(d, DATA + i) == data_before[i], "protected RAM changed",
          ram_byte(d, DATA + i), data_before[i]);

  delete d;
  if (!negative.empty()) {
    if (negative == "first_event" && errors > 0) {
      std::printf("P1D_FAULT_NEGATIVE_FIRST_EVENT_DETECTED errors=%d\n", errors);
      return 1;
    }
    if (negative == "hold_change" && errors > 0) {
      std::printf("P1D_FAULT_NEGATIVE_HOLD_CHANGE_DETECTED errors=%d\n", errors);
      return 1;
    }
    std::printf("P1D_FAULT_NEGATIVE_%s_NOT_DETECTED errors=%d\n",
                negative.c_str(), errors);
    return 2;
  }
  if (errors) { std::printf("P1D_FAULT_FAIL case=%s errors=%d\n", name.c_str(), errors); return 1; }
  std::printf("P1D_FAULT_PASS case=%s kind=%u cause=%u commits=%d hold_edges=16\n",
              name.c_str(), c.kind, c.cause, commits);
  return 0;
}
