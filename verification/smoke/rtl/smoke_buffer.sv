// P0-01 verification fixture: a small synchronous valid/ready FIFO.
// This is NOT part of the CPU RTL. It exists only to prove that the
// SystemVerilog -> Verilator -> assertion/exit-code path works.
//
// Semantics:
//   - synchronous active-high reset, sampled on posedge clk
//   - synchronous active-high flush; flush has priority over push/pop and
//     drops all pending items
//   - transfer occurs only on posedge clk when valid && ready
//   - a stalled source must hold valid/data; a stalled sink must see held
//     valid/data (checked by the assertions below)
module smoke_buffer #(
    parameter int DEPTH = 4,
    parameter int WIDTH = 16
) (
    input  logic             clk,
    input  logic             reset,
    input  logic             flush,
    input  logic             in_valid,
    output logic             in_ready,
    input  logic [WIDTH-1:0] in_data,
    output logic             out_valid,
    input  logic             out_ready,
    output logic [WIDTH-1:0] out_data
);

  localparam int PTR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam int CNT_W = $clog2(DEPTH + 1);

  logic [WIDTH-1:0] mem[0:DEPTH-1];
  logic [PTR_W-1:0] wptr;
  logic [PTR_W-1:0] rptr;
  logic [CNT_W-1:0] count;
  logic             do_push;
  logic             do_pop;

  always_comb begin
    in_ready = (count < CNT_W'(DEPTH));
    out_valid = (count != 0);
    out_data = mem[rptr];
    do_push = in_valid && in_ready && !flush;
    do_pop = out_valid && out_ready && !flush;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      wptr  <= '0;
      rptr  <= '0;
      count <= '0;
    end else if (flush) begin
      wptr  <= '0;
      rptr  <= '0;
      count <= '0;
    end else begin
      if (do_push) begin
        mem[wptr] <= in_data;
        wptr <= (wptr == PTR_W'(DEPTH - 1)) ? '0 : wptr + 1'b1;
      end
      if (do_pop) begin
        rptr <= (rptr == PTR_W'(DEPTH - 1)) ? '0 : rptr + 1'b1;
      end
      count <= CNT_W'(count + CNT_W'(do_push) - CNT_W'(do_pop));
    end
  end

  // Internal invariants. These are immediate assertions and are enabled by
  // the simulator assertion flag.
  always_ff @(posedge clk) begin
    if (!reset) begin
      assert (count <= CNT_W'(DEPTH)) else $error("P0-01_DUT_INVARIANT count > DEPTH");
      if (do_push)
        assert (count < CNT_W'(DEPTH)) else $error("P0-01_DUT_INVARIANT push while full");
      if (do_pop)
        assert (count > CNT_W'(0)) else $error("P0-01_DUT_INVARIANT pop while empty");
    end
  end

  // Handshake stability: a source that was stalled must hold valid/data, and
  // a sink that was stalled must see valid/data held. Flush cancels a pending
  // transaction, so it is excluded.
  logic             prev_in_stalled;
  logic [WIDTH-1:0] prev_in_data;
  logic             prev_out_stalled;
  logic [WIDTH-1:0] prev_out_data;

  always_ff @(posedge clk) begin
    prev_in_stalled <= !reset && !flush && in_valid && !in_ready;
    prev_in_data    <= in_data;
    prev_out_stalled <= !reset && !flush && out_valid && !out_ready;
    prev_out_data   <= out_data;
  end

  always_ff @(posedge clk) begin
    if (!reset && !flush && prev_in_stalled) begin
      assert (in_valid) else $error("P0-01_DUT_STABILITY input valid dropped while stalled");
      assert (in_data == prev_in_data) else $error("P0-01_DUT_STABILITY input data changed while stalled");
    end
    if (!reset && !flush && prev_out_stalled) begin
      assert (out_valid) else $error("P0-01_DUT_STABILITY output valid dropped while stalled");
      assert (out_data == prev_out_data) else $error("P0-01_DUT_STABILITY output data changed while stalled");
    end
  end

endmodule
