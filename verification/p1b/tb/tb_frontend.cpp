// P1-B-R1 fetch/decode + real RAM/bridge integration test.
//
// The monitor is edge-based: every working edge (including same-cycle redirect
// and illegal-target probes) goes through begin/commit. Requests are matched
// to responses through an independent outstanding queue; decode accepts are
// matched to the completed fetch result. Global errors are never cleared.
#include "Vfrontend_tb_top.h"
#include "verilated.h"
#include "../decode_expected.h"

#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <map>
#include <random>
#include <string>

#ifndef P1B_GEN_W
#define P1B_GEN_W 8
#endif

static constexpr uint32_t RESET_VECTOR = 0x80000000u;
static constexpr uint32_t RAM_END = 0x80020000u;
static constexpr uint32_t NOP = 0x00000013u;

struct Expected {
  uint32_t instr;
  uint32_t op, exec, rd, rs1, rs2, imm, uses1, uses2, rd_we;
  uint32_t is_branch, is_jump, is_load, is_store, is_csr;
  uint32_t is_fence, is_fence_i, is_mret, is_sret, is_wfi;
  uint32_t illegal, illegal_cause, illegal_tval;
  uint32_t mem_size, csr_op, csr_addr, csr_uimm, csr_uimm_valid;
  uint32_t fetch_exc, fetch_cause, fetch_tval;
};

struct DecodedSnap {
  bool valid;
  uint32_t pc, instr, op, exec, rd, rs1, rs2, imm, uses1, uses2, rd_we;
  uint32_t is_branch, is_jump, is_load, is_store, is_csr;
  uint32_t is_fence, is_fence_i, is_mret, is_sret, is_wfi;
  uint32_t illegal, illegal_cause, illegal_tval;
  uint32_t mem_size, csr_op, csr_addr, csr_uimm, csr_uimm_valid;
  uint32_t fetch_exc_valid, fetch_exc_cause, fetch_exc_tval, fetch_gen;
  uint32_t pred_taken, pred_target, pred_index;
};

struct Stats {
  uint64_t accepted = 0;
  uint64_t requests = 0;
  uint64_t responses = 0;
  uint64_t matched = 0;
  uint64_t orphan = 0;
  uint64_t redirects = 0;
  uint64_t decode_accepts = 0;
  uint64_t fetch_exc = 0;
};

struct ReqRec {
  uint64_t pa;
  uint32_t pc;
  uint32_t id;
  uint32_t gen;
  Expected expected;
  bool cancelled;
};

struct ResRec {
  uint32_t pc;
  uint32_t gen;
  uint32_t instr;
  uint32_t fetch_exc;
};

struct Inputs {
  bool redirect = false;
  uint32_t target = RESET_VECTOR;
  uint8_t accept = 0;
  bool gate = false;
  uint8_t fault = 0;
  uint8_t delay = 0;
  uint8_t fault_delay = 0;
  bool req_mask_xor = false;
  bool reset = false;
};

struct ReqSnap {
  bool valid = false;
  bool is_store = false;
  uint32_t va = 0;
  uint64_t pa = 0;
  uint32_t size = 0;
  uint32_t byte_mask = 0;
  uint32_t wdata = 0;
  bool cacheable = false;
  uint32_t priv = 0;
  uint32_t id = 0;
  uint32_t gen = 0;
};

struct Pre {
  bool dec_valid = false;
  DecodedSnap dec{};
  ReqSnap req{};
  bool req_ready = false, req_fire = false;
  bool resp_valid = false, resp_ready = false, resp_fire = false;
  uint32_t resp_id = 0, resp_gen = 0, resp_rdata = 0;
  bool resp_error = false;
};

struct Tb {
  Vfrontend_tb_top* dut;
  std::map<uint32_t, Expected> image;
  std::deque<ReqRec> outstanding;
  std::deque<ResRec> results;
  Stats total, stage_start;
  uint64_t errors = 0;
  uint64_t op_errors = 0;
  uint64_t other_errors = 0;
  uint64_t pc_errors = 0;
  uint64_t req_errors = 0;
  uint64_t stage_error_start = 0;
  uint64_t cycles = 0;
  uint64_t max_cycles = 1000000;
  uint32_t model_pc = RESET_VECTOR;
  uint32_t next_req_pc = RESET_VECTOR;
  std::string stage = "init";
  bool compare_enabled = true;
  bool inject_pc_skip = false;
  bool inject_req_stability = false;
  bool pc_injected = false;
  bool flow_complete = false;

  bool held_dec_valid = false;
  DecodedSnap held_dec{};
  bool held_req_valid = false;
  ReqSnap held_req{};

  explicit Tb(Vfrontend_tb_top* d) : dut(d) {}

  enum ErrCat { CAT_OTHER, CAT_OP, CAT_PC, CAT_REQ };

  void fail_cat(ErrCat cat, const char* msg, uint32_t got = 0,
                uint32_t want = 0) {
    std::fprintf(stderr,
                 "P1-B_FRONTEND_FAIL: stage=%s cat=%s %s got=0x%x want=0x%x pc=0x%x\n",
                 stage.c_str(), cat == CAT_OP ? "op" :
                 (cat == CAT_PC ? "pc" : (cat == CAT_REQ ? "req" : "other")),
                 msg, got, want, model_pc);
    ++errors;
    if (cat == CAT_OP) ++op_errors; else ++other_errors;
    if (cat == CAT_PC) ++pc_errors;
    if (cat == CAT_REQ) ++req_errors;
    if (errors > 200) std::exit(1);
  }

  void fail(const char* msg, uint32_t got = 0, uint32_t want = 0) {
    fail_cat(CAT_OTHER, msg, got, want);
  }

  void check(bool cond, const char* msg, uint32_t got = 0, uint32_t want = 0) {
    if (!cond) fail_cat(CAT_OTHER, msg, got, want);
  }

  void check_op(bool cond, const char* msg, uint32_t got = 0,
                uint32_t want = 0) {
    if (!cond) fail_cat(CAT_OP, msg, got, want);
  }

  void check_pc(bool cond, const char* msg, uint32_t got = 0,
                uint32_t want = 0) {
    if (!cond) fail_cat(CAT_PC, msg, got, want);
  }

  void check_req(bool cond, const char* msg, uint32_t got = 0,
                 uint32_t want = 0) {
    if (!cond) fail_cat(CAT_REQ, msg, got, want);
  }

  static Expected nop_expected() {
    Expected x{};
    x.instr = NOP;
    x.op = 7; x.exec = 10; x.rd = 0; x.rs1 = 0; x.rs2 = 0; x.imm = 0;
    x.uses1 = 1; x.uses2 = 0; x.rd_we = 0;
    x.mem_size = 2; x.csr_op = 0;
    return x;
  }

