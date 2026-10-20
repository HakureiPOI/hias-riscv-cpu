// P1-B single-active-slot fetch unit.
//
// One accepted memory read may be in flight. A redirect cancels a request that
// has not been accepted; an accepted response is still drained and discarded.
// A decoded fetch result is held until the consumer returns accept_count.
module p1_fetch #(
    parameter int unsigned ID_W = 6,
    parameter int unsigned GEN_W = 8
) (
    input  logic                        clk,
    input  logic                        reset,
    /* verilator lint_off UNUSEDSIGNAL */
    input  core_types_pkg::redirect_t   redirect_i,

    output core_types_pkg::mem_req_t    mem_req_o,
    input  logic                        mem_req_ready_i,
    input  core_types_pkg::mem_resp_t   mem_resp_i,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic                        mem_resp_ready_o,

    output core_types_pkg::fetch_bundle_t fetch_o,
    input  core_types_pkg::fetch_accept_t fetch_accept_i,

    output logic                        redirect_error_o,
    output logic                        accept_error_o,
    output logic                        req_pending_o,
    output logic                        result_valid_o
);

  import core_config_pkg::*;
  import core_types_pkg::*;

  localparam logic [GEN_W-1:0] GEN_MAX = {GEN_W{1'b1}};

  typedef enum logic [1:0] {
    S_IDLE = 2'd0,
    S_RESP = 2'd1
  } state_e;

  state_e            state_q;
  logic [VA_BITS-1:0] pc_q;
  logic [VA_BITS-1:0] req_pc_q;
  logic [ID_W-1:0]   req_id_q;
  logic [GEN_W-1:0]  req_gen_q;
  logic [ID_W-1:0]   next_id_q;
  logic [GEN_W-1:0]  next_gen_q;
  logic              wrap_blocked_q;
  logic              discard_q;
  logic              wait_redirect_q;
  logic              out_valid_q;
  fetch_slot_t       out_slot_q;

  logic accept_fetch;
  logic response_match;

  always_comb begin
    mem_req_o = '0;
    mem_req_o.valid = !reset && (state_q == S_IDLE) && !out_valid_q &&
                      !wrap_blocked_q && !wait_redirect_q &&
                      !redirect_i.valid;
    mem_req_o.is_store = 1'b0;
    mem_req_o.va = pc_q;
    mem_req_o.pa = PA_BITS'(pc_q);
    mem_req_o.size = MEM_WORD;
    mem_req_o.byte_mask = 4'b1111;
    mem_req_o.wdata = '0;
    mem_req_o.cacheable = 1'b1;
    mem_req_o.priv = PRIV_M;
    mem_req_o.req_id = REQ_ID_W'(next_id_q);
    mem_req_o.gen = ROB_GEN_W'(next_gen_q);

    fetch_o = '0;
    fetch_o.slot_valid = out_valid_q ? 2'b01 : 2'b00;
    fetch_o.slot[0] = out_slot_q;
    fetch_o.slot[1] = '0;

    mem_resp_ready_o = 1'b1;
    accept_fetch = out_valid_q && fetch_accept_i.accept_count[0];
    response_match = (mem_resp_i.req_id == REQ_ID_W'(req_id_q)) &&
                     (mem_resp_i.gen == ROB_GEN_W'(req_gen_q));
    req_pending_o = (state_q == S_RESP);
    result_valid_o = out_valid_q;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      state_q <= S_IDLE;
      pc_q <= RESET_VECTOR;
      req_pc_q <= RESET_VECTOR;
      req_id_q <= '0;
      req_gen_q <= '0;
      next_id_q <= '0;
      next_gen_q <= '0;
      wrap_blocked_q <= 1'b0;
      discard_q <= 1'b0;
      wait_redirect_q <= 1'b0;
      out_valid_q <= 1'b0;
      out_slot_q <= '0;
      redirect_error_o <= 1'b0;
      accept_error_o <= 1'b0;
    end else begin
      redirect_error_o <= 1'b0;
      accept_error_o <= 1'b0;

      // Protocol check: only 4-byte aligned redirect targets are accepted.
      // The front-end does not fabricate a Trap with a wrong EPC.
      if (redirect_i.valid && (redirect_i.target_pc[1:0] != 2'b00)) begin
        redirect_error_o <= 1'b1;
      end else if (redirect_i.valid) begin
        // Redirect/Flush has priority over ordinary output and acceptance.
        pc_q <= redirect_i.target_pc;
        out_valid_q <= 1'b0;
        wait_redirect_q <= 1'b0;
        if (state_q == S_RESP) begin
          // An accepted read cannot be cancelled; drain and discard it.
          discard_q <= 1'b1;
        end
      end

      if (fetch_accept_i.accept_count[1]) accept_error_o <= 1'b1;

      // Request acceptance is suppressed in the redirect cycle by
      // mem_req_o.valid above.
      if (state_q == S_IDLE && mem_req_o.valid && mem_req_ready_i) begin
        state_q <= S_RESP;
        req_pc_q <= pc_q;
        req_id_q <= next_id_q;
        req_gen_q <= next_gen_q;
        discard_q <= 1'b0;
        next_id_q <= next_id_q + 1'b1;
        if (next_gen_q == GEN_MAX) begin
          wrap_blocked_q <= 1'b1;
          next_gen_q <= '0;
        end else begin
          next_gen_q <= next_gen_q + 1'b1;
        end
      end

      if (state_q == S_RESP && mem_resp_i.valid) begin
        if (discard_q || redirect_i.valid) begin
          // Old or cancelled response: consume, do not create a fetch event.
          state_q <= S_IDLE;
          discard_q <= 1'b0;
          if (wrap_blocked_q) begin
            wrap_blocked_q <= 1'b0;
            next_gen_q <= '0;
          end
        end else if (!response_match) begin
          // Wrong ID/gen: consume the response but keep waiting for the true
          // response. This path is exercised by the testbench fault wrapper.
          state_q <= S_RESP;
        end else begin
          out_slot_q <= '0;
          out_slot_q.valid <= 1'b1;
          out_slot_q.pc <= req_pc_q;
          out_slot_q.instr <= mem_resp_i.rdata;
          out_slot_q.pred_taken <= 1'b0;
          out_slot_q.pred_target <= req_pc_q + 32'd4;
          out_slot_q.pred_index <= 8'd0;
          out_slot_q.fetch_exc_valid <= mem_resp_i.error;
          out_slot_q.fetch_exc_cause <= EXC_INST_ACCESS_FAULT;
          out_slot_q.fetch_exc_tval <= req_pc_q;
          out_slot_q.fetch_gen <= FETCH_GEN_W'(req_gen_q);
          out_valid_q <= 1'b1;
          pc_q <= req_pc_q + 32'd4;
          if (mem_resp_i.error) wait_redirect_q <= 1'b1;
          state_q <= S_IDLE;
          if (wrap_blocked_q) begin
            wrap_blocked_q <= 1'b0;
            next_gen_q <= '0;
          end
        end
      end

      if (accept_fetch) begin
        out_valid_q <= 1'b0;
      end
    end
  end

  // Local contract checks.
  always_ff @(posedge clk) begin
    if (!reset) begin
      assert (!(out_valid_q && (state_q == S_RESP))) else
        $error("P1-B_FETCH: result and accepted request simultaneously");
      assert (fetch_accept_i.accept_count != 2'd2) else
        $error("P1-B_FETCH: multi-slot accept on single-slot fetch");
    end
  end

endmodule
