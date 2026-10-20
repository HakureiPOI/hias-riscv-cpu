// P1-C-R2 stopped-fault/control-boundary probes.
// The architectural mirror is updated only from expected normal commit writes;
// it is never read back from the DUT after a fault.
#include "Vinteger_tb_top.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>

static constexpr uint32_t BASE = 0x80000000u;

struct Write { int rd; uint32_t data; };  // rd=-1 means no architectural write

struct Case {
  std::vector<uint32_t> words;
  int kind;                 // -1 means no fault expected
  uint32_t cause, tval, pc, fault_instr;
  std::vector<uint32_t> commit_pcs;
  std::vector<Write> writes;
};

static void edge(Vinteger_tb_top* d) {
  d->clk = 1; d->eval(); d->clk = 0; d->eval();
}

static bool same_regs(const uint32_t* a, const uint32_t* b, int* bad) {
  for (int i = 0; i < 32; ++i)
    if (a[i] != b[i]) { *bad = i; return false; }
  return true;
}

static void report_regs(const char* phase, int r, uint32_t got, uint32_t want) {
  std::fprintf(stderr, "P1C_FAULT_MONITOR_MISMATCH phase=%s x%d got=0x%08x "
                       "want=0x%08x\n", phase, r, got, want);
}

int main(int argc, char** argv) {
  std::string name = "illegal", negative;
  for (int i = 1; i < argc; ++i) {
    if (std::strncmp(argv[i], "+case=", 6) == 0) name = argv[i] + 6;
    if (std::strncmp(argv[i], "+negative=", 10) == 0) negative = argv[i] + 10;
  }
  Verilated::commandArgs(argc, argv);

  Case c;
  if (name == "illegal") {
    c = {{0xffffffffu}, 1, 2, 0xffffffffu, 0x80000000u, 0xffffffffu, {}, {}};
  } else if (name == "unsupported") {
    c = {{0x30001073u}, 2, 0, 0x30001073u, 0x80000000u, 0x30001073u, {}, {}};
  } else if (name == "unaligned") {
    c = {{0x006000efu}, 3, 0, 0x80000006u, 0x80000000u, 0x006000efu, {}, {}};
  } else if (name == "unaligned_branch") {
    c = {{0x00000363u}, 3, 0, 0x80000006u, 0x80000000u, 0x00000363u, {}, {}};
  } else if (name == "jalr_unaligned") {
    c = {{0x05500093u, 0x00700293u, 0x000280e7u}, 3, 0, 0x00000006u,
         0x80000008u, 0x000280e7u, {0x80000000u, 0x80000004u},
         {{1, 0x55u}, {5, 7u}}};
  } else if (name == "fetch") {
    c = {{0x100002b7u, 0x00028067u}, 0, 1, 0x10000000u, 0x10000000u, 0x0u,
         {0x80000000u, 0x80000004u}, {{5, 0x10000000u}, {-1, 0}}};
  } else if (name == "branch_untaken") {
    c = {{0x00100093u, 0x00008363u, 0x0000006fu}, -1, 0, 0, 0, 0,
         {0x80000000u, 0x80000004u, 0x80000008u},
         {{1, 1u}, {-1, 0}, {-1, 0}}};
  } else if (name == "jalr_clear") {
    c = {{0x00500293u, 0x000280e7u}, -1, 0, 0, 0, 0,
         {0x80000000u, 0x80000004u},
         {{5, 5u}, {1, 0x80000008u}}};
  } else {
    std::fprintf(stderr, "P1C_FAULT_FAIL: unknown case %s\n", name.c_str());
    return 2;
  }
  if (!negative.empty() && name != "jalr_unaligned") {
    std::fprintf(stderr, "P1C_FAULT_FAIL: negative mode needs jalr_unaligned\n");
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
  d->clk = 0; d->eval();

  uint32_t mirror[32] = {0};
  std::map<uint32_t, uint32_t> fetch_gen_by_pc;
  int commits = 0;
  bool pending_commit = false;
  int pending_idx = -1;
  bool fault = false;
  int errors = 0;

  auto apply_pending = [&]() {
    if (!pending_commit) return;
    const Write& w = c.writes[pending_idx];
    if (w.rd >= 0 && w.rd != 0) mirror[w.rd] = w.data;
    mirror[0] = 0;
    pending_commit = false;
  };
  auto dump_trace = [&](const char* phase, int index, uint32_t pc,
                        uint32_t instr, bool rd_we, uint32_t rd,
                        uint32_t data) {
    std::printf("P1C_FAULT_TRACE case=%s phase=%s index=%d pc=0x%08x "
                "instr=0x%08x rd_we=%u rd=%u data=0x%08x\n",
                name.c_str(), phase, index, pc, instr, rd_we ? 1u : 0u, rd, data);
  };
  auto check_commit = [&](int idx) {
    if (idx >= static_cast<int>(c.commit_pcs.size())) {
      std::fprintf(stderr, "P1C_FAULT_FAIL: case=%s extra commit %d\n",
                   name.c_str(), idx);
      ++errors;
      return;
    }
    const uint32_t want_pc = c.commit_pcs[idx];
    const uint32_t want_instr = c.words[(want_pc - BASE) / 4];
    const Write& w = c.writes[idx];
    const bool want_we = w.rd >= 0 && w.rd != 0;
    const uint32_t got_rd = static_cast<unsigned>(d->commit_rd);
    const uint32_t got_data = d->commit_rd_data;
    bool ok = d->commit_valid && d->commit_pc == want_pc &&
              d->commit_instr == want_instr &&
              static_cast<bool>(d->commit_rd_we) == want_we;
    if (want_we) ok = ok && got_rd == static_cast<uint32_t>(w.rd) &&
                          got_data == w.data;
    if (!ok) {
      std::fprintf(stderr,
        "P1C_FAULT_FAIL: case=%s commit %d mismatch pc=0x%x/0x%x "
        "instr=0x%x/0x%x rd_we=%u/%u rd=%u/%d data=0x%x/0x%x\n",
        name.c_str(), idx, d->commit_pc, want_pc, d->commit_instr, want_instr,
        d->commit_rd_we, want_we, got_rd, w.rd, got_data, w.data);
      ++errors;
    }
    dump_trace("commit", idx, d->commit_pc, d->commit_instr,
               d->commit_rd_we, got_rd, got_data);
    pending_commit = d->commit_valid;
    pending_idx = idx;
  };
  auto compare_arf = [&](const uint32_t* obs, const char* phase,
                         bool report) -> bool {
    int bad = -1;
    if (same_regs(obs, mirror, &bad)) return true;
    if (report)
      report_regs(phase, bad, obs[bad], mirror[bad]);
    return false;
  };

  // Run until fault first observed or the expected normal commit count.
  for (int cycle = 0; cycle < 600; ++cycle) {
    d->clk = 0; d->eval();
    if (d->mem_req_valid && d->mem_req_ready)
      fetch_gen_by_pc[d->mem_req_va] = d->mem_req_gen;
    if (d->fault_valid) { fault = true; break; }
    if (d->commit_valid) {
      check_commit(commits);
      ++commits;
      if (c.kind < 0 && commits >= static_cast<int>(c.commit_pcs.size())) {
        edge(d);
        apply_pending();
        if (!compare_arf(d->arf_debug_o, "normal_final", true)) ++errors;
        break;
      }
    }
    edge(d);
    apply_pending();
    if (!compare_arf(d->arf_debug_o, "commit_edge", true)) ++errors;
  }

  if (c.kind < 0) {
    if (fault) { std::fprintf(stderr, "P1C_FAULT_FAIL: case=%s unexpected fault\n", name.c_str()); ++errors; }
    if (commits != static_cast<int>(c.commit_pcs.size())) {
      std::fprintf(stderr, "P1C_FAULT_FAIL: case=%s commits=%d expected=%zu\n",
                   name.c_str(), commits, c.commit_pcs.size());
      ++errors;
    }
    if (name == "branch_untaken") {
      if (d->arf_debug_o[1] != 1u || d->arf_debug_o[0] != 0u) ++errors;
    }
    if (name == "jalr_clear") {
      if (d->arf_debug_o[1] != 0x80000008u || d->arf_debug_o[5] != 5u) ++errors;
    }
  } else if (fault) {
    const uint32_t f_kind = d->fault_kind, f_cause = d->fault_cause;
    const uint32_t f_tval = d->fault_tval, f_pc = d->fault_pc;
    const uint32_t f_instr = d->fault_instr;
    const uint32_t f_tidx = d->fault_token_idx, f_tgen = d->fault_token_gen;
    const uint32_t f_fetch = d->fault_fetch_gen;
    std::printf("P1C_FAULT_TRACE case=%s phase=fault_first kind=%u cause=%u "
                "tval=0x%08x pc=0x%08x instr=0x%08x token=%u/%u fetch_gen=%u\n",
                name.c_str(), f_kind, f_cause, f_tval, f_pc, f_instr,
                f_tidx, f_tgen, f_fetch);
    if (f_kind != static_cast<unsigned>(c.kind) || f_cause != c.cause ||
        f_tval != c.tval || f_pc != c.pc || f_instr != c.fault_instr) {
      std::fprintf(stderr, "P1C_FAULT_FAIL: case=%s fault metadata mismatch\n",
                   name.c_str());
      ++errors;
    }
    if (f_tidx != 0 || f_tgen != static_cast<uint32_t>(commits)) {
      std::fprintf(stderr, "P1C_FAULT_FAIL: case=%s fault token %u/%u "
                           "expected 0/%d\n", name.c_str(), f_tidx, f_tgen, commits);
      ++errors;
    }
    auto it = fetch_gen_by_pc.find(f_pc);
    if (it == fetch_gen_by_pc.end() || f_fetch != it->second) {
      std::fprintf(stderr, "P1C_FAULT_FAIL: case=%s fault fetch_gen=%u "
                           "expected=%s\n", name.c_str(), f_fetch,
                   it == fetch_gen_by_pc.end() ? "missing" : "recorded");
      ++errors;
    }
    if (d->commit_valid || d->commit_trap_valid || d->ram_write) {
      std::fprintf(stderr, "P1C_FAULT_FAIL: case=%s side effect at fault\n",
                   name.c_str());
      ++errors;
    }
    if (!compare_arf(d->arf_debug_o, "fault_first", true)) ++errors;

    if (negative == "initial_arf") {
      uint32_t obs[32];
      for (int r = 0; r < 32; ++r) obs[r] = d->arf_debug_o[r];
      obs[1] = 0x8000000cu;  // the link value the buggy JALR would write
      int bad = -1;
      if (!same_regs(obs, mirror, &bad) && bad == 1) {
        report_regs("negative_initial", bad, obs[bad], mirror[bad]);
        std::printf("P1C_FAULT_NEGATIVE_INITIAL_ARF_DETECTED\n");
        delete d;
        return 1;
      }
      std::printf("P1C_FAULT_NEGATIVE_INITIAL_ARF_NOT_DETECTED\n");
      delete d;
      return 2;
    }

    // Sixteen actual edges with independent architectural mirror and metadata
    // stability checks. No DUT ARF read is used as the expected value.
    for (int i = 0; i < 16; ++i) {
      edge(d);
      d->clk = 0; d->eval();
      if (!d->fault_valid || d->fault_kind != f_kind || d->fault_cause != f_cause ||
          d->fault_tval != f_tval || d->fault_pc != f_pc ||
          d->fault_instr != f_instr || d->fault_token_idx != f_tidx ||
          d->fault_token_gen != f_tgen || d->fault_fetch_gen != f_fetch) {
        std::fprintf(stderr, "P1C_FAULT_FAIL: case=%s fault metadata changed "
                             "at hold edge %d\n", name.c_str(), i);
        ++errors;
      }
      if (d->commit_valid || d->commit_trap_valid || d->ram_write) {
        std::fprintf(stderr, "P1C_FAULT_FAIL: case=%s side effect in hold %d\n",
                     name.c_str(), i);
        ++errors;
      }
      if (negative == "hold_change" && i == 3) {
        uint32_t obs[32];
        for (int r = 0; r < 32; ++r) obs[r] = d->arf_debug_o[r];
        obs[5] ^= 1u;  // one held architectural value changes
        int bad = -1;
        if (!same_regs(obs, mirror, &bad) && bad == 5) {
          report_regs("negative_hold", bad, obs[bad], mirror[bad]);
          std::printf("P1C_FAULT_NEGATIVE_HOLD_CHANGE_DETECTED\n");
          delete d;
          return 1;
        }
        std::printf("P1C_FAULT_NEGATIVE_HOLD_CHANGE_NOT_DETECTED\n");
        delete d;
        return 2;
      }
      if (!compare_arf(d->arf_debug_o, "hold_edge", true)) {
        std::fprintf(stderr, "P1C_FAULT_FAIL: case=%s ARF changed at hold %d\n",
                     name.c_str(), i);
        ++errors;
      }
      std::printf("P1C_FAULT_TRACE case=%s phase=hold edge=%d arf_ok\n",
                  name.c_str(), i);
    }
  } else {
    std::fprintf(stderr, "P1C_FAULT_FAIL: case=%s fault not observed\n", name.c_str());
    ++errors;
  }

  delete d;
  if (errors) {
    std::printf("P1C_FAULT_FAIL case=%s errors=%d\n", name.c_str(), errors);
    return 1;
  }
  std::printf("P1C_FAULT_PASS case=%s kind=%d commits=%d\n",
              name.c_str(), c.kind, commits);
  return 0;
}