  static Expected fetch_error_expected(uint32_t pc) {
    Expected x = nop_expected();
    x.instr = 0;
    x.fetch_exc = 1;
    x.fetch_cause = 1;
    x.fetch_tval = pc;
    return x;
  }

  static Expected from_case(const ExpectedDecode& e) {
    Expected x{};
    x.instr = e.instr; x.op = e.op; x.exec = e.exec;
    x.rd = e.rd; x.rs1 = e.rs1; x.rs2 = e.rs2; x.imm = e.imm;
    x.uses1 = e.uses1; x.uses2 = e.uses2; x.rd_we = e.rd_we;
    x.is_branch = e.is_branch; x.is_jump = e.is_jump;
    x.is_load = e.is_load; x.is_store = e.is_store; x.is_csr = e.is_csr;
    x.is_fence = e.is_fence; x.is_fence_i = e.is_fence_i;
    x.is_mret = e.is_mret; x.is_sret = e.is_sret; x.is_wfi = e.is_wfi;
    x.illegal = e.illegal; x.illegal_cause = e.illegal_cause;
    x.illegal_tval = e.illegal_tval;
    x.mem_size = e.mem_size; x.csr_op = e.csr_op; x.csr_addr = e.csr_addr;
    x.csr_uimm = e.csr_uimm; x.csr_uimm_valid = e.csr_uimm_valid;
    return x;
  }

  void setup_image() {
    image.clear();
    for (unsigned i = 0; i < kDecodeCaseCount; ++i) {
      const ExpectedDecode& e = kDecodeCases[i];
      image[e.pc] = from_case(e);
    }
  }

  Expected expected_at(uint32_t pc) const {
    auto it = image.find(pc);
    if (it != image.end()) return it->second;
    if (pc < RESET_VECTOR || pc >= RAM_END) return fetch_error_expected(pc);
    return nop_expected();
  }

  DecodedSnap snapshot() const {
    DecodedSnap d{};
    d.valid = dut->dec_valid;
    d.pc = dut->dec_pc; d.instr = dut->dec_instr;
    d.op = dut->dec_op; d.exec = dut->dec_exec;
    d.rd = dut->dec_rd; d.rs1 = dut->dec_rs1; d.rs2 = dut->dec_rs2;
    d.imm = dut->dec_imm; d.uses1 = dut->dec_uses1; d.uses2 = dut->dec_uses2;
    d.rd_we = dut->dec_rd_we;
    d.is_branch = dut->dec_is_branch; d.is_jump = dut->dec_is_jump;
    d.is_load = dut->dec_is_load; d.is_store = dut->dec_is_store;
    d.is_csr = dut->dec_is_csr; d.is_fence = dut->dec_is_fence;
    d.is_fence_i = dut->dec_is_fence_i; d.is_mret = dut->dec_is_mret;
    d.is_sret = dut->dec_is_sret; d.is_wfi = dut->dec_is_wfi;
    d.illegal = dut->dec_illegal; d.illegal_cause = dut->dec_illegal_cause;
    d.illegal_tval = dut->dec_illegal_tval;
    d.mem_size = dut->dec_mem_size; d.csr_op = dut->dec_csr_op;
    d.csr_addr = dut->dec_csr_addr; d.csr_uimm = dut->dec_csr_uimm;
    d.csr_uimm_valid = dut->dec_csr_uimm_valid;
    d.fetch_exc_valid = dut->dec_fetch_exc_valid;
    d.fetch_exc_cause = dut->dec_fetch_exc_cause;
    d.fetch_exc_tval = dut->dec_fetch_exc_tval;
    d.fetch_gen = dut->dec_fetch_gen;
    d.pred_taken = dut->dec_pred_taken;
    d.pred_target = dut->dec_pred_target;
    d.pred_index = dut->dec_pred_index;
    return d;
  }

  bool same_dec(const DecodedSnap& a, const DecodedSnap& b) const {
    return a.valid == b.valid && a.pc == b.pc && a.instr == b.instr &&
           a.op == b.op && a.exec == b.exec && a.rd == b.rd &&
           a.rs1 == b.rs1 && a.rs2 == b.rs2 && a.imm == b.imm &&
           a.uses1 == b.uses1 && a.uses2 == b.uses2 &&
           a.rd_we == b.rd_we && a.is_branch == b.is_branch &&
           a.is_jump == b.is_jump && a.is_load == b.is_load &&
           a.is_store == b.is_store && a.is_csr == b.is_csr &&
           a.is_fence == b.is_fence && a.is_fence_i == b.is_fence_i &&
           a.is_mret == b.is_mret && a.is_sret == b.is_sret &&
           a.is_wfi == b.is_wfi && a.illegal == b.illegal &&
           a.illegal_cause == b.illegal_cause &&
           a.illegal_tval == b.illegal_tval && a.mem_size == b.mem_size &&
           a.csr_op == b.csr_op && a.csr_addr == b.csr_addr &&
           a.csr_uimm == b.csr_uimm &&
           a.csr_uimm_valid == b.csr_uimm_valid &&
           a.fetch_exc_valid == b.fetch_exc_valid &&
           a.fetch_exc_cause == b.fetch_exc_cause &&
           a.fetch_exc_tval == b.fetch_exc_tval &&
           a.fetch_gen == b.fetch_gen && a.pred_taken == b.pred_taken &&
           a.pred_target == b.pred_target && a.pred_index == b.pred_index;
  }

  static bool same_req(const ReqSnap& a, const ReqSnap& b) {
    return a.valid == b.valid && a.is_store == b.is_store &&
           a.va == b.va && a.pa == b.pa && a.size == b.size &&
           a.byte_mask == b.byte_mask && a.wdata == b.wdata &&
           a.cacheable == b.cacheable && a.priv == b.priv &&
           a.id == b.id && a.gen == b.gen;
  }

  void apply(const Inputs& in) {
    dut->reset = in.reset;
    dut->redirect_valid = in.redirect;
    dut->redirect_target = in.target;
    dut->redirect_cause = 0;
    dut->redirect_flush_all = 1;
    dut->decoded_accept = in.accept;
    dut->req_gate = in.gate;
    dut->fault_mode = in.fault;
    dut->fault_delay_i = in.fault_delay;
    dut->req_observe_mask_xor = in.req_mask_xor;
    dut->resp_delay_i = in.delay;
  }

