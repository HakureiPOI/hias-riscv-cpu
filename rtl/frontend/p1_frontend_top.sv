// P1-B integrated frontend: fetch/decode + real 128 KiB RAM and bridge.
// No instruction execution, no retirement/Trap events.
module p1_frontend_top #(
    parameter int unsigned ID_W = 6,
    parameter int unsigned GEN_W = 8
) (
    input  logic                          clk,
    input  logic                          reset,
    input  core_types_pkg::redirect_t     redirect_i,
    input  logic                          load_valid,
    input  logic [14:0]                   load_word_addr,
    input  logic [31:0]                   load_data,
    input  logic [1:0]                    resp_delay_i,

    output core_types_pkg::decoded_slot_t decoded_o,
    output logic                          decoded_valid_o,
    input  core_types_pkg::prefix_accept_t decoded_accept_i,
    output core_types_pkg::commit_bundle_t commit_o,

    output logic                          redirect_error_o,
    output logic                          accept_error_o,
    output logic                          fetch_valid_o,
    output logic [31:0]                   fetch_pc_o,
    output logic [31:0]                   fetch_instr_o,
    output logic                          fetch_exc_valid_o,
    output logic [7:0]                    fetch_gen_o,
    output logic                          req_pending_o,
    output logic                          mem_req_valid_o,
    output logic                          mem_req_ready_o,
    output logic                          mem_resp_valid_o,
    output logic                          mem_resp_ready_o,
    output logic                          ram_write_o
);

  import core_config_pkg::*;
  import core_types_pkg::*;

  mem_req_t  req;
  logic      req_ready;
  /* verilator lint_off UNUSEDSIGNAL */
  logic      decoded_held_unused;
  /* verilator lint_on UNUSEDSIGNAL */
  mem_resp_t resp;
  logic      resp_ready;

  p1_frontend_core #(.ID_W(ID_W), .GEN_W(GEN_W)) u_core (
      .clk(clk), .reset(reset), .redirect_i(redirect_i),
      .mem_req_o(req), .mem_req_ready_i(req_ready),
      .mem_resp_i(resp), .mem_resp_ready_o(resp_ready),
      .decoded_o(decoded_o), .decoded_valid_o(decoded_valid_o),
      .decoded_held_o(decoded_held_unused),
      .decoded_accept_i(decoded_accept_i),
      .redirect_error_o(redirect_error_o), .accept_error_o(accept_error_o),
      .fetch_valid_o(fetch_valid_o), .fetch_pc_o(fetch_pc_o),
      .fetch_instr_o(fetch_instr_o), .fetch_exc_valid_o(fetch_exc_valid_o),
      .fetch_gen_o(fetch_gen_o), .req_pending_o(req_pending_o));

  ram_bridge u_bridge (
      .clk(clk), .reset(reset),
      .load_valid(load_valid), .load_word_addr(load_word_addr),
      .load_data(load_data), .flush_i(1'b0),
      .req_i(req), .req_ready_o(req_ready),
      .resp_o(resp), .resp_ready_i(resp_ready),
      .resp_delay_i(resp_delay_i), .ram_write_o(ram_write_o));

  always_comb begin
    commit_o = '0;
    mem_req_valid_o = req.valid;
    mem_req_ready_o = req_ready;
    mem_resp_valid_o = resp.valid;
    mem_resp_ready_o = resp_ready;
  end

  // The frontend never retires or traps; that belongs to P1-C—F.
  always_ff @(posedge clk) begin
    if (!reset) begin
      assert (!commit_o.trap_valid && commit_o.slot_valid == 2'b00) else
        $error("P1-B_FRONTEND: fabricated retire/trap event");
    end
  end

endmodule
