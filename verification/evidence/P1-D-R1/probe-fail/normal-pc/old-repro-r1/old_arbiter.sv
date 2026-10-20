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
  owner_e sel_q;
  logic   sel_locked_q;
  logic   last_was_lsu_q;
  owner_e sel;
  logic   sel_req_valid;

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
    if (sel == OWNER_FETCH) bus_req_o = fetch_req_i;
    else if (sel == OWNER_LSU) bus_req_o = lsu_req_i;

    fetch_req_ready_o = (owner_q == OWNER_NONE) && (sel == OWNER_FETCH) &&
                        bus_req_ready_i;
    lsu_req_ready_o = (owner_q == OWNER_NONE) && (sel == OWNER_LSU) &&
                      bus_req_ready_i;

    fetch_resp_o = (owner_q == OWNER_FETCH) ? bus_resp_i : '0;
    lsu_resp_o = (owner_q == OWNER_LSU) ? bus_resp_i : '0;
    bus_resp_ready_o = (owner_q == OWNER_FETCH) ? fetch_resp_ready_i :
                       (owner_q == OWNER_LSU) ? lsu_resp_ready_i : 1'b1;

    fetch_outstanding_o = (owner_q == OWNER_FETCH);
    lsu_outstanding_o = (owner_q == OWNER_LSU);
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      owner_q <= OWNER_NONE;
      sel_q <= OWNER_NONE;
      sel_locked_q <= 1'b0;
      last_was_lsu_q <= 1'b0;
    end else begin
      if (owner_q == OWNER_NONE) begin
        if (fetch_req_ready_o) begin
          owner_q <= OWNER_FETCH;
          sel_locked_q <= 1'b0;
          last_was_lsu_q <= 1'b0;
        end else if (lsu_req_ready_o) begin
          owner_q <= OWNER_LSU;
          sel_locked_q <= 1'b0;
          last_was_lsu_q <= 1'b1;
        end else if (!sel_req_valid) begin
          sel_locked_q <= 1'b0;
        end else begin
          // Keep the selected client stable until its request is accepted.
          sel_locked_q <= 1'b1;
          sel_q <= sel;
        end
      end else if (bus_resp_i.valid && bus_resp_ready_o) begin
        owner_q <= OWNER_NONE;
      end
    end
  end

endmodule
