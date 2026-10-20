// P1-C stopped-fault and control-boundary probes.
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

static void tick(Vinteger_tb_top* d) {
  d->clk = 0; d->eval(); d->clk = 1; d->eval(); d->clk = 0; d->eval();
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
    c = {{0x00002083u}, 2, 0, 0x00002083u, 0x80000000u, 0};
  } else if (name == "unaligned") {
    c = {{0x006000efu}, 3, 0, 0x80000006u, 0x80000000u, 0};
  } else if (name == "unaligned_branch") {
    c = {{0x00000363u}, 3, 0, 0x80000006u, 0x80000000u, 0};
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
  d->reset = 1; d->accept_stall_i = 0; d->load_valid = 1;
  d->resp_delay_i = 0;
  for (uint32_t w = 0; w < c.words.size(); ++w) {
    d->load_word_addr = static_cast<uint16_t>(w);
    d->load_data = c.words[w];
    tick(d);
  }
  d->load_valid = 0; d->reset = 0;
  d->clk = 1; d->eval(); d->clk = 0; d->eval();

  int commits = 0;
  uint32_t last_pc = 0, last_next = 0, branch_next = 0;
  bool fault = false;
  for (int cycle = 0; cycle < 500; ++cycle) {
    d->clk = 0; d->eval();
    if (d->commit_valid) {
      ++commits;
      last_pc = d->commit_pc;
      last_next = d->commit_next_pc;
      if (last_pc == 0x80000004u) branch_next = last_next;
    }
    if (d->fault_valid) { fault = true; break; }
    if (c.kind < 0 && commits >= c.commits) break;
    d->clk = 1; d->eval(); d->clk = 0; d->eval();
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
    } else if (name == "jalr_clear") {
      check(branch_next == 0x00000004u, "JALR cleared target", branch_next,
            0x00000004u);
      check(last_pc == 0x80000004u, "JALR commit pc", last_pc, 0x80000004u);
    }
  } else {
    check(fault, "fault not observed", 0, 1);
    check(d->fault_kind == static_cast<unsigned>(c.kind), "fault kind",
          d->fault_kind, static_cast<unsigned>(c.kind));
    check(d->fault_cause == c.cause, "fault cause", d->fault_cause, c.cause);
    check(d->fault_tval == c.tval, "fault tval", d->fault_tval, c.tval);
    check(d->fault_pc == c.pc, "fault pc", d->fault_pc, c.pc);
    check(commits == c.commits, "commits before fault", commits, c.commits);
    check(!d->commit_valid, "fault and commit same cycle", d->commit_valid, 0);
    check(!d->ram_write, "fault caused RAM write", d->ram_write, 0);
    if (c.commits == 0)
      for (int r = 0; r < 32; ++r)
        check(d->arf_debug_o[r] == 0, "fault changed ARF",
              d->arf_debug_o[r], 0);
  }

  delete d;
  if (errors) { std::printf("P1C_FAULT_FAIL case=%s errors=%d\n", name.c_str(), errors); return 1; }
  std::printf("P1C_FAULT_PASS case=%s kind=%d commits=%d\n", name.c_str(), c.kind, commits);
  return 0;
}
