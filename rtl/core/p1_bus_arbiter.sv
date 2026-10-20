// P1-D shared fetch/data memory arbiter.
//
// One transaction may be outstanding globally. A client's request is held
// stable while selected and not ready. Responses are routed only to the owner
// that accepted the transaction. Unselected clients see ready=0 and valid=0.
module p1_bus_arbiter (
    input  logic                     clk,
    input  logic                     reset,

    input  core_types_pkg::mem_req_t fetch_req_i,
    output logic                     fetch_req_ready_o,
    output core_types_pkg::mem_resp_t fetch_resp_o,
    input  logic                     fetch_resp_ready_i,

    input  core_types_pkg::mem_req_t lsu_req_i,
    output logic                     lsu_req_ready_o,
    output core_types_pkg::mem_resp_t lsu_resp_o,
    input  logic                     lsu_resp_ready_i,

    output core_types_pkg::mem_req_t  bus_req_o,
    input  logic                      bus_req_ready_i,
    input  core_types_pkg::mem_resp_t bus_resp_i,
    output logic                      bus_resp_ready_o,

    output logic                      fetch_outstanding_o,
    output logic                      lsu_outstanding_o
);

  import core_types_pkg::*;

  typedef enum logic [1:0] {
    OWNER_NONE  = 2'd0,
    OWNER_FETCH = 2'd1,
    OWNER_LSU   = 2'd2
  } owner_e;

  owner_e owner_q;
  logic [5:0] owner_id_q;
  logic [7:0] owner_gen_q;
  owner_e sel_q;
  logic   sel_locked_q;
  logic   last_was_lsu_q;
  owner_e sel;
  logic   sel_req_valid;
  logic   resp_match;

  always_comb begin
    sel = OWNER_NONE;
    if (owner_q != OWNER_NONE) sel = owner_q;
    else if (sel_locked_q) sel = sel_q;
    else if (fetch_req_i.valid && lsu_req_i.valid)
      sel = last_was_lsu_q ? OWNER_FETCH : OWNER_LSU;
    else if (fetch_req_i.valid) sel = OWNER_FETCH;
    else if (lsu_req_i.valid) sel = OWNER_LSU;
    sel_req_valid = (sel == OWNER_FETCH) ? fetch_req_i.valid :
                    (sel == OWNER_LSU) ? lsu_req_i.valid : 1'b0;

    bus_req_o = '0;
    if (owner_q == OWNER_NONE) begin
      if (sel == OWNER_FETCH) bus_req_o = fetch_req_i;
      else if (sel == OWNER_LSU) bus_req_o = lsu_req_i;
    end

    fetch_req_ready_o = (owner_q == OWNER_NONE) && (sel == OWNER_FETCH) &&
                        fetch_req_i.valid && bus_req_ready_i;
    lsu_req_ready_o = (owner_q == OWNER_NONE) && (sel == OWNER_LSU) &&
                      lsu_req_i.valid && bus_req_ready_i;

    resp_match = (bus_resp_i.req_id == owner_id_q) &&
                 (bus_resp_i.gen == owner_gen_q);
    fetch_resp_o = (owner_q == OWNER_FETCH && resp_match) ? bus_resp_i : '0;
    lsu_resp_o = (owner_q == OWNER_LSU && resp_match) ? bus_resp_i : '0;
    // Matching responses are held by the owner client's ready. Wrong/orphan
    // responses are drained without releasing the saved owner identity.
    bus_resp_ready_o = (owner_q == OWNER_NONE) ? 1'b1 :
                       (resp_match ?
                        ((owner_q == OWNER_FETCH) ? fetch_resp_ready_i :
                                                   lsu_resp_ready_i) : 1'b1);

    fetch_outstanding_o = (owner_q == OWNER_FETCH);
    lsu_outstanding_o = (owner_q == OWNER_LSU);
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      owner_q <= OWNER_NONE;
      owner_id_q <= '0;
      owner_gen_q <= '0;
      sel_q <= OWNER_NONE;
      sel_locked_q <= 1'b0;
      last_was_lsu_q <= 1'b0;
    end else begin
      if (owner_q == OWNER_NONE) begin
        if (fetch_req_ready_o) begin
          owner_q <= OWNER_FETCH;
          owner_id_q <= fetch_req_i.req_id;
          owner_gen_q <= fetch_req_i.gen;
          sel_locked_q <= 1'b0;
          last_was_lsu_q <= 1'b0;
        end else if (lsu_req_ready_o) begin
          owner_q <= OWNER_LSU;
          owner_id_q <= lsu_req_i.req_id;
          owner_gen_q <= lsu_req_i.gen;
          sel_locked_q <= 1'b0;
          last_was_lsu_q <= 1'b1;
        end else if (!sel_req_valid) begin
          sel_locked_q <= 1'b0;
        end else begin
          // Keep the selected client stable until its request is accepted.
          sel_locked_q <= 1'b1;
          sel_q <= sel;
        end
      end else if (bus_resp_i.valid && bus_resp_ready_o &&
                   (bus_resp_i.req_id == owner_id_q) &&
                   (bus_resp_i.gen == owner_gen_q)) begin
        owner_q <= OWNER_NONE;
      end
    end
  end

endmodule
