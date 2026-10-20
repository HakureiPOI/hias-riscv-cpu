// P1-C integer DUT runner: loads a flat RAM image, executes until an endpoint
// PC, records real commit_bundle_t retire events and final ARF state.
#include "Vinteger_tb_top.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

static uint64_t parse_u64(const char* s, uint64_t def) {
  if (!s || !*s) return def;
  char* end = nullptr;
  uint64_t v = std::strtoull(s, &end, 0);
  return (end && *end == '\0') ? v : def;
}

static void tick(Vinteger_tb_top* d) {
  d->clk = 0; d->eval();
  d->clk = 1; d->eval();
  d->clk = 0; d->eval();
}

int main(int argc, char** argv) {
  std::string image, trace, regs_path;
  uint32_t end_pc = 0;
  uint64_t max_retire = 200000;
  uint32_t max_cycles = 1000000;
  bool stall_mode = false, delay_mode = false;
  int recovery_mode = -1;
  int fixed_delay = -1;
  for (int i = 1; i < argc; ++i) {
    const char* a = argv[i];
    if (std::strncmp(a, "+image=", 7) == 0) image = a + 7;
    else if (std::strncmp(a, "+trace=", 7) == 0) trace = a + 7;
    else if (std::strncmp(a, "+regs=", 6) == 0) regs_path = a + 6;
    else if (std::strncmp(a, "+end_pc=", 8) == 0) end_pc = (uint32_t)parse_u64(a + 8, 0);
    else if (std::strncmp(a, "+max_retire=", 12) == 0) max_retire = parse_u64(a + 12, max_retire);
    else if (std::strncmp(a, "+max_cycles=", 12) == 0) max_cycles = (uint32_t)parse_u64(a + 12, max_cycles);
    else if (std::strcmp(a, "+stall") == 0) stall_mode = true;
    else if (std::strcmp(a, "+delay") == 0) delay_mode = true;
    else if (std::strncmp(a, "+recovery=", 10) == 0)
      recovery_mode = (int)parse_u64(a + 10, 0);
    else if (std::strncmp(a, "+resp_delay=", 12) == 0)
      fixed_delay = (int)parse_u64(a + 12, 0);
  }
  Verilated::commandArgs(argc, argv);
  if (image.empty() || trace.empty() || regs_path.empty() || end_pc == 0) {
    std::fprintf(stderr, "P1C_DUT_FAIL: missing +image/+trace/+regs/+end_pc\n");
    return 2;
  }

  std::ifstream in(image, std::ios::binary);
  if (!in) { std::fprintf(stderr, "P1C_DUT_FAIL: cannot open image %s\n", image.c_str()); return 2; }
  std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)), {});
  while (bytes.size() % 4) bytes.push_back(0);
  const uint32_t words = static_cast<uint32_t>(bytes.size() / 4);

  Vinteger_tb_top* d = new Vinteger_tb_top;
  d->reset = 1;
  d->accept_stall_i = 0;
  d->req_gate_i = 0;
  d->load_valid = 1;
  d->resp_delay_i = 0;
  for (uint32_t w = 0; w < words; ++w) {
    d->load_word_addr = static_cast<uint16_t>(w);
    d->load_data = (uint32_t)bytes[4*w] | ((uint32_t)bytes[4*w+1] << 8) |
                   ((uint32_t)bytes[4*w+2] << 16) | ((uint32_t)bytes[4*w+3] << 24);
    tick(d);
  }
  d->load_valid = 0;
  d->reset = 0;
  d->clk = 1; d->eval();
  d->clk = 0; d->eval();

  std::ofstream tf(trace);
  if (!tf) { std::fprintf(stderr, "P1C_DUT_FAIL: cannot open trace\n"); return 2; }
  uint64_t seq = 0;
  uint32_t cycles = 0;
  uint32_t last_commit_pc = 0;
  uint32_t lfsr = 0x1a2b3c4du ^ words;
  uint64_t redirect_req_wait = 0, redirect_resp_wait = 0,
           redirect_resp_same = 0, redirect_dec = 0, redirect_stall = 0;
  uint32_t recovery_start = 0xffffffffu;
  bool prev_dec_valid = false;
  bool prev_req_wait = false;
  bool pending_commit = false;
  uint32_t pending_rd = 0, pending_wdata = 0;
  bool pending_rd_we = false;
  bool done = false;
  while (!done && cycles < max_cycles) {
    if (stall_mode) {
      lfsr = lfsr * 1664525u + 1013904223u;
      d->accept_stall_i = ((lfsr >> 16) % 100u) < 18u;
    } else {
      d->accept_stall_i = 0;
    }
    if (recovery_mode >= 0) {
      const uint32_t instr = d->decoded_valid ? d->decoded_instr : 0;
      const uint32_t opcode = instr & 0x7f;
      if (d->decoded_valid &&
          (opcode == 0x63 || opcode == 0x6f || opcode == 0x67))
        recovery_start = cycles + static_cast<uint32_t>(recovery_mode);
      d->req_gate_i = (cycles >= recovery_start && cycles < recovery_start + 6);
    } else {
      d->req_gate_i = stall_mode ? (((lfsr >> 20) % 100u) < 30u) : 0;
    }
    d->resp_delay_i = fixed_delay >= 0 ? static_cast<uint8_t>(fixed_delay) :
                      (delay_mode ? (lfsr & 3u) : 0);
    d->clk = 0; d->eval();
    if (d->redirect_valid) {
      if (prev_req_wait) ++redirect_req_wait;
      if (d->req_pending && !d->mem_resp_valid) ++redirect_resp_wait;
      if (d->mem_resp_valid) ++redirect_resp_same;
      if (d->decoded_held) ++redirect_dec;
      if (d->accept_stall_i) ++redirect_stall;
    }

    if (d->fault_valid) {
      std::fprintf(stderr,
        "P1C_DUT_FAIL: unexpected fault kind=%u pc=0x%08x instr=0x%08x "
        "cause=%u tval=0x%08x token=%u/%u fetch_gen=%u cycles=%u\\n",
        d->fault_kind, d->fault_pc, d->fault_instr, d->fault_cause,
        d->fault_tval, d->fault_token_idx, d->fault_token_gen,
        d->fault_fetch_gen, cycles);
      d->final();
      delete d;
      return 1;
    }

    if (d->commit_valid) {
      const bool rd_we = d->commit_rd_we;
      if (d->commit_slot_valid != 0x1 || d->commit_trap_valid)
        { std::fprintf(stderr, "P1C_DUT_FAIL: bad commit shape\\n"); return 1; }
      if (d->commit_priv != 0x3)
        { std::fprintf(stderr, "P1C_DUT_FAIL: non-M retirement\\n"); return 1; }
      const unsigned token_idx = static_cast<unsigned>(d->commit_token_idx);
      const unsigned token_gen = static_cast<unsigned>(d->commit_token_gen);
      const unsigned rd = static_cast<unsigned>(d->commit_rd);
      if (token_idx != 0 || token_gen != (seq & 0xffu))
        { std::fprintf(stderr, "P1C_DUT_FAIL: token mismatch idx=%u gen=%u seq=%llu\\n",
                       token_idx, token_gen,
                       (unsigned long long)seq); return 1; }
      if (rd_we && rd == 0)
        { std::fprintf(stderr, "P1C_DUT_FAIL: x0 write retired\\n"); return 1; }
      if (d->commit_csr_valid || d->commit_csr_rd_valid ||
          d->commit_csr_wr_valid || d->commit_mem_valid || d->commit_mem_we)
        { std::fprintf(stderr, "P1C_DUT_FAIL: unexpected CSR/mem retire\\n"); return 1; }
      if ((d->commit_next_pc & 3u) != 0)
        { std::fprintf(stderr, "P1C_DUT_FAIL: unaligned retired next_pc\\n"); return 1; }

      tf << "{\"schema\":\"hias-retire/2\",\"kind\":\"normal\",\"source\":\"dut\","
         << "\"seq\":" << seq
         << ",\"token\":{\"idx\":" << token_idx
         << ",\"gen\":" << token_gen << "},\"token_valid\":true"
         << ",\"pc\":" << d->commit_pc << ",\"instr\":" << d->commit_instr
         << ",\"next_pc\":" << d->commit_next_pc << ",\"next_pc_valid\":true"
         << ",\"priv\":\"M\",\"rd_we\":" << (rd_we ? "true" : "false")
         << ",\"rd\":" << rd
         << ",\"rd_data\":" << (rd_we ? std::to_string(d->commit_rd_data) : "null")
         << ",\"csr_valid\":false,\"csr_rd_valid\":false,\"csr_wr_valid\":false"
         << ",\"csr_addr\":null,\"csr_wdata\":null,\"csr_rdata\":null"
         << ",\"mem_valid\":false,\"mem_we\":false,\"mem_va\":null,\"mem_pa\":null"
         << ",\"mem_size\":\"none\",\"mem_mask\":null,\"mem_wdata\":null,\"mem_rdata\":null"
         << ",\"derived_fields\":[],\"not_observed_fields\":[]}\n";
      last_commit_pc = d->commit_pc;
      pending_commit = true;
      pending_rd_we = rd_we;
      pending_rd = rd;
      pending_wdata = d->commit_rd_data;
      ++seq;
      if (seq > max_retire) {
        std::fprintf(stderr, "P1C_DUT_FAIL: retire budget exceeded\n");
        return 1;
      }
      if (d->commit_pc == end_pc) done = true;
    }

    prev_dec_valid = d->decoded_valid;
    prev_req_wait = d->mem_req_valid && !d->mem_req_ready;
    d->clk = 1; d->eval();
    d->clk = 0; d->eval();
    if (pending_commit) {
      const uint32_t rd = static_cast<unsigned>(pending_rd);
      if (pending_rd_we && rd != 0 && d->arf_debug_o[rd] != pending_wdata) {
        std::fprintf(stderr, "P1C_DUT_FAIL: commit/ARF edge mismatch x%u "
                             "arf=0x%08x commit=0x%08x\n",
                     rd, d->arf_debug_o[rd], pending_wdata);
        return 1;
      }
      pending_commit = false;
    }
    ++cycles;
  }
  tf.close();

  if (!done) {
    std::fprintf(stderr, "P1C_DUT_FAIL: endpoint not reached in %u cycles "
                         "retires=%llu\\n", cycles, (unsigned long long)seq);
    return 1;
  }
  if (d->fault_valid) {
    std::fprintf(stderr, "P1C_DUT_FAIL: fault at endpoint\n");
    return 1;
  }

  std::ofstream rf(regs_path);
  rf << "{\"final_pc\":" << last_commit_pc << ",\"retire_count\":" << seq
     << ",\"regs\":[";
  for (int i = 0; i < 32; ++i) {
    if (i) rf << ",";
    rf << d->arf_debug_o[i];
  }
  rf << "]}\n";
  rf.close();
  std::printf("P1C_DUT_PASS retires=%llu endpoint=0x%08x cycles=%u "
              "redirect_req_wait=%llu redirect_resp_wait=%llu "
              "redirect_resp_same=%llu redirect_dec=%llu redirect_stall=%llu\n",
              (unsigned long long)seq, end_pc, cycles,
              (unsigned long long)redirect_req_wait,
              (unsigned long long)redirect_resp_wait,
              (unsigned long long)redirect_resp_same,
              (unsigned long long)redirect_dec,
              (unsigned long long)redirect_stall);
  d->final();
  delete d;
  return 0;
}
