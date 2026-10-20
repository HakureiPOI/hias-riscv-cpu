// P1-B RV32I + Zicsr + Zifencei decoder.
// Pure combinational decode; no CSR state, no execution, no retirement.
module p1_decode (
    input  core_types_pkg::fetch_slot_t fetch_i,
    output core_types_pkg::decoded_slot_t decoded_o
);

  import core_config_pkg::*;
  import core_types_pkg::*;

  // Immediate helpers intentionally consume only the encoding subfields.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [31:0] imm_i(input logic [31:0] instr);
    return {{20{instr[31]}}, instr[31:20]};
  endfunction

  function automatic logic [31:0] imm_s(input logic [31:0] instr);
    return {{20{instr[31]}}, instr[31:25], instr[11:7]};
  endfunction

  function automatic logic [31:0] imm_b(input logic [31:0] instr);
    return {{19{instr[31]}}, instr[31], instr[7], instr[30:25],
            instr[11:8], 1'b0};
  endfunction

  function automatic logic [31:0] imm_u(input logic [31:0] instr);
    return {instr[31:12], 12'b0};
  endfunction

  function automatic logic [31:0] imm_j(input logic [31:0] instr);
    return {{11{instr[31]}}, instr[31], instr[19:12], instr[20],
            instr[30:21], 1'b0};
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  always_comb begin : decode
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [4:0]  rd;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  shamt;

    opcode = fetch_i.instr[6:0];
    funct3 = fetch_i.instr[14:12];
    funct7 = fetch_i.instr[31:25];
    rd = fetch_i.instr[11:7];
    rs1 = fetch_i.instr[19:15];
    rs2 = fetch_i.instr[24:20];
    shamt = fetch_i.instr[24:20];

    decoded_o = '0;
    decoded_o.valid = fetch_i.valid;
    decoded_o.pc = fetch_i.pc;
    decoded_o.instr = fetch_i.instr;
    decoded_o.op = OP_ALU_I;
    decoded_o.exec_op = EXEC_ADDI;
    decoded_o.rd = rd;
    decoded_o.rs1 = rs1;
    decoded_o.rs2 = rs2;
    decoded_o.imm = '0;
    decoded_o.uses_rs1 = 1'b0;
    decoded_o.uses_rs2 = 1'b0;
    decoded_o.rd_we = 1'b0;
    decoded_o.is_branch = 1'b0;
    decoded_o.is_jump = 1'b0;
    decoded_o.is_load = 1'b0;
    decoded_o.is_store = 1'b0;
    decoded_o.is_csr = 1'b0;
    decoded_o.is_fence = 1'b0;
    decoded_o.is_fence_i = 1'b0;
    decoded_o.is_mret = 1'b0;
    decoded_o.is_sret = 1'b0;
    decoded_o.is_wfi = 1'b0;
    decoded_o.illegal = 1'b0;
    decoded_o.illegal_cause = EXC_ILLEGAL_INST;
    decoded_o.illegal_tval = fetch_i.instr;
    decoded_o.mem_size = MEM_WORD;
    decoded_o.csr_op = CSR_RW;
    decoded_o.csr_addr = '0;
    decoded_o.csr_uimm = '0;
    decoded_o.csr_uimm_valid = 1'b0;
    decoded_o.pred_index = fetch_i.pred_index;
    decoded_o.fetch_exc_valid = fetch_i.fetch_exc_valid;
    decoded_o.fetch_exc_cause = fetch_i.fetch_exc_cause;
    decoded_o.fetch_exc_tval = fetch_i.fetch_exc_tval;
    decoded_o.fetch_gen = fetch_i.fetch_gen;
    decoded_o.pred_taken = fetch_i.pred_taken;
    decoded_o.pred_target = fetch_i.pred_target;

    if (!fetch_i.valid) begin
      decoded_o.valid = 1'b0;
    end else if (fetch_i.fetch_exc_valid) begin
      // Fetch errors take precedence and are not reclassified as illegals.
      decoded_o.valid = 1'b1;
      decoded_o.rd_we = 1'b0;
      decoded_o.imm = '0;
    end else begin
      unique case (opcode)
        7'b0110111: begin // LUI
          decoded_o.op = OP_LUI;
          decoded_o.exec_op = EXEC_LUI;
          decoded_o.imm = imm_u(fetch_i.instr);
          decoded_o.rd_we = (rd != 0);
          decoded_o.uses_rs1 = 1'b0;
        end
        7'b0010111: begin // AUIPC
          decoded_o.op = OP_AUIPC;
          decoded_o.exec_op = EXEC_AUIPC;
          decoded_o.imm = imm_u(fetch_i.instr);
          decoded_o.rd_we = (rd != 0);
        end
        7'b1101111: begin // JAL
          if (funct3 == 3'b000) begin
            decoded_o.op = OP_JAL;
            decoded_o.exec_op = EXEC_JAL;
            decoded_o.imm = imm_j(fetch_i.instr);
            decoded_o.rd_we = (rd != 0);
            decoded_o.is_jump = 1'b1;
          end else begin
            decoded_o.illegal = 1'b1;
          end
        end
        7'b1100111: begin // JALR
          if (funct3 == 3'b000) begin
            decoded_o.op = OP_JALR;
            decoded_o.exec_op = EXEC_JALR;
            decoded_o.imm = imm_i(fetch_i.instr);
            decoded_o.rd_we = (rd != 0);
            decoded_o.uses_rs1 = 1'b1;
            decoded_o.is_jump = 1'b1;
          end else begin
            decoded_o.illegal = 1'b1;
          end
        end
        7'b1100011: begin // BRANCH
          decoded_o.imm = imm_b(fetch_i.instr);
          decoded_o.uses_rs1 = 1'b1;
          decoded_o.uses_rs2 = 1'b1;
          decoded_o.is_branch = 1'b1;
          decoded_o.op = OP_BRANCH;
          unique case (funct3)
            3'b000: decoded_o.exec_op = EXEC_BEQ;
            3'b001: decoded_o.exec_op = EXEC_BNE;
            3'b100: decoded_o.exec_op = EXEC_BLT;
            3'b101: decoded_o.exec_op = EXEC_BGE;
            3'b110: decoded_o.exec_op = EXEC_BLTU;
            3'b111: decoded_o.exec_op = EXEC_BGEU;
            default: begin decoded_o.illegal = 1'b1; decoded_o.exec_op = EXEC_BEQ; end
          endcase
        end
        7'b0000011: begin // LOAD
          decoded_o.imm = imm_i(fetch_i.instr);
          decoded_o.uses_rs1 = 1'b1;
          decoded_o.is_load = 1'b1;
          decoded_o.op = OP_LOAD;
          decoded_o.rd_we = (rd != 0);
          unique case (funct3)
            3'b000: begin decoded_o.exec_op = EXEC_LB;  decoded_o.mem_size = MEM_BYTE; end
            3'b001: begin decoded_o.exec_op = EXEC_LH;  decoded_o.mem_size = MEM_HALF; end
            3'b010: begin decoded_o.exec_op = EXEC_LW;  decoded_o.mem_size = MEM_WORD; end
            3'b100: begin decoded_o.exec_op = EXEC_LBU; decoded_o.mem_size = MEM_BYTE; end
            3'b101: begin decoded_o.exec_op = EXEC_LHU; decoded_o.mem_size = MEM_HALF; end
            default: begin decoded_o.illegal = 1'b1; decoded_o.exec_op = EXEC_LW; end
          endcase
        end
        7'b0100011: begin // STORE
          decoded_o.imm = imm_s(fetch_i.instr);
          decoded_o.uses_rs1 = 1'b1;
          decoded_o.uses_rs2 = 1'b1;
          decoded_o.is_store = 1'b1;
          decoded_o.op = OP_STORE;
          decoded_o.rd_we = 1'b0;
          unique case (funct3)
            3'b000: begin decoded_o.exec_op = EXEC_SB; decoded_o.mem_size = MEM_BYTE; end
            3'b001: begin decoded_o.exec_op = EXEC_SH; decoded_o.mem_size = MEM_HALF; end
            3'b010: begin decoded_o.exec_op = EXEC_SW; decoded_o.mem_size = MEM_WORD; end
            default: begin decoded_o.illegal = 1'b1; decoded_o.exec_op = EXEC_SW; end
          endcase
        end
        7'b0010011: begin // OP-IMM
          decoded_o.uses_rs1 = 1'b1;
          decoded_o.rd_we = (rd != 0);
          decoded_o.op = OP_ALU_I;
          unique case (funct3)
            3'b000: begin decoded_o.exec_op = EXEC_ADDI; decoded_o.imm = imm_i(fetch_i.instr); end
            3'b010: begin decoded_o.exec_op = EXEC_SLTI; decoded_o.imm = imm_i(fetch_i.instr); end
            3'b011: begin decoded_o.exec_op = EXEC_SLTIU; decoded_o.imm = imm_i(fetch_i.instr); end
            3'b100: begin decoded_o.exec_op = EXEC_XORI; decoded_o.imm = imm_i(fetch_i.instr); end
            3'b110: begin decoded_o.exec_op = EXEC_ORI; decoded_o.imm = imm_i(fetch_i.instr); end
            3'b111: begin decoded_o.exec_op = EXEC_ANDI; decoded_o.imm = imm_i(fetch_i.instr); end
            3'b001: begin
              if (funct7 == 7'b0000000) begin
                decoded_o.exec_op = EXEC_SLLI;
                decoded_o.imm = {27'b0, shamt};
              end else begin
                decoded_o.illegal = 1'b1;
                decoded_o.exec_op = EXEC_SLLI;
              end
            end
            3'b101: begin
              if (funct7 == 7'b0000000) begin
                decoded_o.exec_op = EXEC_SRLI;
                decoded_o.imm = {27'b0, shamt};
              end else if (funct7 == 7'b0100000) begin
                decoded_o.exec_op = EXEC_SRAI;
                decoded_o.imm = {27'b0, shamt};
              end else begin
                decoded_o.illegal = 1'b1;
                decoded_o.exec_op = EXEC_SRLI;
              end
            end
            default: decoded_o.illegal = 1'b1;
          endcase
        end
        7'b0110011: begin // OP
          decoded_o.uses_rs1 = 1'b1;
          decoded_o.uses_rs2 = 1'b1;
          decoded_o.rd_we = (rd != 0);
          decoded_o.op = OP_ALU_R;
          if (funct7 == 7'b0000000) begin
            unique case (funct3)
              3'b000: decoded_o.exec_op = EXEC_ADD;
              3'b001: decoded_o.exec_op = EXEC_SLL;
              3'b010: decoded_o.exec_op = EXEC_SLT;
              3'b011: decoded_o.exec_op = EXEC_SLTU;
              3'b100: decoded_o.exec_op = EXEC_XOR;
              3'b101: decoded_o.exec_op = EXEC_SRL;
              3'b110: decoded_o.exec_op = EXEC_OR;
              3'b111: decoded_o.exec_op = EXEC_AND;
            endcase
          end else if (funct7 == 7'b0100000) begin
            case (funct3)
              3'b000: decoded_o.exec_op = EXEC_SUB;
              3'b101: decoded_o.exec_op = EXEC_SRA;
              default: begin decoded_o.illegal = 1'b1; decoded_o.exec_op = EXEC_ADD; end
            endcase
          end else begin
            // RV32M and other funct7 values are outside P1-B's supported set.
            decoded_o.illegal = 1'b1;
            decoded_o.op = OP_MULDIV;
            decoded_o.exec_op = EXEC_MUL;
          end
        end
        7'b0001111: begin // FENCE / FENCE.I
          decoded_o.rd_we = 1'b0;
          decoded_o.uses_rs1 = 1'b0;
          decoded_o.uses_rs2 = 1'b0;
          if (funct3 == 3'b000) begin
            decoded_o.op = OP_FENCE;
            decoded_o.exec_op = EXEC_FENCE;
            decoded_o.is_fence = 1'b1;
          end else if (funct3 == 3'b001) begin
            decoded_o.op = OP_FENCEI;
            decoded_o.exec_op = EXEC_FENCEI;
            decoded_o.is_fence_i = 1'b1;
          end else begin
            decoded_o.illegal = 1'b1;
          end
        end
        7'b1110011: begin // SYSTEM
          decoded_o.rd_we = 1'b0;
          if (funct3 == 3'b000) begin
            unique case (fetch_i.instr)
              32'h0000_0073: begin decoded_o.op = OP_ECALL;  decoded_o.exec_op = EXEC_ECALL; end
              32'h0010_0073: begin decoded_o.op = OP_EBREAK; decoded_o.exec_op = EXEC_EBREAK; end
              32'h3020_0073: begin decoded_o.op = OP_MRET;   decoded_o.exec_op = EXEC_MRET; decoded_o.is_mret = 1'b1; end
              32'h1050_0073: begin decoded_o.op = OP_WFI;    decoded_o.exec_op = EXEC_WFI;  decoded_o.is_wfi = 1'b1; end
              default: decoded_o.illegal = 1'b1;
            endcase
          end else if (funct3 == 3'b100) begin
            decoded_o.illegal = 1'b1;
          end else begin
            decoded_o.is_csr = 1'b1;
            decoded_o.op = OP_CSR;
            decoded_o.exec_op = EXEC_CSR;
            decoded_o.csr_addr = fetch_i.instr[31:20];
            decoded_o.rd_we = (rd != 0);
            decoded_o.csr_uimm_valid = (funct3 >= 3'b101);
            decoded_o.csr_uimm = rs1;
            decoded_o.rs1 = decoded_o.csr_uimm_valid ? 5'd0 : rs1;
            decoded_o.uses_rs1 = !decoded_o.csr_uimm_valid && (rs1 != 0);
            unique case (funct3)
              3'b001: decoded_o.csr_op = CSR_RW;
              3'b010: decoded_o.csr_op = CSR_RS;
              3'b011: decoded_o.csr_op = CSR_RC;
              3'b101: decoded_o.csr_op = CSR_RW;
              3'b110: decoded_o.csr_op = CSR_RS;
              3'b111: decoded_o.csr_op = CSR_RC;
              default: decoded_o.illegal = 1'b1;
            endcase
          end
        end
        default: decoded_o.illegal = 1'b1;
      endcase

      if (decoded_o.illegal) begin
        decoded_o.illegal_cause = EXC_ILLEGAL_INST;
        decoded_o.illegal_tval = fetch_i.instr;
        decoded_o.rd_we = 1'b0;
        decoded_o.is_branch = 1'b0;
        decoded_o.is_jump = 1'b0;
        decoded_o.is_load = 1'b0;
        decoded_o.is_store = 1'b0;
        decoded_o.is_csr = 1'b0;
        decoded_o.is_fence = 1'b0;
        decoded_o.is_fence_i = 1'b0;
        decoded_o.is_mret = 1'b0;
        decoded_o.is_sret = 1'b0;
        decoded_o.is_wfi = 1'b0;
      end
    end
  end

endmodule
