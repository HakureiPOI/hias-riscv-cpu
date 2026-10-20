module alu_tb_top (
    input  logic [5:0]  op,
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [31:0] pc,
    input  logic [31:0] imm,
    output logic [31:0] result,
    output logic        branch_taken,
    output logic [31:0] target,
    output logic        is_control
);
  import core_types_pkg::*;
  p1_alu u_alu (.op(exec_op_e'(op)), .a(a), .b(b), .pc(pc), .imm(imm),
                .result(result), .branch_taken(branch_taken),
                .target(target), .is_control(is_control));
endmodule
