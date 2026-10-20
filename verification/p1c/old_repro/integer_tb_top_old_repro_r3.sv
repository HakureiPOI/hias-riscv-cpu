module integer_tb_top (
    input  logic        clk,
    input  logic        reset,
    input  logic        accept_stall_i,
    input  logic        req_gate_i,
    input  logic        load_valid,
    input  logic [14:0] load_word_addr,
    input  logic [31:0] load_data,
    input  logic [1:0]  resp_delay_i,

    output logic [1:0]  commit_slot_valid,
    output logic        commit_valid,
    output logic [31:0] commit_pc,
    output logic [31:0] commit_instr,
    output logic [31:0] commit_next_pc,
    output logic [4:0]  commit_token_idx,
    output logic [7:0]  commit_token_gen,
    output logic [1:0]  commit_priv,
    output logic        commit_rd_we,
    output logic [4:0]  commit_rd,
    output logic [31:0] commit_rd_data,
    output logic        commit_csr_valid,
    output logic        commit_csr_rd_valid,
    output logic        commit_csr_wr_valid,
    output logic [11:0] commit_csr_addr,
    output logic [31:0] commit_csr_wdata,
    output logic [31:0] commit_csr_rdata,
    output logic        commit_mem_valid,
    output logic        commit_mem_we,
    output logic [31:0] commit_mem_va,
    output logic [33:0] commit_mem_pa,
    output logic [1:0]  commit_mem_size,
    output logic [3:0]  commit_mem_mask,
    output logic [31:0] commit_mem_wdata,
    output logic [31:0] commit_mem_rdata,
    output logic        commit_trap_valid,

    output logic        fault_valid,
    output logic [1:0]  fault_kind,
    output logic [31:0] fault_pc,
    output logic [31:0] fault_instr,
    output logic [4:0]  fault_cause,
    output logic [31:0] fault_tval,
    output logic [4:0]  fault_token_idx,
    output logic [7:0]  fault_token_gen,
    output logic [7:0]  fault_fetch_gen,

    output logic [31:0] arf_debug_o [0:31],
    output logic        decoded_valid,
    output logic        decoded_held,
    output logic [31:0] decoded_pc,
    output logic [31:0] decoded_instr,
    output logic        redirect_valid,
    output logic [31:0] redirect_target,
    output logic        req_pending,
    output logic        mem_req_valid,
    output logic        mem_req_ready,
    output logic [31:0] mem_req_va,
    output logic [7:0]  mem_req_gen,
    output logic        mem_resp_valid,
    output logic        mem_resp_ready,
    output logic        ram_write
);
  import core_types_pkg::*;
  logic [4:0] fault_cause_raw;

  // Old-checker reproduction fixture: corrupt the observed fault cause while
  // leaving the actual RTL metadata correct.
  always_comb fault_cause = fault_cause_raw ^ (fault_valid ? 5'd1 : 5'd0);

  /* verilator lint_off UNUSEDSIGNAL */
  commit_bundle_t commit;
  /* verilator lint_on UNUSEDSIGNAL */
  rob_token_t fault_token;
  p1_integer_top u_top (
      .clk(clk), .reset(reset), .accept_stall_i(accept_stall_i),
      .req_gate_i(req_gate_i), .load_valid(load_valid), .load_word_addr(load_word_addr),
      .load_data(load_data), .resp_delay_i(resp_delay_i),
      .commit_o(commit), .fault_valid_o(fault_valid), .fault_kind_o(fault_kind),
      .fault_pc_o(fault_pc), .fault_instr_o(fault_instr),
      .fault_cause_o(fault_cause_raw), .fault_tval_o(fault_tval),
      .fault_token_o(fault_token), .fault_fetch_gen_o(fault_fetch_gen),
      .arf_debug_o(arf_debug_o), .decoded_valid_o(decoded_valid),
      .decoded_held_o(decoded_held),
      .decoded_pc_o(decoded_pc), .decoded_instr_o(decoded_instr),
      .redirect_valid_o(redirect_valid),
      .redirect_target_o(redirect_target), .req_pending_o(req_pending),
      .mem_req_valid_o(mem_req_valid), .mem_req_ready_o(mem_req_ready),
      .mem_req_va_o(mem_req_va), .mem_req_gen_o(mem_req_gen),
      .mem_resp_valid_o(mem_resp_valid), .mem_resp_ready_o(mem_resp_ready),
      .ram_write_o(ram_write));

  assign commit_slot_valid = commit.slot_valid;
  assign commit_valid = commit.slot_valid[0];
  assign commit_pc = commit.slot[0].pc;
  assign commit_instr = commit.slot[0].instr;
  assign commit_next_pc = commit.slot[0].next_pc;
  assign commit_token_idx = commit.slot[0].token.idx;
  assign commit_token_gen = commit.slot[0].token.gen;
  assign commit_priv = commit.slot[0].priv;
  assign commit_rd_we = commit.slot[0].rd_we;
  assign commit_rd = commit.slot[0].rd;
  assign commit_rd_data = commit.slot[0].rd_data;
  assign commit_csr_valid = 1'b0;
  assign commit_csr_rd_valid = commit.slot[0].csr_rd_valid;
  assign commit_csr_wr_valid = commit.slot[0].csr_wr_valid;
  assign commit_csr_addr = commit.slot[0].csr_addr;
  assign commit_csr_wdata = commit.slot[0].csr_wdata;
  assign commit_csr_rdata = commit.slot[0].csr_rdata;
  assign commit_mem_valid = commit.slot[0].mem_valid;
  assign commit_mem_we = commit.slot[0].mem_we;
  assign commit_mem_va = commit.slot[0].mem_va;
  assign commit_mem_pa = commit.slot[0].mem_pa;
  assign commit_mem_size = commit.slot[0].mem_size;
  assign commit_mem_mask = commit.slot[0].mem_mask;
  assign commit_mem_wdata = commit.slot[0].mem_wdata;
  assign commit_mem_rdata = commit.slot[0].mem_rdata;
  assign commit_trap_valid = commit.trap_valid;
  assign fault_token_idx = fault_token.idx;
  assign fault_token_gen = fault_token.gen;
endmodule
