// P1-C integer core integration: accepted P1-B frontend + real 128 KiB RAM,
// one-instruction sequential ARF/ALU backend and real commit events.
module p1_integer_top (
    input  logic                          clk,
    input  logic                          reset,
    input  logic                          accept_stall_i,
    input  logic                          req_gate_i,
    input  logic                          load_valid,
    input  logic [14:0]                   load_word_addr,
    input  logic [31:0]                   load_data,
    input  logic [1:0]                    resp_delay_i,

    output core_types_pkg::commit_bundle_t commit_o,
    output logic                          fault_valid_o,
    output logic [1:0]                    fault_kind_o,
    output logic [31:0]                   fault_pc_o,
    output logic [31:0]                   fault_instr_o,
    output logic [4:0]                    fault_cause_o,
    output logic [31:0]                   fault_tval_o,
    output core_types_pkg::rob_token_t    fault_token_o,
    output logic [7:0]                    fault_fetch_gen_o,

    output logic [31:0]                   arf_debug_o [0:31],

    output logic                          decoded_valid_o,
    output logic                          decoded_held_o,
    output logic [31:0]                   decoded_pc_o,
    output logic [31:0]                   decoded_instr_o,
    output logic                          redirect_valid_o,
    output logic [31:0]                   redirect_target_o,
    output logic                          req_pending_o,
    output logic                          mem_req_valid_o,
    output logic                          mem_req_ready_o,
    output logic [31:0]                   mem_req_va_o,
    output logic [7:0]                    mem_req_gen_o,
    output logic                          mem_resp_valid_o,
    output logic                          mem_resp_ready_o,
    output logic                          ram_write_o
);

  import core_config_pkg::*;
  import core_types_pkg::*;

  decoded_slot_t decoded;
  logic          decoded_valid;
  logic          decoded_held;
  prefix_accept_t decoded_accept;
  redirect_t     redirect;
  mem_req_t      req;
  mem_req_t      bridge_req;
  logic          req_ready;
  logic          bridge_req_ready;
  mem_resp_t     resp;
  logic          resp_ready;

  /* verilator lint_off PINCONNECTEMPTY */
  p1_frontend_core u_frontend (
      .clk(clk), .reset(reset), .redirect_i(redirect),
      .mem_req_o(req), .mem_req_ready_i(req_ready),
      .mem_resp_i(resp), .mem_resp_ready_o(resp_ready),
      .decoded_o(decoded), .decoded_valid_o(decoded_valid),
      .decoded_held_o(decoded_held),
      .decoded_accept_i(decoded_accept),
      .redirect_error_o(), .accept_error_o(),
      .fetch_valid_o(), .fetch_pc_o(), .fetch_instr_o(),
      .fetch_exc_valid_o(), .fetch_gen_o(), .req_pending_o(req_pending_o));
  /* verilator lint_on PINCONNECTEMPTY */

  p1_integer_core u_core (
      .clk(clk), .reset(reset), .accept_stall_i(accept_stall_i),
      .decoded_i(decoded), .decoded_valid_i(decoded_valid),
      .decoded_accept_o(decoded_accept),
      .redirect_o(redirect), .commit_o(commit_o),
      .fault_valid_o(fault_valid_o), .fault_kind_o(fault_kind_o),
      .fault_pc_o(fault_pc_o), .fault_instr_o(fault_instr_o),
      .fault_cause_o(fault_cause_o), .fault_tval_o(fault_tval_o),
      .fault_token_o(fault_token_o), .fault_fetch_gen_o(fault_fetch_gen_o),
      .arf_debug_o(arf_debug_o));

  // Test-only request gate. It hides valid from the bridge and ready from the
  // core on the same real request; the production bridge/RAM are unchanged.
  always_comb begin
    bridge_req = req;
    bridge_req.valid = req.valid && !req_gate_i;
  end
  assign req_ready = bridge_req_ready && !req_gate_i;

  ram_bridge u_bridge (
      .clk(clk), .reset(reset),
      .load_valid(load_valid), .load_word_addr(load_word_addr),
      .load_data(load_data), .flush_i(1'b0),
      .req_i(bridge_req), .req_ready_o(bridge_req_ready),
      .resp_o(resp), .resp_ready_i(resp_ready),
      .resp_delay_i(resp_delay_i), .ram_write_o(ram_write_o));

  assign decoded_valid_o = decoded_valid;
  assign decoded_held_o = decoded_held;
  assign decoded_pc_o = decoded.pc;
  assign decoded_instr_o = decoded.instr;
  assign redirect_valid_o = redirect.valid;
  assign redirect_target_o = redirect.target_pc;
  assign mem_req_valid_o = req.valid;
  assign mem_req_ready_o = req_ready;
  assign mem_req_va_o = req.va;
  assign mem_req_gen_o = req.gen;
  assign mem_resp_valid_o = resp.valid;
  assign mem_resp_ready_o = resp_ready;

endmodule
