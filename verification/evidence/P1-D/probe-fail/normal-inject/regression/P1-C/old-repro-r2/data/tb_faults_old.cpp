// P1-C-R1 stopped-fault/control-boundary probes with multi-edge fault holds.
#include "Vinteger_tb_top.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

struct Case {
  std::vector<uint32_t> words;
  int kind;             // -1 means no fault expected
  uint32_t cause, tval, pc;
  int commits;
};

static void edge(Vinteger_tb_top* d) {
  d->clk = 1; d->eval(); d->clk = 0; d->eval();
}

int main(int argc, char** argv) {
  std::string name = "illegal";
  for (int i = 1; i < argc; ++i)
    if (std::strncmp(argv[i], "+case=", 6) == 0) name = argv[i] + 6;
  Verilated::commandArgs(argc, argv);

  Case c;
  if (name == "illegal") {
    c = {{0xffffffffu}, 1, 2, 0xffffffffu, 0x80000000u, 0};
  } else if (name == "unsupported") {
    c = {{0x30001073u}, 2, 0, 0x30001073u, 0x80000000u, 0};
  } else if (name == "unaligned") {
    c = {{0x006000efu}, 3, 0, 0x80000006u, 0x80000000u, 0};
  } else if (name == "unaligned_branch") {
    c = {{0x00000363u}, 3, 0, 0x80000006u, 0x80000000u, 0};
  } else if (name == "jalr_unaligned") {
    c = {{0x05500093u, 0x00700293u, 0x000280e7u}, 3, 0, 0x00000006u,
         0x80000008u, 2};
  } else if (name == "fetch") {
    c = {{0x100002b7u, 0x00028067u}, 0, 1, 0x10000000u, 0x10000000u, 2};
  } else if (name == "branch_untaken") {
    c = {{0x00100093u, 0x00008363u, 0x0000006fu}, -1, 0, 0, 0, 3};
  } else if (name == "jalr_clear") {
    c = {{0x00500293u, 0x000280e7u}, -1, 0, 0, 0, 2};
  } else {
    std::fprintf(stderr, "P1C_FAULT_FAIL: unknown case %s\n", name.c_str());
    return 2;
  }

  Vinteger_tb_top* d = new Vinteger_tb_top;
  d->reset = 1; d->accept_stall_i = 0; d->req_gate_i = 0;
  d->load_valid = 1; d->resp_delay_i = 0;
  for (uint32_t w = 0; w < c.words.size(); ++w) {
    d->load_word_addr = static_cast<uint16_t>(w);
    d->load_data = c.words[w];
    d->clk = 0; d->eval(); edge(d);
  }
  d->load_valid = 0; d->reset = 0;
  d->clk = 1; d->eval(); d->clk = 0; d->eval();

  int commits = 0;
  uint32_t last_pc = 0, last_next = 0, branch_next = 0;
  bool fault = false;
  int fault_cycles = 0;
  uint32_t snap_regs[32] = {0};
  uint32_t f_kind = 0, f_cause = 0, f_tval = 0, f_pc = 0, f_instr = 0;
  uint32_t f_tidx = 0, f_tgen = 0, f_fetch = 0;

  for (int cycle = 0; cycle < 600; ++cycle) {
    d->clk = 0; d->eval();
    if (d->commit_valid) {
      ++commits;
      last_pc = d->commit_pc;
      last_next = d->commit_next_pc;
      if (last_pc == 0x80000004u) branch_next = last_next;
    }
    if (d->fault_valid) {
      fault = true;
      f_kind = d->fault_kind; f_cause = d->fault_cause;
      f_tval = d->fault_tval; f_pc = d->fault_pc;
      f_instr = d->fault_instr; f_tidx = d->fault_token_idx;
      f_tgen = d->fault_token_gen; f_fetch = d->fault_fetch_gen;
      for (int r = 0; r < 32; ++r) snap_regs[r] = d->arf_debug_o[r];
      break;
    }
    if (c.kind < 0 && commits >= c.commits) { edge(d); break; }
    edge(d);
  }

  int errors = 0;
  auto check = [&](bool cond, const char* msg, uint32_t got, uint32_t want) {
    if (!cond) {
      std::fprintf(stderr, "P1C_FAULT_FAIL: case=%s %s got=0x%x want=0x%x\n",
                   name.c_str(), msg, got, want);
      ++errors;
    }
  };

  if (c.kind < 0) {
    check(!fault, "unexpected fault", 1, 0);
    check(commits == c.commits, "commit count", commits, c.commits);
    if (name == "branch_untaken") {
      check(branch_next == 0x80000008u, "untaken branch next_pc", branch_next,
            0x80000008u);
      check(last_pc == 0x80000008u, "last pc", last_pc, 0x80000008u);
      check(d->arf_debug_o[1] == 1u, "branch prefix ARF x1",
            d->arf_debug_o[1], 1u);
    } else if (name == "jalr_clear") {
      check(branch_next == 0x00000004u, "JALR cleared target", branch_next,
            0x00000004u);
      check(last_pc == 0x80000004u, "JALR commit pc", last_pc, 0x80000004u);
      check(d->arf_debug_o[1] == 0x80000008u, "JALR link ARF x1",
            d->arf_debug_o[1], 0x80000008u);
      check(d->arf_debug_o[5] == 5u, "JALR old rs1 ARF x5",
            d->arf_debug_o[5], 5u);
    }
  } else {
    check(fault, "fault not observed", 0, 1);
    check(f_kind == static_cast<unsigned>(c.kind), "fault kind", f_kind,
          static_cast<unsigned>(c.kind));
    check(f_cause == c.cause, "fault cause", f_cause, c.cause);
    check(f_tval == c.tval, "fault tval", f_tval, c.tval);
    check(f_pc == c.pc, "fault pc", f_pc, c.pc);
    check(commits == c.commits, "commits before fault", commits, c.commits);
    check(f_tidx == 0, "fault token idx", f_tidx, 0);
    check(!d->commit_valid, "fault and commit same cycle", d->commit_valid, 0);
    check(!d->ram_write, "fault caused RAM write", d->ram_write, 0);

    // Hold the stopped fault for sixteen actual edges and require complete
    // metadata/ARF stability with no commit/trap/side effect.
    for (int i = 0; i < 16; ++i) {
      edge(d);
      d->clk = 0; d->eval();
      check(d->fault_valid, "fault valid dropped", d->fault_valid, 1);
      check(d->fault_kind == f_kind, "fault kind changed", d->fault_kind, f_kind);
      check(d->fault_cause == f_cause, "fault cause changed", d->fault_cause, f_cause);
      check(d->fault_tval == f_tval, "fault tval changed", d->fault_tval, f_tval);
      check(d->fault_pc == f_pc, "fault pc changed", d->fault_pc, f_pc);
      check(d->fault_instr == f_instr, "fault instr changed", d->fault_instr, f_instr);
      check(d->fault_token_idx == f_tidx, "fault token idx changed",
            d->fault_token_idx, f_tidx);
      check(d->fault_token_gen == f_tgen, "fault token gen changed",
            d->fault_token_gen, f_tgen);
      check(d->fault_fetch_gen == f_fetch, "fault fetch_gen changed",
            d->fault_fetch_gen, f_fetch);
      check(!d->commit_valid, "commit during fault hold", d->commit_valid, 0);
      check(!d->commit_trap_valid, "trap during fault hold", d->commit_trap_valid, 0);
      check(!d->ram_write, "RAM write during fault hold", d->ram_write, 0);
      for (int r = 0; r < 32; ++r)
        check(d->arf_debug_o[r] == snap_regs[r], "ARF changed during fault hold",
              d->arf_debug_o[r], snap_regs[r]);
      ++fault_cycles;
    }
  }

  delete d;
  if (errors) {
    std::printf("P1C_FAULT_FAIL case=%s errors=%d\n", name.c_str(), errors);
    return 1;
  }
  std::printf("P1C_FAULT_PASS case=%s kind=%d commits=%d hold_edges=%d\n",
              name.c_str(), c.kind, commits, fault_cycles);
  return 0;
}
