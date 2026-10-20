module arf_tb_top (
    input  logic        clk,
    input  logic        reset,
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    input  logic        we,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data
);
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] debug_regs [0:31];
  /* verilator lint_on UNUSEDSIGNAL */
  p1_arf u_arf (.clk(clk), .reset(reset),
                .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
                .rs1_data(rs1_data), .rs2_data(rs2_data),
                .we(we), .rd_addr(rd_addr), .rd_data(rd_data),
                .debug_regs(debug_regs));
endmodule
