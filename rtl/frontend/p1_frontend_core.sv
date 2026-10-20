// P1-B fetch + decode core. It owns no retirement/Trap state.
module p1_frontend_core #(
    parameter int unsigned ID_W = 6,
    parameter int unsigned GEN_W = 8
) (
    input  logic                          clk,
    input  logic                          reset,
    input  core_types_pkg::redirect_t     redirect_i,

    output core_types_pkg::mem_req_t      mem_req_o,
    input  logic                          mem_req_ready_i,
    input  core_types_pkg::mem_resp_t     mem_resp_i,
    output logic                          mem_resp_ready_o,

    output core_types_pkg::decoded_slot_t decoded_o,
    output logic                          decoded_valid_o,
    input  core_types_pkg::prefix_accept_t decoded_accept_i,

    output logic                          redirect_error_o,
    output logic                          accept_error_o,
    output logic                          fetch_valid_o,
    output logic [31:0]                   fetch_pc_o,
    output logic [31:0]                   fetch_instr_o,
    output logic                          fetch_exc_valid_o,
    output logic [7:0]                    fetch_gen_o,
    output logic                          req_pending_o
);

  import core_config_pkg::*;
  import core_types_pkg::*;

  fetch_bundle_t fetch_bundle;
  fetch_accept_t fetch_accept;
  fetch_slot_t   fetch_slot;
  decoded_slot_t decode_comb;
  decoded_slot_t out_q;
  logic          out_valid_q;
  logic          fetch_accept_error;
  logic          fetch_result_valid;
  logic          redirect_effective;

  p1_fetch #(.ID_W(ID_W), .GEN_W(GEN_W)) u_fetch (
      .clk(clk), .reset(reset), .redirect_i(redirect_i),
      .mem_req_o(mem_req_o), .mem_req_ready_i(mem_req_ready_i),
      .mem_resp_i(mem_resp_i), .mem_resp_ready_o(mem_resp_ready_o),
      .fetch_o(fetch_bundle), .fetch_accept_i(fetch_accept),
      .redirect_error_o(redirect_error_o), .accept_error_o(fetch_accept_error),
      .req_pending_o(req_pending_o), .result_valid_o(fetch_result_valid));

  assign fetch_slot = fetch_bundle.slot[0];
  p1_decode u_decode (.fetch_i(fetch_slot), .decoded_o(decode_comb));

  assign redirect_effective = redirect_i.valid &&
                             (redirect_i.target_pc[1:0] == 2'b00);

  always_comb begin
    fetch_accept = '0;
    if (fetch_bundle.slot_valid[0] && !redirect_effective &&
        (!out_valid_q || decoded_accept_i.accept_count[0]))
      fetch_accept.accept_count = 2'd1;
    decoded_o = out_q;
    decoded_o.valid = out_valid_q && !redirect_effective;
    decoded_valid_o = out_valid_q && !redirect_effective;
    accept_error_o = decoded_accept_i.accept_count[1] | fetch_accept_error;
    fetch_valid_o = fetch_bundle.slot_valid[0] | fetch_result_valid;
    fetch_pc_o = fetch_slot.pc;
    fetch_instr_o = fetch_slot.instr;
    fetch_exc_valid_o = fetch_slot.fetch_exc_valid;
    fetch_gen_o = fetch_slot.fetch_gen;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      out_q <= '0;
      out_valid_q <= 1'b0;
    end else begin
      // Redirect/Flush clears the held decoded result and suppresses a new
      // capture in the same cycle.
      if (redirect_effective) begin
        out_valid_q <= 1'b0;
      end
      if (out_valid_q && decoded_accept_i.accept_count[0]) begin
        out_valid_q <= 1'b0;
      end
      if (fetch_accept.accept_count[0]) begin
        out_q <= decode_comb;
        out_valid_q <= 1'b1;
      end
    end
  end

  // Only one active fetch slot in P1.
  always_ff @(posedge clk) begin
    if (!reset) begin
      assert (fetch_accept.accept_count != 2'd2) else
        $error("P1-B_FRONTEND: accepted more than one fetch slot");
    end
  end

endmodule
