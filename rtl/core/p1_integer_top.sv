// P1-D integer core integration: P1-B frontend, shared fetch/data arbiter,
// real 128 KiB RAM/bridge, ARF/ALU and Load/Store backend.
module p1_integer_top (
    input  logic                          clk,
    input  logic                          reset,
    input  logic                          accept_stall_i,
    input  logic                          req_gate_i,
    input  logic                          lsu_gate_i,
    input  logic                          force_lsu_error_i,
    input  logic                          load_valid,
    input  logic [14:0]                   load_word_addr,
    input  logic [31:0]                   load_data,
    input  logic [1:0]                    resp_delay_i,

    output core_types_pkg::commit_bundle_t commit_o,
    output logic                          fault_valid_o,
    output logic [2:0]                    fault_kind_o,
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
    output logic                          ram_write_o,
    output logic                          fetch_req_valid_o,
    output logic                          fetch_req_ready_o,
    output logic [31:0]                   fetch_req_va_o,
    output logic [7:0]                    fetch_req_gen_o,
    output logic                          lsu_req_valid_o,
    output logic                          lsu_req_ready_o,
    output logic                          lsu_req_is_store_o,
    output logic [31:0]                   lsu_req_va_o,
    output logic [33:0]                   lsu_req_pa_o,
    output logic [1:0]                    lsu_req_size_o,
    output logic [3:0]                    lsu_req_mask_o,
    output logic [31:0]                   lsu_req_wdata_o,
    output logic [5:0]                    lsu_req_id_o,
    output logic [7:0]                    lsu_req_gen_o,
    output logic                          lsu_resp_valid_o,
    output logic                          lsu_resp_ready_o,
    output logic                          fetch_resp_valid_o,
    output logic                          fetch_outstanding_o,
    output logic                          lsu_outstanding_o
);

  import core_config_pkg::*;
  import core_types_pkg::*;

  decoded_slot_t decoded;
  logic decoded_valid, decoded_held;
  prefix_accept_t decoded_accept;
  redirect_t redirect;

  mem_req_t fetch_req, fetch_req_g;
  logic fetch_req_ready;
  mem_resp_t fetch_resp;
  logic fetch_resp_ready;

  mem_req_t lsu_req, lsu_req_g;
  logic lsu_req_ready;
  mem_resp_t lsu_resp_raw;
  mem_resp_t lsu_resp;
  logic lsu_resp_ready;

  mem_req_t bus_req;
  logic bus_req_ready;
  mem_resp_t bus_resp;
  logic bus_resp_ready;

  /* verilator lint_off PINCONNECTEMPTY */
  p1_frontend_core u_frontend (
      .clk(clk), .reset(reset), .redirect_i(redirect),
      .mem_req_o(fetch_req), .mem_req_ready_i(fetch_req_ready),
      .mem_resp_i(fetch_resp), .mem_resp_ready_o(fetch_resp_ready),
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
      .lsu_req_o(lsu_req), .lsu_req_ready_i(lsu_req_ready),
      .lsu_resp_i(lsu_resp), .lsu_resp_ready_o(lsu_resp_ready),
      .redirect_o(redirect), .commit_o(commit_o),
      .fault_valid_o(fault_valid_o), .fault_kind_o(fault_kind_o),
      .fault_pc_o(fault_pc_o), .fault_instr_o(fault_instr_o),
      .fault_cause_o(fault_cause_o), .fault_tval_o(fault_tval_o),
      .fault_token_o(fault_token_o), .fault_fetch_gen_o(fault_fetch_gen_o),
      .arf_debug_o(arf_debug_o));

  // Test-only gates preserve the old frontend gate behavior and allow the
  // data client to be held independently. Production RAM/bridge are untouched.
  always_comb begin
    lsu_resp = lsu_resp_raw;
    if (force_lsu_error_i && lsu_resp_raw.valid) begin
      lsu_resp.error = 1'b1;
      lsu_resp.error_cause = EXC_LOAD_ACCESS_FAULT;
    end
  end

  always_comb begin
    fetch_req_g = fetch_req;
    fetch_req_g.valid = fetch_req.valid && !req_gate_i;
  end
  // fetch_req_ready is the arbiter's ready masked by the gate.
  logic fetch_req_ready_arb;
  assign fetch_req_ready = fetch_req_ready_arb && !req_gate_i;

  always_comb begin
    lsu_req_g = lsu_req;
    lsu_req_g.valid = lsu_req.valid && !lsu_gate_i;
  end
  logic lsu_req_ready_arb;
  assign lsu_req_ready = lsu_req_ready_arb && !lsu_gate_i;

  p1_bus_arbiter u_arb (
      .clk(clk), .reset(reset),
      .fetch_req_i(fetch_req_g), .fetch_req_ready_o(fetch_req_ready_arb),
      .fetch_resp_o(fetch_resp), .fetch_resp_ready_i(fetch_resp_ready),
      .lsu_req_i(lsu_req_g), .lsu_req_ready_o(lsu_req_ready_arb),
      .lsu_resp_o(lsu_resp_raw), .lsu_resp_ready_i(lsu_resp_ready),
      .bus_req_o(bus_req), .bus_req_ready_i(bus_req_ready),
      .bus_resp_i(bus_resp), .bus_resp_ready_o(bus_resp_ready),
      .fetch_outstanding_o(fetch_outstanding_o),
      .lsu_outstanding_o(lsu_outstanding_o));

  ram_bridge u_bridge (
      .clk(clk), .reset(reset),
      .load_valid(load_valid), .load_word_addr(load_word_addr),
      .load_data(load_data), .flush_i(1'b0),
      .req_i(bus_req), .req_ready_o(bus_req_ready),
      .resp_o(bus_resp), .resp_ready_i(bus_resp_ready),
      .resp_delay_i(resp_delay_i), .ram_write_o(ram_write_o));

  assign decoded_valid_o = decoded_valid;
  assign decoded_held_o = decoded_held;
  assign decoded_pc_o = decoded.pc;
  assign decoded_instr_o = decoded.instr;
  assign redirect_valid_o = redirect.valid;
  assign redirect_target_o = redirect.target_pc;
  assign mem_req_valid_o = bus_req.valid;
  assign mem_req_ready_o = bus_req_ready;
  assign mem_req_va_o = bus_req.va;
  assign mem_req_gen_o = bus_req.gen;
  assign mem_resp_valid_o = bus_resp.valid;
  assign mem_resp_ready_o = bus_resp_ready;
  assign fetch_req_valid_o = fetch_req.valid;
  assign fetch_req_ready_o = fetch_req_ready;
  assign fetch_req_va_o = fetch_req.va;
  assign fetch_req_gen_o = fetch_req.gen;
  assign lsu_req_valid_o = lsu_req.valid;
  assign lsu_req_ready_o = lsu_req_ready;
  assign lsu_req_is_store_o = lsu_req.is_store;
  assign lsu_req_va_o = lsu_req.va;
  assign lsu_req_pa_o = lsu_req.pa;
  assign lsu_req_size_o = lsu_req.size;
  assign lsu_req_mask_o = lsu_req.byte_mask;
  assign lsu_req_wdata_o = lsu_req.wdata;
  assign lsu_req_id_o = lsu_req.req_id;
  assign lsu_req_gen_o = lsu_req.gen;
  assign lsu_resp_valid_o = lsu_resp.valid;
  assign lsu_resp_ready_o = lsu_resp_ready;
  assign fetch_resp_valid_o = fetch_resp.valid;

endmodule