  Pre sample() const {
    Pre p{};
    p.dec_valid = dut->dec_valid;
    p.dec = snapshot();
    p.req.valid = dut->mem_req_valid_o;
    p.req.is_store = dut->mem_req_is_store_o;
    p.req.va = dut->mem_req_va_o;
    p.req.pa = dut->mem_req_pa_o;
    p.req.size = dut->mem_req_size_o;
    p.req.byte_mask = dut->mem_req_byte_mask_o;
    p.req.wdata = dut->mem_req_wdata_o;
    p.req.cacheable = dut->mem_req_cacheable_o;
    p.req.priv = dut->mem_req_priv_o;
    p.req.id = dut->mem_req_id_o;
    p.req.gen = dut->mem_req_gen_o;
    p.req_ready = dut->mem_req_ready_o;
    p.req_fire = p.req.valid && p.req_ready;
    p.resp_valid = dut->mem_resp_valid_o;
    p.resp_ready = dut->mem_resp_ready_o;
    p.resp_fire = p.resp_valid && p.resp_ready;
    p.resp_id = dut->mem_resp_id_o;
    p.resp_gen = dut->mem_resp_gen_o;
    p.resp_rdata = dut->mem_resp_rdata_o;
    p.resp_error = dut->mem_resp_error_o;
    return p;
  }

  Pre begin_cycle(const Inputs& in) {
    apply(in);
    dut->clk = 0; dut->eval();
    return sample();
  }

  void check_stability(const Pre& p, const Inputs& in) {
    const bool effective = in.redirect && ((in.target & 3u) == 0);
    if (held_dec_valid && !effective) {
      check(p.dec_valid, "held decoded valid disappeared");
      check(same_dec(p.dec, held_dec), "held decoded payload changed");
    }
    if (held_req_valid && !effective) {
      check_req(p.req.valid, "held request valid disappeared");
      check_req(same_req(p.req, held_req), "held request payload changed");
    }
  }

  void compare_decoded(const Pre& p, const ReqRec& result) {
    const DecodedSnap& d = p.dec;
    const Expected& e = result.expected;
    check(d.valid, "decoded valid missing");
    check(d.pc == result.pc, "decoded PC", d.pc, result.pc);
    check(d.instr == e.instr, "instruction word", d.instr, e.instr);
    check(d.fetch_gen == result.gen, "fetch generation", d.fetch_gen, result.gen);
    check(d.pred_taken == 0, "pred_taken", d.pred_taken, 0);
    check(d.pred_target == result.pc + 4u, "pred_target",
          d.pred_target, result.pc + 4u);
    check(d.pred_index == 0, "pred_index", d.pred_index, 0);

    if (e.fetch_exc) {
      check(!d.illegal, "fetch exception misclassified as illegal");
      check(d.fetch_exc_valid == 1, "fetch exception valid", d.fetch_exc_valid, 1);
      check(d.fetch_exc_cause == e.fetch_cause, "fetch exception cause",
            d.fetch_exc_cause, e.fetch_cause);
      check(d.fetch_exc_tval == e.fetch_tval, "fetch exception tval",
            d.fetch_exc_tval, e.fetch_tval);
      check(d.rd_we == 0, "fetch exception rd_we", d.rd_we, 0);
      return;
    }

    check(d.fetch_exc_valid == 0, "unexpected fetch exception",
          d.fetch_exc_valid, 0);
    check(d.illegal == (e.illegal != 0), "illegal", d.illegal, e.illegal);
    if (e.illegal) {
      check(d.illegal_cause == 2, "illegal cause", d.illegal_cause, 2);
      check(d.illegal_tval == e.instr, "illegal tval", d.illegal_tval, e.instr);
      check(d.rd_we == 0, "illegal rd_we", d.rd_we, 0);
      check(d.is_branch == 0 && d.is_jump == 0 && d.is_load == 0 &&
            d.is_store == 0 && d.is_csr == 0 && d.is_fence == 0 &&
            d.is_fence_i == 0 && d.is_mret == 0 && d.is_sret == 0 &&
            d.is_wfi == 0, "illegal side-effect flags");
      return;
    }

    check_op(d.op == e.op, "op", d.op, e.op);
    check(d.exec == e.exec, "exec", d.exec, e.exec);
    check(d.rd == e.rd, "rd", d.rd, e.rd);
    check(d.rs1 == e.rs1, "rs1", d.rs1, e.rs1);
    check(d.rs2 == e.rs2, "rs2", d.rs2, e.rs2);
    check(d.imm == e.imm, "imm", d.imm, e.imm);
    check(d.uses1 == (e.uses1 != 0), "uses_rs1", d.uses1, e.uses1);
    check(d.uses2 == (e.uses2 != 0), "uses_rs2", d.uses2, e.uses2);
    check(d.rd_we == (e.rd_we != 0), "rd_we", d.rd_we, e.rd_we);
    check(d.is_branch == (e.is_branch != 0), "is_branch",
          d.is_branch, e.is_branch);
    check(d.is_jump == (e.is_jump != 0), "is_jump", d.is_jump, e.is_jump);
    check(d.is_load == (e.is_load != 0), "is_load", d.is_load, e.is_load);
    check(d.is_store == (e.is_store != 0), "is_store", d.is_store, e.is_store);
    check(d.is_csr == (e.is_csr != 0), "is_csr", d.is_csr, e.is_csr);
    check(d.is_fence == (e.is_fence != 0), "is_fence", d.is_fence, e.is_fence);
    check(d.is_fence_i == (e.is_fence_i != 0), "is_fence_i",
          d.is_fence_i, e.is_fence_i);
    check(d.is_mret == (e.is_mret != 0), "is_mret", d.is_mret, e.is_mret);
    check(d.is_sret == (e.is_sret != 0), "is_sret", d.is_sret, e.is_sret);
    check(d.is_wfi == (e.is_wfi != 0), "is_wfi", d.is_wfi, e.is_wfi);
    check(d.mem_size == e.mem_size, "mem_size", d.mem_size, e.mem_size);
    check(d.csr_op == e.csr_op, "csr_op", d.csr_op, e.csr_op);
    check(d.csr_addr == e.csr_addr, "csr_addr", d.csr_addr, e.csr_addr);
    check(d.csr_uimm == e.csr_uimm, "csr_uimm", d.csr_uimm, e.csr_uimm);
    check(d.csr_uimm_valid == (e.csr_uimm_valid != 0), "csr_uimm_valid",
          d.csr_uimm_valid, e.csr_uimm_valid);
  }

