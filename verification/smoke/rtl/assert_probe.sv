// P0-01 negative probe: intentionally fires a known assertion once.
// The Makefile requires a non-zero exit status and the exact message below;
// it does not accept arbitrary failures.
module assert_probe (
    input logic clk
);
  always_ff @(posedge clk) begin
    assert (1'b0) else $error("P0-01_NEGATIVE_PROBE_ASSERTION_FIRED");
  end
endmodule
