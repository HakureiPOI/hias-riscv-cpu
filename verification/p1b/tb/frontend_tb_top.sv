// P1-B integration testbench wrapper: real fetch/decode + RAM bridge, with a
// test-only request stall and one-shot response fault injector.
module frontend_tb_top #(
    parameter int unsigned ID_W = 6,
    parameter int unsigned GEN_W = 8
) (
    input  logic        clk,
    input  logic        reset,

    input  logic        redirect_valid,
    input  logic [31:0] redirect_target,
    input  logic [1:0]  redirect_cause,
    input  logic        redirect_flush_all,

    input  logic        load_valid,
    input  logic [14:0] load_word_addr,
    input  logic [31:0] load_data,
    input  logic [1:0]  resp_delay_i,
    input  logic        req_gate,
    input  logic [1:0]  fault_mode,
    input  logic [2:0]  fault_delay_i,
    input  logic        req_observe_mask_xor,
    input  logic [1:0]  decoded_accept,

    output logic        dec_valid,
    output logic [31:0] dec_pc,
    output logic [31:0] dec_instr,
    output logic [4:0]  dec_op,
    output logic [5:0]  dec_exec,
    output logic [4:0]  dec_rd,
    output logic [4:0]  dec_rs1,
    output logic [4:0]  dec_rs2,
    output logic [31:0] dec_imm,
    output logic        dec_uses1,
    output logic        dec_uses2,
    output logic        dec_rd_we,
    output logic        dec_is_branch,
    output logic        dec_is_jump,
    output logic        dec_is_load,
    output logic        dec_is_store,
    output logic        dec_is_csr,
    output logic        dec_is_fence,
    output logic        dec_is_fence_i,
    output logic        dec_is_mret,
    output logic        dec_is_sret,
    output logic        dec_is_wfi,
    output logic        dec_illegal,
    output logic [4:0]  dec_illegal_cause,
    output logic [31:0] dec_illegal_tval,
    output logic [1:0]  dec_mem_size,
    output logic [1:0]  dec_csr_op,
    output logic [11:0] dec_csr_addr,
    output logic [4:0]  dec_csr_uimm,
    output logic        dec_csr_uimm_valid,
    output logic        dec_fetch_exc_valid,
    output logic [4:0]  dec_fetch_exc_cause,
    output logic [31:0] dec_fetch_exc_tval,
    output logic [7:0]  dec_fetch_gen,
    output logic        dec_pred_taken,
    output logic [31:0] dec_pred_target,
    output logic [7:0]  dec_pred_index,

    output logic        fetch_valid_o,
    output logic [31:0] fetch_pc_o,
    output logic [31:0] fetch_instr_o,
    output logic        fetch_exc_valid_o,
    output logic [7:0]  fetch_gen_o,
    output logic        req_pending_o,
    output logic        redirect_error_o,
    output logic        accept_error_o,
    output logic        mem_req_valid_o,
    output logic        mem_req_ready_o,
    output logic        mem_req_is_store_o,
    output logic [31:0] mem_req_va_o,
    output logic [33:0] mem_req_pa_o,
    output logic [1:0]  mem_req_size_o,
    output logic [3:0]  mem_req_byte_mask_o,
    output logic [31:0] mem_req_wdata_o,
    output logic        mem_req_cacheable_o,
    output logic [1:0]  mem_req_priv_o,
    output logic [5:0]  mem_req_id_o,
    output logic [7:0]  mem_req_gen_o,
    output logic        mem_resp_valid_o,
    output logic        mem_resp_ready_o,
    output logic [5:0]  mem_resp_id_o,
    output logic [7:0]  mem_resp_gen_o,
    output logic [31:0] mem_resp_rdata_o,
    output logic        mem_resp_error_o,
    output logic        ram_write_o,
    output logic        fault_used_o,
    output logic        commit_valid_o,
    output logic        commit_trap_valid_o
);

  import core_config_pkg::*;
  import core_types_pkg::*;

  mem_req_t  core_req;
  logic      core_req_ready;
  mem_resp_t core_resp;
  logic      core_resp_ready;
  mem_req_t  bridge_req;
  logic      bridge_req_ready;
  mem_resp_t bridge_resp;
  logic      bridge_resp_ready;
  /* verilator lint_off UNUSEDSIGNAL */
  decoded_slot_t decoded;
  /* verilator lint_on UNUSEDSIGNAL */
  /* verilator lint_off UNUSEDSIGNAL */
  logic           decoded_held_unused;
  /* verilator lint_on UNUSEDSIGNAL */
  logic           decoded_valid;
  redirect_t      redirect;
  commit_bundle_t commit_unused;

  always_comb begin
    redirect = '0;
    redirect.valid = redirect_valid;
    redirect.target_pc = redirect_target;
    redirect.cause = flush_cause_e'(redirect_cause);
    redirect.flush_all = redirect_flush_all;
  end

  // Test-only request stall: hide valid from the bridge and hide ready from
  // the core, so neither side believes the request was accepted.
  always_comb begin
    bridge_req = core_req;
    bridge_req.valid = core_req.valid && !req_gate;
  end
  assign core_req_ready = bridge_req_ready && !req_gate;

  p1_frontend_core #(.ID_W(ID_W), .GEN_W(GEN_W)) u_core (
      .clk(clk), .reset(reset), .redirect_i(redirect),
      .mem_req_o(core_req), .mem_req_ready_i(core_req_ready),
      .mem_resp_i(core_resp), .mem_resp_ready_o(core_resp_ready),
      .decoded_o(decoded), .decoded_valid_o(decoded_valid),
      .decoded_held_o(decoded_held_unused),
      .decoded_accept_i(prefix_accept_t'(decoded_accept)),
      .redirect_error_o(redirect_error_o), .accept_error_o(accept_error_o),
      .fetch_valid_o(fetch_valid_o), .fetch_pc_o(fetch_pc_o),
      .fetch_instr_o(fetch_instr_o), .fetch_exc_valid_o(fetch_exc_valid_o),
      .fetch_gen_o(fetch_gen_o), .req_pending_o(req_pending_o));

  ram_bridge u_bridge (
      .clk(clk), .reset(reset),
      .load_valid(load_valid), .load_word_addr(load_word_addr),
      .load_data(load_data), .flush_i(1'b0),
      .req_i(bridge_req), .req_ready_o(bridge_req_ready),
      .resp_o(bridge_resp), .resp_ready_i(bridge_resp_ready),
      .resp_delay_i(resp_delay_i), .ram_write_o(ram_write_o));

  // One-shot response fault: inject a wrong ID/gen, hold the real response
  // for a configurable number of cycles, then deliver it. Production bridge
  // and RAM are untouched.
  logic      saved_valid_q;
  logic      fault_used_q;
  logic [2:0] fault_delay_q;
  mem_resp_t saved_q;

  always_comb begin
    core_resp = bridge_resp;
    bridge_resp_ready = core_resp_ready;
    fault_used_o = fault_used_q;
    if (fault_mode != 2'd0) begin
      if (saved_valid_q) begin
        bridge_resp_ready = 1'b1;
        if (fault_delay_q == 3'd0) begin
          core_resp = saved_q;
          core_resp.valid = 1'b1;
        end else begin
          core_resp = '0;
          core_resp.valid = 1'b0;
        end
      end else if (bridge_resp.valid && !fault_used_q) begin
        core_resp = bridge_resp;
        if (fault_mode == 2'd1 || fault_mode == 2'd2)
          core_resp.req_id = bridge_resp.req_id ^ 6'h1;
        if (fault_mode == 2'd1 || fault_mode == 2'd3)
          core_resp.gen = bridge_resp.gen ^ 8'h1;
        core_resp.valid = 1'b1;
        bridge_resp_ready = 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      saved_valid_q <= 1'b0;
      fault_used_q <= 1'b0;
      fault_delay_q <= '0;
      saved_q <= '0;
    end else if (fault_mode != 2'd0) begin
      if (bridge_resp.valid && !fault_used_q && !saved_valid_q) begin
        saved_q <= bridge_resp;
        saved_valid_q <= 1'b1;
        fault_used_q <= 1'b1;
        fault_delay_q <= fault_delay_i;
      end else if (saved_valid_q) begin
        if (fault_delay_q != 3'd0)
          fault_delay_q <= fault_delay_q - 3'd1;
        else
          saved_valid_q <= 1'b0;
      end
    end else begin
      saved_valid_q <= 1'b0;
      fault_used_q <= 1'b0;
      fault_delay_q <= '0;
    end
  end

  assign mem_req_valid_o = core_req.valid;
  assign mem_req_ready_o = core_req_ready;
  assign mem_req_is_store_o = core_req.is_store;
  assign mem_req_va_o = core_req.va;
  assign mem_req_pa_o = core_req.pa;
  assign mem_req_size_o = core_req.size;
  // Observation-only fixture hook; production core_req/bridge request is not
  // modified. Used solely to prove the monitor rejects a changed held field.
  assign mem_req_byte_mask_o = core_req.byte_mask ^ {3'b000, req_observe_mask_xor};
  assign mem_req_wdata_o = core_req.wdata;
  assign mem_req_cacheable_o = core_req.cacheable;
  assign mem_req_priv_o = core_req.priv;
  assign mem_req_id_o = core_req.req_id;
  assign mem_req_gen_o = core_req.gen;
  assign mem_resp_valid_o = core_resp.valid;
  assign mem_resp_ready_o = core_resp_ready;
  assign mem_resp_id_o = core_resp.req_id;
  assign mem_resp_gen_o = core_resp.gen;
  assign mem_resp_rdata_o = core_resp.rdata;
  assign mem_resp_error_o = core_resp.error;

  assign dec_valid = decoded_valid;
  assign dec_pc = decoded.pc;
  assign dec_instr = decoded.instr;
  assign dec_op = decoded.op;
  assign dec_exec = decoded.exec_op;
  assign dec_rd = decoded.rd;
  assign dec_rs1 = decoded.rs1;
  assign dec_rs2 = decoded.rs2;
  assign dec_imm = decoded.imm;
  assign dec_uses1 = decoded.uses_rs1;
  assign dec_uses2 = decoded.uses_rs2;
  assign dec_rd_we = decoded.rd_we;
  assign dec_is_branch = decoded.is_branch;
  assign dec_is_jump = decoded.is_jump;
  assign dec_is_load = decoded.is_load;
  assign dec_is_store = decoded.is_store;
  assign dec_is_csr = decoded.is_csr;
  assign dec_is_fence = decoded.is_fence;
  assign dec_is_fence_i = decoded.is_fence_i;
  assign dec_is_mret = decoded.is_mret;
  assign dec_is_sret = decoded.is_sret;
  assign dec_is_wfi = decoded.is_wfi;
  assign dec_illegal = decoded.illegal;
  assign dec_illegal_cause = decoded.illegal_cause;
  assign dec_illegal_tval = decoded.illegal_tval;
  assign dec_mem_size = decoded.mem_size;
  assign dec_csr_op = decoded.csr_op;
  assign dec_csr_addr = decoded.csr_addr;
  assign dec_csr_uimm = decoded.csr_uimm;
  assign dec_csr_uimm_valid = decoded.csr_uimm_valid;
  assign dec_fetch_exc_valid = decoded.fetch_exc_valid;
  assign dec_fetch_exc_cause = decoded.fetch_exc_cause;
  assign dec_fetch_exc_tval = decoded.fetch_exc_tval;
  assign dec_fetch_gen = decoded.fetch_gen;
  assign dec_pred_taken = decoded.pred_taken;
  assign dec_pred_target = decoded.pred_target;
  assign dec_pred_index = decoded.pred_index;

  assign commit_unused = '0;
  assign commit_valid_o = 1'b0;
  assign commit_trap_valid_o = 1'b0;

endmodule