  void monitor(const Pre& p, const Inputs& in) {
    const bool effective = in.redirect && ((in.target & 3u) == 0);
    if (p.req_fire) {
      ++total.requests;
      if (effective) fail("request accepted during effective redirect");
      uint32_t expected_pc = next_req_pc;
      if (inject_pc_skip && !pc_injected) expected_pc += 4u;
      check_pc(p.req.va == expected_pc, "request VA order",
               p.req.va, expected_pc);
      check_pc(p.req.pa == static_cast<uint64_t>(expected_pc),
               "request PA order", static_cast<uint32_t>(p.req.pa), expected_pc);
      if (inject_pc_skip && !pc_injected) pc_injected = true;
      check_req(!p.req.is_store, "fetch request is_store", p.req.is_store, 0);
      check_req(p.req.va == static_cast<uint32_t>(p.req.pa),
                "fetch request VA/PA mismatch", p.req.va,
                static_cast<uint32_t>(p.req.pa));
      check_req(p.req.size == 2, "fetch request size", p.req.size, 2);
      check_req(p.req.byte_mask == 0xfu, "fetch request byte_mask",
                p.req.byte_mask, 0xf);
      check_req(p.req.wdata == 0, "fetch request wdata", p.req.wdata, 0);
      check_req(p.req.cacheable, "fetch request cacheable");
      check_req(p.req.priv == 3, "fetch request privilege", p.req.priv, 3);
      ReqRec r{};
      r.pa = p.req.pa;
      r.pc = p.req.va;
      r.id = p.req.id;
      r.gen = p.req.gen;
      r.expected = expected_at(r.pc);
      r.cancelled = false;
      outstanding.push_back(r);
      next_req_pc += 4u;
    }

    if (p.resp_fire) {
      ++total.responses;
      if (outstanding.empty()) {
        fail("response without an accepted request");
      } else {
        const ReqRec& head = outstanding.front();
        const bool match = (p.resp_id == head.id) && (p.resp_gen == head.gen);
        if (!match) {
          ++total.orphan;
        } else {
          ++total.matched;
          check(p.resp_rdata == head.expected.instr, "response instruction",
                p.resp_rdata, head.expected.instr);
          check(p.resp_error == (head.expected.fetch_exc != 0),
                "response error flag", p.resp_error, head.expected.fetch_exc);
          if (!effective && !head.cancelled) {
            ResRec rr{};
            rr.pc = head.pc;
            rr.gen = p.resp_gen;
            rr.instr = p.resp_rdata;
            rr.fetch_exc = p.resp_error;
            results.push_back(rr);
          }
          outstanding.pop_front();
        }
      }
    }

    if (p.dec_valid && in.accept) {
      ++total.decode_accepts;
      if (results.empty()) {
        fail("decode accept without completed fetch result");
      } else {
        const ResRec rr = results.front();
        compare_decoded(p, ReqRec{0, rr.pc, 0, rr.gen, expected_at(rr.pc), false});
        ++total.accepted;
        if (rr.fetch_exc) ++total.fetch_exc;
        model_pc = rr.pc + 4u;
        results.pop_front();
      }
    }

    if (effective) {
      ++total.redirects;
      model_pc = in.target;
      next_req_pc = in.target;
      for (auto& r : outstanding) r.cancelled = true;
      results.clear();
    }
  }

