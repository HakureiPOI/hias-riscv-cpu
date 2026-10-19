// P0-02-R1 small interface contract fixture.
//
// This is not a CPU module. It exercises two shared rules that the P1/P2
// implementation must follow:
//   1. two-slot contiguous-prefix acceptance with backpressure/resource limits
//   2. ROB-token allocation, stale-response rejection, and drain-before-wrap
module interface_fixture #(
    parameter int GEN_W = 1,
    parameter int DEPTH = 4
) (
    input  logic             clk,
    input  logic             reset,
    input  logic             flush,

    input  logic [1:0]       in_valid,
    input  logic [7:0]       in0_tag,
    input  logic [7:0]       in1_tag,
    input  logic [1:0]       resources,
    output logic [1:0]       accept_count,
    output logic [1:0]       accepted_valid,
    output logic [7:0]       accepted0,
    output logic [7:0]       accepted1,

    input  logic             alloc_req,
    output logic             alloc_ready,
    output logic [1:0]       alloc_idx,
    output logic [GEN_W-1:0] alloc_gen,

    input  logic             resp_valid,
    input  logic [1:0]       resp_idx,
    input  logic [GEN_W-1:0] resp_gen,
    output logic             resp_accept
);

  localparam int IDX_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;

  always_comb begin
    logic [1:0] prefix_count;
    prefix_count = 2'd0;
    if (!flush && in_valid[0]) begin
      prefix_count = in_valid[1] ? 2'd2 : 2'd1;
    end
    if (resources == 2'd0)
      accept_count = 2'd0;
    else if (resources == 2'd1)
      accept_count = (prefix_count == 2'd2) ? 2'd1 : prefix_count;
    else
      accept_count = prefix_count;

    accepted_valid = (accept_count == 2'd2) ? 2'b11 :
                     (accept_count == 2'd1) ? 2'b01 : 2'b00;
    accepted0 = in0_tag;
    accepted1 = in1_tag;
  end

  logic [GEN_W-1:0] idx_gen[0:DEPTH-1];
  logic             idx_valid[0:DEPTH-1];
  logic [IDX_W-1:0] next_idx;
  logic [GEN_W-1:0] next_gen;
  logic             wrap_blocked;
  logic [IDX_W:0]   busy;
  logic             accept_resp;

  always_comb begin
    accept_resp = resp_valid && idx_valid[resp_idx] &&
                  (idx_gen[resp_idx] == resp_gen);
  end

  assign alloc_ready = !reset && !wrap_blocked && (busy < DEPTH[IDX_W:0]);
  assign alloc_idx   = next_idx;
  assign alloc_gen   = next_gen;
  assign resp_accept = accept_resp;

  always_ff @(posedge clk) begin
    if (reset) begin
      next_idx <= '0;
      next_gen <= '0;
      wrap_blocked <= 1'b0;
      busy <= '0;
      for (int i = 0; i < DEPTH; i++) begin
        idx_gen[i] <= '0;
        idx_valid[i] <= 1'b0;
      end
    end else if (flush) begin
      // A flush cancels young allocations. Responses for them must be rejected
      // because the valid bits are cleared.
      next_idx <= '0;
      next_gen <= '0;
      wrap_blocked <= 1'b0;
      busy <= '0;
      for (int i = 0; i < DEPTH; i++) begin
        idx_gen[i] <= '0;
        idx_valid[i] <= 1'b0;
      end
    end else begin
      if (alloc_req && alloc_ready) begin
        idx_valid[next_idx] <= 1'b1;
        idx_gen[next_idx] <= next_gen;
        busy <= busy + 1'b1;
        if (next_idx == IDX_W'(DEPTH - 1)) begin
          if (next_gen == {GEN_W{1'b1}}) begin
            wrap_blocked <= 1'b1;
            next_idx <= '0;
            next_gen <= '0;
          end else begin
            next_idx <= '0;
            next_gen <= next_gen + 1'b1;
          end
        end else begin
          next_idx <= next_idx + 1'b1;
        end
      end
      if (accept_resp) begin
        idx_valid[resp_idx] <= 1'b0;
        busy <= busy - 1'b1;
      end
      if (wrap_blocked && busy == '0 && !accept_resp) begin
        wrap_blocked <= 1'b0;
        next_idx <= '0;
        next_gen <= '0;
      end
    end
  end

  // Assertions for the contract itself.
  always_ff @(posedge clk) begin
    if (!reset && !flush) begin
      assert (accept_count <= resources) else
        $error("P0-02_IF_FIXTURE: accept_count exceeds resources");
      assert ((accept_count == 2'd2) || (accepted_valid == {1'b0, (accept_count == 2'd1)}))
        else $error("P0-02_IF_FIXTURE: accepted_valid is not a prefix");
      assert (alloc_ready || wrap_blocked || busy >= DEPTH[IDX_W:0]) else
        $error("P0-02_IF_FIXTURE: alloc_ready deasserted without cause");
    end
  end

endmodule
