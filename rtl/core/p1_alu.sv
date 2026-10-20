// P1-C integer ALU and control-transfer target calculation.
// Covers the 29 integer/control instructions accepted by the P1-C backend.
module p1_alu (
    input  core_types_pkg::exec_op_e op,
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

  always_comb begin
    result = 32'b0;
    branch_taken = 1'b0;
    target = 32'b0;
    is_control = 1'b0;

    unique case (op)
      EXEC_ADD:  result = a + b;
      EXEC_SUB:  result = a - b;
      EXEC_SLL:  result = a << b[4:0];
      EXEC_SLT:  result = {31'b0, $signed(a) < $signed(b)};
      EXEC_SLTU: result = {31'b0, a < b};
      EXEC_XOR:  result = a ^ b;
      EXEC_SRL:  result = a >> b[4:0];
      EXEC_SRA:  result = $signed(a) >>> b[4:0];
      EXEC_OR:   result = a | b;
      EXEC_AND:  result = a & b;

      EXEC_ADDI:  result = a + imm;
      EXEC_SLTI:  result = {31'b0, $signed(a) < $signed(imm)};
      EXEC_SLTIU: result = {31'b0, a < imm};
      EXEC_XORI:  result = a ^ imm;
      EXEC_ORI:   result = a | imm;
      EXEC_ANDI:  result = a & imm;
      EXEC_SLLI:  result = a << imm[4:0];
      EXEC_SRLI:  result = a >> imm[4:0];
      EXEC_SRAI:  result = $signed(a) >>> imm[4:0];

      EXEC_LUI:   result = imm;
      EXEC_AUIPC: result = pc + imm;

      EXEC_JAL: begin
        result = pc + 32'd4;
        target = pc + imm;
        is_control = 1'b1;
      end
      EXEC_JALR: begin
        result = pc + 32'd4;
        target = (a + imm) & ~32'd1;
        is_control = 1'b1;
      end

      EXEC_BEQ, EXEC_BNE, EXEC_BLT, EXEC_BGE, EXEC_BLTU, EXEC_BGEU: begin
        target = pc + imm;
        is_control = 1'b1;
        unique case (op)
          EXEC_BEQ:  branch_taken = (a == b);
          EXEC_BNE:  branch_taken = (a != b);
          EXEC_BLT:  branch_taken = ($signed(a) < $signed(b));
          EXEC_BGE:  branch_taken = ($signed(a) >= $signed(b));
          EXEC_BLTU: branch_taken = (a < b);
          default:   branch_taken = (a >= b);
        endcase
      end

      default: begin
        result = 32'b0;
      end
    endcase
  end

endmodule
