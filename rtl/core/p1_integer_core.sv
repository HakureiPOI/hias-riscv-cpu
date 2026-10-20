// P1-C single-instruction sequential integer backend.
//
// One decoded instruction is accepted from the P1-B frontend, executes through
// the ARF/ALU, and commits on the next cycle. Only one instruction is in flight;
// an internal single-entry sequential commit slot provides the real rob_token_t
// identity. A stopped fault result is held for future P1-E Trap handling; this
// module never fabricates a Trap or retirement for an unsupported instruction.
module p1_integer_core #(
    parameter int unsigned GEN_W = 8
) (
    input  logic                          clk,
    input  logic                          reset,
    input  logic                          accept_stall_i,

    /* verilator lint_off UNUSEDSIGNAL */
    input  core_types_pkg::decoded_slot_t decoded_i,
    input  logic                          decoded_valid_i,
    /* verilator lint_on UNUSEDSIGNAL */
    output core_types_pkg::prefix_accept_t decoded_accept_o,

    output core_types_pkg::redirect_t     redirect_o,
    output core_types_pkg::commit_bundle_t commit_o,

    output logic                          fault_valid_o,
    output logic [1:0]                    fault_kind_o,
    output logic [31:0]                   fault_pc_o,
    output logic [31:0]                   fault_instr_o,
    output logic [4:0]                    fault_cause_o,
    output logic [31:0]                   fault_tval_o,
    output core_types_pkg::rob_token_t    fault_token_o,
    output logic [7:0]                    fault_fetch_gen_o,

    output logic [31:0]                   arf_debug_o [0:31]
);

  import core_config_pkg::*;
  import core_types_pkg::*;

  typedef enum logic [2:0] {
    S_IDLE   = 3'd0,
    S_EXEC   = 3'd1,
    S_EXEC2  = 3'd2,
    S_EXEC3  = 3'd3,
    S_COMMIT = 3'd4,
    S_FAULT  = 3'd5
  } state_e;

  // Fault kinds: 0 fetch exception, 1 illegal encoding, 2 unsupported but
  // legal instruction, 3 control-transfer target misalignment.
  state_e            state_q;
  logic [31:0]       item_pc_q;
  logic [31:0]       item_instr_q;
  logic [4:0]        item_rd_q;
  logic              item_rd_we_q;
  rob_token_t        token_q;
  logic [31:0]       result_q;
  logic [31:0]       next_pc_q;
  logic              item_control_q;
  logic [GEN_W-1:0]  next_gen_q;

  logic [1:0]        fault_kind_q;
  logic [31:0]       fault_pc_q;
  logic [31:0]       fault_instr_q;
  logic [4:0]        fault_cause_q;
  logic [31:0]       fault_tval_q;
  rob_token_t        fault_token_q;
  logic [7:0]        fault_fetch_gen_q;

  logic [31:0]       arf_rs1;
  logic [31:0]       arf_rs2;
  logic [31:0]       alu_result;
  logic [31:0]       alu_target;
  logic              alu_branch_taken;
  logic              alu_is_control;

  logic              accept;
  logic              exec_supported;
  logic              unsupported;
  logic              fault_select;
  logic [1:0]        fault_kind_sel;
  logic [4:0]        fault_cause_sel;
  logic [31:0]       fault_tval_sel;
  logic [31:0]       next_pc_sel;
  logic              target_unaligned;

  function automatic logic supported_exec(input exec_op_e op);
    unique case (op)
      EXEC_ADD, EXEC_SUB, EXEC_SLL, EXEC_SLT, EXEC_SLTU, EXEC_XOR,
      EXEC_SRL, EXEC_SRA, EXEC_OR, EXEC_AND,
      EXEC_ADDI, EXEC_SLTI, EXEC_SLTIU, EXEC_XORI, EXEC_ORI, EXEC_ANDI,
      EXEC_SLLI, EXEC_SRLI, EXEC_SRAI,
      EXEC_LUI, EXEC_AUIPC, EXEC_JAL, EXEC_JALR,
      EXEC_BEQ, EXEC_BNE, EXEC_BLT, EXEC_BGE, EXEC_BLTU, EXEC_BGEU:
        return 1'b1;
      default:
        return 1'b0;
    endcase
  endfunction

  assign exec_supported = supported_exec(decoded_i.exec_op);
  assign unsupported = decoded_i.is_load || decoded_i.is_store ||
                       decoded_i.is_csr || decoded_i.is_fence ||
                       decoded_i.is_fence_i || decoded_i.is_mret ||
                       decoded_i.is_sret || decoded_i.is_wfi ||
                       !exec_supported;

  // Operand b is the immediate for OP-IMM/LUI/AUIPC/JAL/JALR/branch; register
  // value for OP/branch comparisons.
  logic [31:0] operand_b;
  assign operand_b = decoded_i.uses_rs2 ? arf_rs2 : decoded_i.imm;

  p1_arf u_arf (
      .clk(clk), .reset(reset),
      .rs1_addr(decoded_i.rs1), .rs2_addr(decoded_i.rs2),
      .rs1_data(arf_rs1), .rs2_data(arf_rs2),
      .we((state_q == S_COMMIT) && !reset && item_rd_we_q &&
          (item_rd_q != 5'd0)),
      .rd_addr(item_rd_q), .rd_data(result_q),
      .debug_regs(arf_debug_o));

  p1_alu u_alu (
      .op(decoded_i.exec_op), .a(arf_rs1), .b(operand_b),
      .pc(decoded_i.pc), .imm(decoded_i.imm),
      .result(alu_result), .branch_taken(alu_branch_taken),
      .target(alu_target), .is_control(alu_is_control));

  assign next_pc_sel = (decoded_i.is_branch && !alu_branch_taken) ?
                       (decoded_i.pc + 32'd4) :
                       (alu_is_control ? alu_target : (decoded_i.pc + 32'd4));

  assign target_unaligned = alu_is_control &&
      ((decoded_i.is_branch && alu_branch_taken && (alu_target[1:0] != 2'b00)) ||
       ((decoded_i.op == OP_JAL) && (alu_target[1:0] != 2'b00)) ||
       ((decoded_i.op == OP_JALR) && (alu_target[1:0] != 2'b00)));

  // Fault priority: fetch exception, illegal encoding, unsupported legal
  // instruction, then misaligned taken control-transfer target.
  always_comb begin
    fault_select = 1'b0;
    fault_kind_sel = 2'd0;
    fault_cause_sel = 5'd0;
    fault_tval_sel = 32'b0;
    if (decoded_i.fetch_exc_valid) begin
      fault_select = 1'b1;
      fault_kind_sel = 2'd0;
      fault_cause_sel = decoded_i.fetch_exc_cause;
      fault_tval_sel = decoded_i.fetch_exc_tval;
    end else if (decoded_i.illegal) begin
      fault_select = 1'b1;
      fault_kind_sel = 2'd1;
      fault_cause_sel = decoded_i.illegal_cause;
      fault_tval_sel = decoded_i.illegal_tval;
    end else if (unsupported) begin
      fault_select = 1'b1;
      fault_kind_sel = 2'd2;
      fault_cause_sel = 5'd0;
      fault_tval_sel = decoded_i.instr;
    end else if (target_unaligned) begin
      fault_select = 1'b1;
      fault_kind_sel = 2'd3;
      fault_cause_sel = 5'd0;
      fault_tval_sel = alu_target;
    end
  end

  assign accept = (state_q == S_IDLE) && decoded_valid_i && !accept_stall_i &&
                  !reset;
  assign decoded_accept_o.accept_count = accept ? 2'd1 : 2'd0;

  always_comb begin
    commit_o = '0;
    if ((state_q == S_COMMIT) && !reset) begin
      commit_o.slot_valid = 2'b01;
      commit_o.slot[0].valid = 1'b1;
      commit_o.slot[0].token = token_q;
      commit_o.slot[0].pc = item_pc_q;
      commit_o.slot[0].instr = item_instr_q;
      commit_o.slot[0].next_pc = next_pc_q;
      commit_o.slot[0].priv = PRIV_M;
      commit_o.slot[0].rd_we = item_rd_we_q && (item_rd_q != 5'd0);
      commit_o.slot[0].rd = item_rd_q;
      commit_o.slot[0].rd_data = result_q;
      commit_o.slot[0].csr_rd_valid = 1'b0;
      commit_o.slot[0].csr_wr_valid = 1'b0;
      commit_o.slot[0].mem_valid = 1'b0;
      commit_o.slot[0].mem_we = 1'b0;
      commit_o.slot[0].mem_size = MEM_WORD;
    end

    redirect_o = '0;
    if ((state_q == S_COMMIT) && !reset && item_control_q) begin
      redirect_o.valid = 1'b1;
      redirect_o.cause = FLUSH_BRANCH;
      redirect_o.target_pc = next_pc_q;
      redirect_o.new_fetch_gen = '0;
      redirect_o.flush_all = 1'b1;
      redirect_o.cancel_pending_mem = 1'b1;
    end
  end

  assign fault_valid_o = (state_q == S_FAULT) && !reset;
  assign fault_kind_o = fault_kind_q;
  assign fault_pc_o = fault_pc_q;
  assign fault_instr_o = fault_instr_q;
  assign fault_cause_o = fault_cause_q;
  assign fault_tval_o = fault_tval_q;
  assign fault_token_o = fault_token_q;
  assign fault_fetch_gen_o = fault_fetch_gen_q;

  always_ff @(posedge clk) begin
    if (reset) begin
      state_q <= S_IDLE;
      item_pc_q <= '0;
      item_instr_q <= '0;
      item_rd_q <= '0;
      item_rd_we_q <= 1'b0;
      token_q <= '0;
      result_q <= '0;
      next_pc_q <= RESET_VECTOR;
      item_control_q <= 1'b0;
      next_gen_q <= '0;
      fault_kind_q <= 2'd0;
      fault_pc_q <= '0;
      fault_instr_q <= '0;
      fault_cause_q <= 5'd0;
      fault_tval_q <= '0;
      fault_token_q <= '0;
      fault_fetch_gen_q <= '0;
    end else begin
      if (state_q == S_IDLE) begin
        if (accept) begin
          token_q <= rob_token_t'{idx: ROB_IDX_W'(0), gen: next_gen_q};
          next_gen_q <= next_gen_q + 1'b1;
          if (fault_select) begin
            fault_kind_q <= fault_kind_sel;
            fault_pc_q <= decoded_i.pc;
            fault_instr_q <= decoded_i.instr;
            fault_cause_q <= fault_cause_sel;
            fault_tval_q <= fault_tval_sel;
            fault_token_q <= rob_token_t'{idx: ROB_IDX_W'(0), gen: next_gen_q};
            fault_fetch_gen_q <= decoded_i.fetch_gen;
            state_q <= S_FAULT;
          end else begin
            item_pc_q <= decoded_i.pc;
            item_instr_q <= decoded_i.instr;
            item_rd_q <= decoded_i.rd;
            item_rd_we_q <= decoded_i.rd_we;
            result_q <= alu_result;
            next_pc_q <= next_pc_sel;
            item_control_q <= alu_is_control;
            state_q <= S_EXEC;
          end
        end
      end else if (state_q == S_EXEC) begin
        state_q <= S_EXEC2;
      end else if (state_q == S_EXEC2) begin
        state_q <= S_EXEC3;
      end else if (state_q == S_EXEC3) begin
        state_q <= S_COMMIT;
      end else if (state_q == S_COMMIT) begin
        state_q <= S_IDLE;
      end
    end
  end

  // Exactly one commit per accepted non-fault instruction.
  always_ff @(posedge clk) begin
    if (!reset) begin
      assert (!((state_q == S_COMMIT) && fault_valid_o)) else
        $error("P1-C_INTEGER: commit and fault simultaneously");
      assert (decoded_accept_o.accept_count != 2'd2) else
        $error("P1-C_INTEGER: multi-slot accept");
    end
  end

endmodule
