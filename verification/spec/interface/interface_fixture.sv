// P0-02-R2 small interface contract fixture (not a CPU module).
//
// Contracts exercised:
//   - two-slot contiguous-prefix acceptance with resource/backpressure limits
//   - reverse prefix accept_count sampled on the clock edge
//   - Token allocation with per-allocation generation, so a freed index is
//     re-used only with a new identity
//   - Flush marks active/cancelled transactions and keeps them counted until
//     their external response arrives; it does not silently forget them
//   - one net in-flight count update (no overlapping +1/-1 assignments)
//   - conservative allocation: the next index must be free; active targets are
//     never overwritten by a non-head completion
//   - drain-before-wrap and stale/duplicate response rejection
module interface_fixture #(
    parameter int GEN_W = 3,
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
    output logic             resp_accept,

    output logic [2:0]       active_count,
    output logic [2:0]       cancelled_count
);

  localparam int IDX_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;

  // ---- prefix acceptance (combinational proposal; the receiver samples the
  // ---- accepted slots at the clock edge in the testbench) -----------------
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

  // ---- token ownership ----------------------------------------------------
  logic [GEN_W-1:0] idx_gen[0:DEPTH-1];
  logic             idx_valid[0:DEPTH-1];
  logic             idx_cancelled[0:DEPTH-1];
  logic [IDX_W-1:0] next_idx;
  logic [GEN_W-1:0] next_gen;
  logic             wrap_blocked;
  logic [IDX_W:0]   busy;
  logic             resp_fire;
  logic             alloc_fire;

  always_comb begin
    resp_fire = resp_valid && idx_valid[resp_idx] &&
                (idx_gen[resp_idx] == resp_gen);
    alloc_fire = alloc_req && alloc_ready;
    active_count = busy[2:0];
    cancelled_count = 3'(idx_cancelled[0]) + 3'(idx_cancelled[1]) +
                      ((DEPTH > 2) ? 3'(idx_cancelled[2]) : 3'd0) +
                      ((DEPTH > 3) ? 3'(idx_cancelled[3]) : 3'd0);
  end

  assign alloc_ready = !reset && !flush && !wrap_blocked &&
                       (busy < DEPTH[IDX_W:0]) && !idx_valid[next_idx];
  assign alloc_idx = next_idx;
  assign alloc_gen = next_gen;
  assign resp_accept = resp_fire;

  always_ff @(posedge clk) begin
    if (reset) begin
      // Environment contract: reset is only used after external requests have
      // been quiesced; the fixture cannot discover in-flight requests that
      // were forgotten outside the module.
      next_idx <= '0;
      next_gen <= '0;
      wrap_blocked <= 1'b0;
      busy <= '0;
      for (int i = 0; i < DEPTH; i++) begin
        idx_gen[i] <= '0;
        idx_valid[i] <= 1'b0;
        idx_cancelled[i] <= 1'b0;
      end
    end else begin
      // Flush converts active transactions to cancelled-but-in-flight. Their
      // identities stay reserved until the matching external response arrives.
      if (flush) begin
        for (int i = 0; i < DEPTH; i++) begin
          if (idx_valid[i]) idx_cancelled[i] <= 1'b1;
        end
      end

      // A response clears its own identity. This is the only completion path;
      // a response for a freed/re-used generation is rejected.
      if (resp_fire) begin
        idx_valid[resp_idx] <= 1'b0;
        idx_cancelled[resp_idx] <= 1'b0;
      end

      // Allocation is conservative: never write the next active index.
      if (alloc_fire) begin
        idx_valid[next_idx] <= 1'b1;
        idx_gen[next_idx] <= next_gen;
        idx_cancelled[next_idx] <= 1'b0;
        if (next_gen == {GEN_W{1'b1}}) begin
          // This is the final generation before wrap. Stop allocating until
          // every in-flight (including cancelled) token drains.
          wrap_blocked <= 1'b1;
          next_idx <= '0;
          next_gen <= '0;
        end else begin
          next_gen <= next_gen + 1'b1;
          next_idx <= (next_idx == IDX_W'(DEPTH - 1)) ? '0 : next_idx + 1'b1;
        end
      end

      // One net count update, so simultaneous allocation and completion do
      // not overwrite each other.
      busy <= busy + (alloc_fire ? 3'd1 : 3'd0) -
              (resp_fire ? 3'd1 : 3'd0);

      if (wrap_blocked && ((busy + (alloc_fire ? 3'd1 : 3'd0) -
                            (resp_fire ? 3'd1 : 3'd0)) == '0)) begin
        wrap_blocked <= 1'b0;
        next_idx <= '0;
        next_gen <= '0;
      end
    end
  end

  // Contract assertions. These check the local ownership rules, not CPU
  // behaviour.
  always_ff @(posedge clk) begin
    if (!reset) begin
      assert (accept_count <= resources) else
        $error("P0-02_IF_FIXTURE: accept_count exceeds resources");
      assert ((accept_count == 2'd2) ||
              (accepted_valid == {1'b0, (accept_count == 2'd1)})) else
        $error("P0-02_IF_FIXTURE: accepted_valid is not a prefix");
      assert (!alloc_fire || !idx_valid[next_idx]) else
        $error("P0-02_IF_FIXTURE: allocation overwrote active token");
      assert (busy <= DEPTH[IDX_W:0]) else
        $error("P0-02_IF_FIXTURE: active count exceeds DEPTH");
    end
  end

endmodule