  void commit(Pre& p, const Inputs& in) {
    check_stability(p, in);
    monitor(p, in);
    const bool effective = in.redirect && ((in.target & 3u) == 0);
    if (p.dec_valid && !in.accept && !effective) {
      held_dec_valid = true;
      held_dec = p.dec;
    } else {
      held_dec_valid = false;
    }
    if (p.req.valid && !p.req_fire && !effective) {
      held_req_valid = true;
      held_req = p.req;
    } else {
      held_req_valid = false;
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
  }

  void cycle(const Inputs& in) {
    Pre p = begin_cycle(in);
    commit(p, in);
  }

  void begin_stage(const char* name) {
    stage = name;
    stage_start = total;
    stage_error_start = errors;
  }

  void end_stage() {
    Stats d{};
    d.accepted = total.accepted - stage_start.accepted;
    d.requests = total.requests - stage_start.requests;
    d.responses = total.responses - stage_start.responses;
    d.matched = total.matched - stage_start.matched;
    d.orphan = total.orphan - stage_start.orphan;
    d.redirects = total.redirects - stage_start.redirects;
    d.decode_accepts = total.decode_accepts - stage_start.decode_accepts;
    d.fetch_exc = total.fetch_exc - stage_start.fetch_exc;
    check(d.requests == d.matched, "stage accepted-request completion",
          static_cast<uint32_t>(d.matched), static_cast<uint32_t>(d.requests));
    check(d.matched + d.orphan == d.responses,
          "stage matched/orphan accounting",
          static_cast<uint32_t>(d.matched + d.orphan),
          static_cast<uint32_t>(d.responses));
    const uint64_t derr = errors - stage_error_start;
    std::printf("P1-B_FRONTEND_STAGE name=%s accepted=%llu requests=%llu "
                "responses=%llu matched=%llu orphan=%llu redirects=%llu "
                "decode_accepts=%llu fetch_exc=%llu errors=%llu result=%s\n",
                stage.c_str(), (unsigned long long)d.accepted,
                (unsigned long long)d.requests,
                (unsigned long long)d.responses,
                (unsigned long long)d.matched,
                (unsigned long long)d.orphan,
                (unsigned long long)d.redirects,
                (unsigned long long)d.decode_accepts,
                (unsigned long long)d.fetch_exc,
                (unsigned long long)derr, derr == 0 ? "PASS" : "FAIL");
    if (derr != 0) std::printf("P1-B_FRONTEND_STAGE_FAIL: %s\n", stage.c_str());
  }

  void drain() {
    Inputs in{};
    in.gate = true;
    in.accept = 1;
    in.fault = 0;
    for (int i = 0; i < 200; ++i) {
      if (!dut->dec_valid && outstanding.empty() && results.empty() &&
          !dut->req_pending_o)
        break;
      cycle(in);
    }
    check(outstanding.empty(), "drain left accepted requests unfinished",
          static_cast<uint32_t>(outstanding.size()), 0);
    check(results.empty(), "drain left completed results unconsumed",
          static_cast<uint32_t>(results.size()), 0);
    check(!dut->dec_valid, "drain left decoded result valid");
  }

  void reset_frontend() {
    check(outstanding.empty(), "reset with accepted requests unfinished");
    check(results.empty(), "reset with completed results unconsumed");
    held_dec_valid = false;
    held_req_valid = false;
    Inputs in{};
    in.reset = true;
    in.gate = true;
    apply(in);
    for (int i = 0; i < 2; ++i) {
      dut->clk = 0; dut->eval();
      dut->clk = 1; dut->eval();
      dut->clk = 0; dut->eval();
    }
    if (dut->commit_valid_o || dut->commit_trap_valid_o)
      fail("frontend fabricated retire/trap during reset");
    if (dut->ram_write_o) fail("fetch wrote RAM during reset");
    in = Inputs{};
    apply(in);
    dut->eval();
    model_pc = RESET_VECTOR;
    next_req_pc = RESET_VECTOR;
  }

  void finish_stage() {
    drain();
    end_stage();
    reset_frontend();
  }

  void load_image_while_reset() {
    Inputs in{};
    in.reset = true;
    in.gate = true;
    apply(in);
    dut->load_valid = 1;
    for (int word = 0; word < 128 * 1024 / 4; ++word) {
      dut->load_word_addr = static_cast<uint16_t>(word);
      const uint32_t pc = RESET_VECTOR + 4u * static_cast<uint32_t>(word);
      auto it = image.find(pc);
      dut->load_data = (it == image.end()) ? NOP : it->second.instr;
      dut->clk = 0; dut->eval();
      dut->clk = 1; dut->eval();
      dut->clk = 0; dut->eval();
    }
    dut->load_valid = 0;
    in = Inputs{};
    apply(in);
    dut->clk = 0; dut->eval();
    model_pc = RESET_VECTOR;
  }

  void redirect_once(uint32_t target) {
    Inputs in{};
    in.redirect = true;
    in.target = target;
    cycle(in);
  }

  void wait_accept(uint32_t pc, const Inputs& base = Inputs{}) {
    Inputs in = base;
    in.accept = 0;
    for (int i = 0; i < 300; ++i) {
      if (dut->dec_valid) break;
      cycle(in);
    }
    check(dut->dec_valid, "timeout waiting for decoded fetch");
    check(dut->dec_pc == pc, "unexpected decoded PC", dut->dec_pc, pc);
    in.accept = 1;
    cycle(in);
    check(model_pc == pc + 4u, "model PC did not advance", model_pc, pc + 4u);
  }

  void last_word_test() {
    const uint32_t last = RAM_END - 4u;
    redirect_once(last);
    wait_accept(last);
    // Prevent the sequential successor at RAM_END from becoming an unrelated
    // post-last-word fetch; the dedicated out-of-range test covers that.
    redirect_once(RESET_VECTOR);
  }

  void backpressure_test(uint32_t target, uint8_t inject_mode) {
    begin_stage("directed-backpressure");
    redirect_once(target);
    Inputs in{};
    in.accept = 0;
    for (int i = 0; i < 300 && !dut->dec_valid; ++i) cycle(in);
    check(dut->dec_valid, "backpressure: no decoded result");
    const DecodedSnap held = snapshot();
    for (int i = 0; i < 4; ++i) {
      Pre p = begin_cycle(in);
      check(p.dec_valid, "backpressure: valid dropped");
      check(same_dec(p.dec, held), "backpressure: payload changed");
      commit(p, in);
    }
    uint32_t old_op = 0, old_imm = 0;
    if (inject_mode == 1 || inject_mode == 3) {
      old_op = image[target].op;
      image[target].op ^= 1u;
    }
    if (inject_mode == 2 || inject_mode == 3) {
      old_imm = image[target].imm;
      image[target].imm ^= 1u;
    }
    in.accept = 1;
    cycle(in);
    if (inject_mode == 1 || inject_mode == 3) image[target].op = old_op;
    if (inject_mode == 2 || inject_mode == 3) image[target].imm = old_imm;
    finish_stage();
  }

  void held_output_redirect_test(uint32_t target, uint32_t final_target) {
    begin_stage("directed-held-redirect-accept");
    redirect_once(target);
    Inputs in{};
    in.accept = 0;
    for (int i = 0; i < 300 && !dut->dec_valid; ++i) cycle(in);
    check(dut->dec_valid, "held redirect: no decoded result to hold");
    in.redirect = true;
    in.target = final_target;
    in.accept = 1;  // consumer is continuously ready on the redirect edge
    Pre p = begin_cycle(in);
    check(!p.dec_valid, "effective redirect did not suppress held decode valid");
    commit(p, in);
    in.redirect = false;
    in.accept = 0;
    for (int i = 0; i < 300 && !dut->dec_valid; ++i) cycle(in);
    check(dut->dec_valid, "held redirect: no new decode");
    check(dut->dec_pc == final_target, "held redirect: old result leaked",
          dut->dec_pc, final_target);
    in.accept = 1;
    cycle(in);
    finish_stage();
  }

  void request_payload_negative_test() {
    begin_stage("negative-request-stability");
    const uint32_t target = RESET_VECTOR + 4u * 8u;
    redirect_once(target);
    Inputs in{};
    in.accept = 0;
    in.gate = true;
    for (int i = 0; i < 20 && !dut->mem_req_valid_o; ++i) cycle(in);
    check(dut->mem_req_valid_o, "request stability negative: no request");
    for (int i = 0; i < 2; ++i) cycle(in);
    in.gate = false;
    in.req_mask_xor = true;  // observation fixture changes one held field
    Pre p = begin_cycle(in);
    commit(p, in);
    in.req_mask_xor = false;
    if (req_errors == 0) {
      std::printf("P1-B_FRONTEND_REQ_STABILITY_NOT_DETECTED\n");
      return;
    }
    std::printf("P1-B_FRONTEND_REQ_STABILITY_DETECTED errors=%llu\n",
                (unsigned long long)req_errors);
  }

  void request_stall_test(uint32_t target, uint32_t final_target) {
    begin_stage("directed-request-stall");
    redirect_once(target);
    Inputs in{};
    in.accept = 0;
    in.gate = true;
    for (int i = 0; i < 3; ++i) cycle(in);
    check(dut->mem_req_valid_o, "stalled request valid dropped");
    check(!dut->mem_req_ready_o, "stalled request claimed ready");
    in.redirect = true;
    in.target = final_target;
    cycle(in);  // cancel not-yet-accepted request
    in = Inputs{};
    in.accept = 0;
    for (int i = 0; i < 300 && !dut->dec_valid; ++i) cycle(in);
    check(dut->dec_valid, "request stall: final target did not decode");
    check(dut->dec_pc == final_target, "request stall: wrong final PC",
          dut->dec_pc, final_target);
    in.accept = 1;
    cycle(in);
    finish_stage();
  }

  void response_redirect_test(uint32_t target, uint32_t final_target) {
    begin_stage("directed-response-redirect");
    redirect_once(target);
    Inputs in{};
    in.accept = 0;
    in.delay = 3;
    for (int i = 0; i < 300; ++i) {
      cycle(in);
      if (dut->req_pending_o && !dut->mem_resp_valid_o) break;
    }
    check(dut->req_pending_o, "response redirect: no pending request");
    in.redirect = true;
    in.target = final_target;
    cycle(in);
    in.redirect = false;
    for (int i = 0; i < 300 && !dut->dec_valid; ++i) cycle(in);
    check(dut->dec_valid, "response redirect: no new decode");
    check(dut->dec_pc == final_target, "response redirect: old response visible",
          dut->dec_pc, final_target);
    in.accept = 1;
    cycle(in);
    finish_stage();
  }

  void same_cycle_redirect_test(uint32_t target, uint32_t final_target) {
    begin_stage("directed-same-cycle-redirect");
    redirect_once(target);
    Inputs in{};
    in.accept = 0;
    in.delay = 2;
    bool redirected = false;
    for (int i = 0; i < 300; ++i) {
      Pre p = begin_cycle(in);
      if (p.resp_fire) {
        in.redirect = true;
        in.target = final_target;
        apply(in);
        dut->eval();
        p = sample();
        redirected = true;
      }
      commit(p, in);
      if (redirected) break;
    }
    check(redirected, "same-cycle redirect not injected");
    in = Inputs{};
    in.accept = 0;
    for (int i = 0; i < 300 && !dut->dec_valid; ++i) cycle(in);
    check(dut->dec_valid, "same-cycle redirect: no new decode");
    check(dut->dec_pc == final_target, "same-cycle redirect: old result leaked",
          dut->dec_pc, final_target);
    in.accept = 1;
    cycle(in);
    finish_stage();
  }

  void fault_injection_test(uint32_t target, uint8_t mode, uint8_t delay) {
    const char* name = (mode == 1) ? "directed-fault-id-gen" :
                       (mode == 2) ? "directed-fault-id" : "directed-fault-gen";
    begin_stage(name);
    redirect_once(target);
    Inputs in{};
    in.accept = 0;
    in.fault = mode;
    in.fault_delay = delay;
    bool saw_orphan = false;
    for (int i = 0; i < 400; ++i) {
      const uint64_t before_orphan = total.orphan;
      cycle(in);
      if (total.orphan > before_orphan) saw_orphan = true;
      if (dut->dec_valid) break;
    }
    check(saw_orphan, "fault injection: wrong response not observed");
    check(dut->fault_used_o, "fault injector did not fire");
    check(dut->dec_valid, "fault injection: real response missing");
    check(dut->dec_pc == target, "fault injection: wrong PC", dut->dec_pc, target);
    in.accept = 1;
    in.fault = 0;
    in.fault_delay = 0;
    cycle(in);
    finish_stage();
  }

  void fetch_error_test() {
    const uint32_t bad = RAM_END;
    image[bad] = fetch_error_expected(bad);
    begin_stage("directed-fetch-error");
    redirect_once(bad);
    Inputs in{};
    in.accept = 0;
    for (int i = 0; i < 300 && !dut->dec_valid; ++i) cycle(in);
    check(dut->dec_valid, "fetch error: no result");
    check(dut->dec_fetch_exc_valid == 1, "fetch error flag");
    check(dut->dec_fetch_exc_cause == 1, "fetch error cause",
          dut->dec_fetch_exc_cause, 1);
    check(dut->dec_fetch_exc_tval == bad, "fetch error tval",
          dut->dec_fetch_exc_tval, bad);
    check(dut->dec_illegal == 0, "fetch error misclassified as illegal");
    in.accept = 1;
    cycle(in);
    in.accept = 1;
    for (int i = 0; i < 5; ++i) {
      cycle(in);
      check(!dut->dec_valid, "fetch error did not wait for redirect");
    }
    in.accept = 0;
    in.redirect = true;
    in.target = RESET_VECTOR;
    cycle(in);
    in = Inputs{};
    in.accept = 0;
    for (int i = 0; i < 300 && !dut->dec_valid; ++i) cycle(in);
    check(dut->dec_valid, "fetch error: did not resume");
    check(dut->dec_pc == RESET_VECTOR, "fetch error: resume PC",
          dut->dec_pc, RESET_VECTOR);
    in.accept = 1;
    cycle(in);
    finish_stage();
  }

  void illegal_target_with_response_test(uint32_t target, uint32_t final_target) {
    begin_stage("directed-illegal-target-pending");
    redirect_once(target);
    Inputs in{};
    in.accept = 0;
    in.delay = 2;
    bool injected = false;
    for (int i = 0; i < 300; ++i) {
      Pre p = begin_cycle(in);
      if (p.resp_fire) {
        in.redirect = true;
        in.target = final_target + 2u;  // deliberately misaligned
        apply(in);
        dut->eval();
        p = sample();
        injected = true;
      }
      commit(p, in);
      if (injected) break;
    }
    check(injected, "illegal target probe not injected");
    check(dut->redirect_error_o == 1, "misaligned redirect not rejected");
    in.redirect = false;
    in.target = final_target + 2u;
    in.accept = 0;
    for (int i = 0; i < 300 && !dut->dec_valid; ++i) cycle(in);
    check(dut->dec_valid, "illegal target cancelled a real response");
    check(dut->dec_pc == target, "illegal target changed result PC",
          dut->dec_pc, target);
    in.accept = 1;
    cycle(in);
    in = Inputs{};
    in.redirect = true;
    in.target = final_target;
    cycle(in);
    in = Inputs{};
    in.accept = 0;
    for (int i = 0; i < 300 && !dut->dec_valid; ++i) cycle(in);
    check(dut->dec_valid, "aligned redirect after illegal target failed");
    check(dut->dec_pc == final_target, "aligned redirect PC",
          dut->dec_pc, final_target);
    in.accept = 1;
    cycle(in);
    finish_stage();
  }

  void continuous_redirect_test(uint32_t a, uint32_t b, uint32_t c) {
    begin_stage("directed-continuous-redirect");
    Inputs in{};
    in.redirect = true;
    in.target = a; cycle(in);
    in.target = b; cycle(in);
    in.target = c; cycle(in);
    in.redirect = false;
    in.accept = 0;
    for (int i = 0; i < 300 && !dut->dec_valid; ++i) cycle(in);
    check(dut->dec_valid, "continuous redirect: no output");
    check(dut->dec_pc == c, "continuous redirect: old target leaked",
          dut->dec_pc, c);
    in.accept = 1;
    cycle(in);
    finish_stage();
  }

  void cancel_wrong_response_wrap_test(uint8_t mode) {
    const char* name = (mode == 1) ? "directed-cancel-wrong-wrap-id-gen" :
                       (mode == 2) ? "directed-cancel-wrong-wrap-id" :
                                     "directed-cancel-wrong-wrap-gen";
    begin_stage(name);
    Inputs in{};
    in.accept = 1;
    in.delay = 3;
    bool got_last_gen = false;
    for (int i = 0; i < 200; ++i) {
      Pre p = begin_cycle(in);
      const bool fire = p.req_fire;
      const uint32_t gen = p.req.gen;
      commit(p, in);
      if (fire && gen == ((1u << P1B_GEN_W) - 1u)) {
        got_last_gen = true;
        break;
      }
    }
    check(got_last_gen, "wrap cancel: last generation not accepted");
    in.fault = mode;    // arm only after the last-generation request
    in.fault_delay = 4; // hold the real response for several cycles
    in.redirect = true;
    in.target = RESET_VECTOR + 4u * 70u;
    cycle(in);  // cancels the accepted last-generation request
    in.redirect = false;
    uint64_t req_before = total.requests;
    bool saw_orphan = false;
    bool saw_real = false;
    for (int i = 0; i < 100; ++i) {
      const uint64_t before_orphan = total.orphan;
      const uint64_t before_matched = total.matched;
      cycle(in);
      if (total.orphan > before_orphan) saw_orphan = true;
      if (total.matched > before_matched) {
        saw_real = true;
        break;
      }
      if (saw_orphan) {
        check(dut->req_pending_o, "wrong response released pending identity");
        check(total.requests == req_before,
              "new request accepted before cancelled response drained",
              static_cast<uint32_t>(total.requests - req_before), 0);
      }
    }
    check(saw_orphan, "wrap cancel: wrong response not observed");
    check(saw_real, "wrap cancel: real response not completed");
    in.accept = 0;
    for (int i = 0; i < 20; ++i) cycle(in);
    in.redirect = false;
    in.accept = 0;
    for (int i = 0; i < 300 && !dut->dec_valid; ++i) cycle(in);
    check(dut->dec_valid, "wrap cancel: no post-drain decode");
    in.accept = 1;
    cycle(in);
    finish_stage();
  }
};

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vfrontend_tb_top* dut = new Vfrontend_tb_top;
  Tb tb(dut);
  bool mismatch = false, mismatch_other = false, mismatch_extra = false;
  bool hang = false, hang_ignore_term = false;
  bool inject_directed = false, inject_random0 = false;
  bool inject_directed_other = false, inject_directed_extra = false;
  bool inject_pc_skip = false, inject_req_stability = false;
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "+mismatch") == 0) mismatch = true;
    if (std::strcmp(argv[i], "+mismatch_other") == 0) mismatch_other = true;
    if (std::strcmp(argv[i], "+mismatch_extra") == 0) mismatch_extra = true;
    if (std::strcmp(argv[i], "+hang") == 0) hang = true;
    if (std::strcmp(argv[i], "+hang_ignore_term") == 0) hang_ignore_term = true;
    if (std::strcmp(argv[i], "+inject_directed") == 0) inject_directed = true;
    if (std::strcmp(argv[i], "+inject_random0") == 0) inject_random0 = true;
    if (std::strcmp(argv[i], "+inject_directed_other") == 0)
      inject_directed_other = true;
    if (std::strcmp(argv[i], "+inject_directed_extra") == 0)
      inject_directed_extra = true;
    if (std::strcmp(argv[i], "+inject_pc_skip") == 0) inject_pc_skip = true;
    if (std::strcmp(argv[i], "+inject_req_stability") == 0)
      inject_req_stability = true;
  }
  const bool mismatch_any = mismatch || mismatch_other || mismatch_extra;
  const bool inject_any = inject_directed || inject_random0 ||
                          inject_directed_other || inject_directed_extra;

  tb.setup_image();
  tb.load_image_while_reset();
  tb.inject_pc_skip = inject_pc_skip;
  tb.inject_req_stability = inject_req_stability;
  if (hang_ignore_term) std::signal(SIGTERM, SIG_IGN);
  if (hang || hang_ignore_term) {
    std::printf("P1-B_FRONTEND_TIMEOUT_PROBE\n");
    std::fflush(stdout);
    for (;;) { dut->clk = !dut->clk; dut->eval(); }
  }
  if (mismatch_any) {
    if (mismatch || mismatch_extra) tb.image[RESET_VECTOR].op ^= 1u;
    if (mismatch_other || mismatch_extra) tb.image[RESET_VECTOR].imm ^= 1u;
    tb.wait_accept(RESET_VECTOR);
    if (tb.op_errors > 0 && tb.other_errors == 0) {
      std::printf("P1-B_FRONTEND_NEGATIVE_OP_DETECTED op_errors=%llu\n",
                  (unsigned long long)tb.op_errors);
      delete dut;
      return 1;
    }
    if (tb.op_errors == 0) {
      std::printf("P1-B_FRONTEND_NEGATIVE_WRONG_REASON op_errors=0 "
                  "other_errors=%llu\n",
                  (unsigned long long)tb.other_errors);
      delete dut;
      return 2;
    }
    std::printf("P1-B_FRONTEND_NEGATIVE_EXTRA_ERRORS op_errors=%llu "
                "other_errors=%llu\n",
                (unsigned long long)tb.op_errors,
                (unsigned long long)tb.other_errors);
    delete dut;
    return 3;
  }
  if (inject_req_stability) {
    tb.request_payload_negative_test();
    if (tb.req_errors == 0) {
      std::printf("P1-B_FRONTEND_REQ_STABILITY_NOT_DETECTED\n");
      delete dut;
      return 2;
    }
    delete dut;
    return 1;
  }

  tb.begin_stage("basic-image");
  for (unsigned i = 0; i < kDecodeCaseCount; ++i)
    tb.wait_accept(kDecodeCases[i].pc);
  tb.last_word_test();
  tb.drain();
  tb.end_stage();
  tb.reset_frontend();
  std::printf("P1-B_FRONTEND_BASIC_PASS cases=%u\n", kDecodeCaseCount);

  uint8_t directed_mode = 0;
  if (inject_directed) directed_mode = 1;
  if (inject_directed_other) directed_mode = 2;
  if (inject_directed_extra) directed_mode = 3;
  tb.backpressure_test(RESET_VECTOR + 4u * 10u, directed_mode);
  tb.held_output_redirect_test(RESET_VECTOR + 4u * 11u,
                               RESET_VECTOR + 4u * 12u);
  tb.request_stall_test(RESET_VECTOR + 4u * 20u, RESET_VECTOR + 4u * 21u);
  tb.response_redirect_test(RESET_VECTOR + 4u * 30u, RESET_VECTOR + 4u * 31u);
  tb.same_cycle_redirect_test(RESET_VECTOR + 4u * 40u, RESET_VECTOR + 4u * 41u);
  tb.fault_injection_test(RESET_VECTOR + 4u * 50u, 1, 2);
  tb.fault_injection_test(RESET_VECTOR + 4u * 51u, 2, 2);
  tb.fault_injection_test(RESET_VECTOR + 4u * 52u, 3, 2);
  tb.fetch_error_test();
  tb.illegal_target_with_response_test(RESET_VECTOR + 4u * 60u,
                                      RESET_VECTOR + 4u * 61u);
  tb.continuous_redirect_test(RESET_VECTOR + 4u * 2u, RESET_VECTOR + 4u * 3u,
                              RESET_VECTOR + 4u * 4u);
  if (P1B_GEN_W <= 4) {
    tb.cancel_wrong_response_wrap_test(1);
    tb.cancel_wrong_response_wrap_test(2);
    tb.cancel_wrong_response_wrap_test(3);
  }

  // Forced generation wrap; with the default GEN_W=8 this also runs the full
  // 256-generation sequence, while the small build forces an early wrap.
  tb.begin_stage("directed-wrap");
  tb.reset_frontend();
  uint32_t last_gen = 0xffffffffu;
  bool wrapped = false;
  int wrap_fetches = (1 << P1B_GEN_W) + 8;
  if (wrap_fetches < 40) wrap_fetches = 40;
  for (int i = 0; i < wrap_fetches; ++i) {
    tb.wait_accept(tb.model_pc);
    const uint32_t g = dut->dec_fetch_gen;
    tb.check(g < (1u << P1B_GEN_W), "wrap: generation out of range",
             g, (1u << P1B_GEN_W) - 1);
    if (last_gen != 0xffffffffu && g < last_gen) wrapped = true;
    last_gen = g;
  }
  tb.check(wrapped, "wrap: generation did not wrap in selected fetch window");
  tb.drain();
  tb.end_stage();
  tb.reset_frontend();
  std::printf("P1-B_FRONTEND_WRAP_PASS gen_w=%d\n", P1B_GEN_W);

  // Three fixed random seeds, each at least 340 accepted results.
  static constexpr int kRandomAcceptsPerSeed = 340;
  const unsigned seeds[3] = {0x1a2b3c4du, 0x5e6f7a8bu, 0x9c0d1e2fu};
  uint64_t random_total = 0;
  for (unsigned s = 0; s < 3; ++s) {
    char name[32];
    std::snprintf(name, sizeof(name), "random-%u", s);
    tb.begin_stage(name);
    std::mt19937 rng(seeds[s]);
    int accepted_this = 0;
    bool injected = false;
    while (accepted_this < kRandomAcceptsPerSeed) {
      const bool redirect = (rng() % 100) < 5;
      const uint32_t target = RESET_VECTOR + 4u * (rng() % (kDecodeCaseCount + 20));
      const bool gate = (rng() % 100) < 10;
      const uint8_t accept = (rng() % 100) < 70 ? 1 : 0;
      const uint8_t delay = static_cast<uint8_t>(rng() % 4);
      Inputs in{};
      in.redirect = redirect;
      in.target = target;
      in.accept = redirect ? 0 : accept;
      in.gate = gate;
      in.delay = delay;
      Pre p = tb.begin_cycle(in);
      uint32_t old_op = 0;
      bool do_inject = inject_random0 && s == 0 && !injected &&
                       p.dec_valid && in.accept;
      if (do_inject) {
        old_op = tb.image[p.dec.pc].op;
        tb.image[p.dec.pc].op ^= 1u;
      }
      const uint64_t before = tb.total.accepted;
      tb.commit(p, in);
      if (do_inject) {
        tb.image[p.dec.pc].op = old_op;
        injected = true;
      }
      if (tb.total.accepted > before) ++accepted_this;
    }
    random_total += static_cast<uint64_t>(accepted_this);
    tb.drain();
    tb.end_stage();
    tb.reset_frontend();
  }
  tb.check(random_total >= 1020, "random run total accepts below 1020",
           static_cast<uint32_t>(random_total), 1020);
  std::printf("P1-B_FRONTEND_RANDOM_PASS seeds=3 accepted=%llu\n",
              (unsigned long long)random_total);
  tb.flow_complete = true;

  if (inject_pc_skip) {
    if (tb.pc_errors > 0 && tb.other_errors == tb.pc_errors) {
      std::printf("P1-B_FRONTEND_PC_MODEL_MISMATCH_DETECTED\n");
      delete dut;
      return 1;
    }
    if (tb.pc_errors == 0) {
      std::printf("P1-B_FRONTEND_PC_MODEL_NOT_DETECTED\n");
      delete dut;
      return 2;
    }
    std::printf("P1-B_FRONTEND_PC_MODEL_EXTRA_ERRORS pc_errors=%llu "
                "other_errors=%llu\n",
                (unsigned long long)tb.pc_errors,
                (unsigned long long)tb.other_errors);
    delete dut;
    return 3;
  }
  if (inject_any && tb.flow_complete) {
    if (tb.op_errors > 0 && tb.other_errors == 0) {
      std::printf("P1-B_FRONTEND_INJECTED_OP_PASS op_errors=%llu "
                  "other_errors=0\n",
                  (unsigned long long)tb.op_errors);
      delete dut;
      return 1;
    }
    if (tb.op_errors == 0) {
      std::printf("P1-B_FRONTEND_INJECTED_WRONG_REASON op_errors=0 "
                  "other_errors=%llu\n",
                  (unsigned long long)tb.other_errors);
      delete dut;
      return 2;
    }
    std::printf("P1-B_FRONTEND_INJECTED_EXTRA_ERRORS op_errors=%llu "
                "other_errors=%llu\n",
                (unsigned long long)tb.op_errors,
                (unsigned long long)tb.other_errors);
    delete dut;
    return 3;
  }
  if (tb.errors != 0) {
    std::printf("P1-B_FRONTEND_TEST_FAIL errors=%llu op_errors=%llu "
                "other_errors=%llu\n",
                (unsigned long long)tb.errors,
                (unsigned long long)tb.op_errors,
                (unsigned long long)tb.other_errors);
    delete dut;
    return 1;
  }
  std::printf("P1-B_FRONTEND_PASS accepted=%llu requests=%llu responses=%llu "
              "matched=%llu orphan=%llu decode=%llu fetch_exc=%llu "
              "redirects=%llu cycles=%llu\n",
              (unsigned long long)tb.total.accepted,
              (unsigned long long)tb.total.requests,
              (unsigned long long)tb.total.responses,
              (unsigned long long)tb.total.matched,
              (unsigned long long)tb.total.orphan,
              (unsigned long long)tb.total.decode_accepts,
              (unsigned long long)tb.total.fetch_exc,
              (unsigned long long)tb.total.redirects,
              (unsigned long long)tb.cycles);
  delete dut;
  return 0;
}
