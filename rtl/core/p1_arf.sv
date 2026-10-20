// P1-C architectural register file: two combinational reads, one commit write.
// Reset initializes all registers to zero for deterministic bring-up. x0 is
// read as zero and writes to x0 are suppressed.
module p1_arf (
    input  logic        clk,
    input  logic        reset,
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data,
    input  logic        we,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    output logic [31:0] debug_regs [0:31]
);

  logic [31:0] regs [0:31];
  integer i_reset;
  integer i_debug;

  assign rs1_data = (rs1_addr == 5'd0) ? 32'b0 : regs[rs1_addr];
  assign rs2_data = (rs2_addr == 5'd0) ? 32'b0 : regs[rs2_addr];

  always_ff @(posedge clk) begin
    if (reset) begin
      for (i_reset = 0; i_reset < 32; i_reset = i_reset + 1)
        regs[i_reset] <= 32'b0;
    end else if (we && rd_addr != 5'd0) begin
      regs[rd_addr] <= rd_data;
    end
  end

  always_comb begin
    for (i_debug = 0; i_debug < 32; i_debug = i_debug + 1)
      debug_regs[i_debug] = regs[i_debug];
  end

endmodule
