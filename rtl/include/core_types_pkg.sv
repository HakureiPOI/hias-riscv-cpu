// P0-02 shared interface types. Candidate baseline for review; there is no
// CPU implementation yet. These definitions are intentionally wider than the
// P1 single-slot configuration.
package core_types_pkg;

  import core_config_pkg::*;

  // ---------------------------------------------------------------------------
  // Enumerations
  // ---------------------------------------------------------------------------

  typedef enum logic [1:0] {
    PRIV_U = 2'b00,
    PRIV_S = 2'b01,
    PRIV_M = 2'b11
  } priv_mode_e;

  typedef enum logic [1:0] {
    SLOT_0 = 2'd0,
    SLOT_1 = 2'd1
  } slot_id_e;

  typedef enum logic [2:0] {
    FU_ALU0 = 3'd0,
    FU_ALU1 = 3'd1,
    FU_BRU  = 3'd2,
    FU_MULDIV = 3'd3,
    FU_LSU  = 3'd4,
    FU_CSR  = 3'd5
  } fu_type_e;

  typedef enum logic [4:0] {
    OP_LUI    = 5'd0,
    OP_AUIPC  = 5'd1,
    OP_JAL    = 5'd2,
    OP_JALR   = 5'd3,
    OP_BRANCH = 5'd4,
    OP_LOAD   = 5'd5,
    OP_STORE  = 5'd6,
    OP_ALU_I  = 5'd7,
    OP_ALU_R  = 5'd8,
    OP_MULDIV = 5'd9,
    OP_CSR    = 5'd10,
    OP_FENCE  = 5'd11,
    OP_FENCEI = 5'd12,
    OP_ECALL  = 5'd13,
    OP_EBREAK = 5'd14,
    OP_MRET   = 5'd15,
    OP_SRET   = 5'd16,
    OP_WFI    = 5'd17
  } op_class_e;

  // Detailed operation consumed by an execution unit. op_class_e is only a
  // coarse decode class and cannot distinguish ADD/SUB, branch kinds or
  // LB/LBU by itself.
  typedef enum logic [5:0] {
    EXEC_ADD    = 6'd0,
    EXEC_SUB    = 6'd1,
    EXEC_SLL    = 6'd2,
    EXEC_SLT    = 6'd3,
    EXEC_SLTU   = 6'd4,
    EXEC_XOR    = 6'd5,
    EXEC_SRL    = 6'd6,
    EXEC_SRA    = 6'd7,
    EXEC_OR     = 6'd8,
    EXEC_AND    = 6'd9,
    EXEC_ADDI   = 6'd10,
    EXEC_SLTI   = 6'd11,
    EXEC_SLTIU  = 6'd12,
    EXEC_XORI   = 6'd13,
    EXEC_ORI    = 6'd14,
    EXEC_ANDI   = 6'd15,
    EXEC_SLLI   = 6'd16,
    EXEC_SRLI   = 6'd17,
    EXEC_SRAI   = 6'd18,
    EXEC_LUI    = 6'd19,
    EXEC_AUIPC  = 6'd20,
    EXEC_JAL    = 6'd21,
    EXEC_JALR   = 6'd22,
    EXEC_BEQ    = 6'd23,
    EXEC_BNE    = 6'd24,
    EXEC_BLT    = 6'd25,
    EXEC_BGE    = 6'd26,
    EXEC_BLTU   = 6'd27,
    EXEC_BGEU   = 6'd28,
    EXEC_LB     = 6'd29,
    EXEC_LH     = 6'd30,
    EXEC_LW     = 6'd31,
    EXEC_LBU    = 6'd32,
    EXEC_LHU    = 6'd33,
    EXEC_SB     = 6'd34,
    EXEC_SH     = 6'd35,
    EXEC_SW     = 6'd36,
    EXEC_MUL    = 6'd37,
    EXEC_MULH   = 6'd38,
    EXEC_MULHSU = 6'd39,
    EXEC_MULHU  = 6'd40,
    EXEC_DIV    = 6'd41,
    EXEC_DIVU   = 6'd42,
    EXEC_REM    = 6'd43,
    EXEC_REMU   = 6'd44,
    EXEC_CSR    = 6'd45,
    EXEC_FENCE  = 6'd46,
    EXEC_FENCEI = 6'd47,
    EXEC_ECALL  = 6'd48,
    EXEC_EBREAK = 6'd49,
    EXEC_MRET   = 6'd50,
    EXEC_SRET   = 6'd51,
    EXEC_WFI    = 6'd52
  } exec_op_e;

  typedef enum logic [1:0] {
    MEM_BYTE = 2'd0,
    MEM_HALF = 2'd1,
    MEM_WORD = 2'd2
  } mem_size_e;

  typedef enum logic [1:0] {
    FLUSH_NONE = 2'd0,
    FLUSH_BRANCH = 2'd1,
    FLUSH_TRAP = 2'd2,
    FLUSH_REPLAY = 2'd3
  } flush_cause_e;

  // CSR operation kind plus a separate immediate flag (csr_uimm_valid).
  // Keeping six enum values in two bits would overlap; the immediate variant
  // is encoded by the flag instead.
  typedef enum logic [1:0] {
    CSR_RW = 2'd0,
    CSR_RS = 2'd1,
    CSR_RC = 2'd2
  } csr_op_e;

  typedef enum logic [4:0] {
    EXC_INST_MISALIGNED   = 5'd0,
    EXC_INST_ACCESS_FAULT = 5'd1,
    EXC_ILLEGAL_INST      = 5'd2,
    EXC_BREAKPOINT        = 5'd3,
    EXC_LOAD_MISALIGNED   = 5'd4,
    EXC_LOAD_ACCESS_FAULT = 5'd5,
    EXC_STORE_MISALIGNED  = 5'd6,
    EXC_STORE_ACCESS_FAULT = 5'd7,
    EXC_ECALL_U           = 5'd8,
    EXC_ECALL_S           = 5'd9,
    EXC_ECALL_M           = 5'd11,
    EXC_INST_PAGE_FAULT   = 5'd12,
    EXC_LOAD_PAGE_FAULT   = 5'd13,
    EXC_STORE_PAGE_FAULT  = 5'd15
  } exception_cause_e;

  typedef enum logic [3:0] {
    IRQ_SSI = 4'd1,
    IRQ_MSI = 4'd3,
    IRQ_STI = 4'd5,
    IRQ_MTI = 4'd7,
    IRQ_SEI = 4'd9,
    IRQ_MEI = 4'd11
  } interrupt_cause_e;

  typedef enum logic [1:0] {
    FPU_ADD = 2'd0,
    FPU_SUB = 2'd1,
    FPU_MUL = 2'd2,
    FPU_DIV = 2'd3
  } fpu_op_e;

  typedef enum logic [2:0] {
    FPU_RNE = 3'd0,
    FPU_RTZ = 3'd1,
    FPU_RDN = 3'd2,
    FPU_RUP = 3'd3,
    FPU_RMM = 3'd4
  } fpu_rm_e;

  // ---------------------------------------------------------------------------
  // Tokens and common records
  // ---------------------------------------------------------------------------

  // Generation must be checked together with the ROB index. An index alone is
  // never sufficient to identify an in-flight instruction.
  typedef struct packed {
    logic [ROB_IDX_W-1:0] idx;
    logic [ROB_GEN_W-1:0] gen;
  } rob_token_t;

  typedef struct packed {
    rob_token_t token;
    logic       valid;
  } tagged_token_t;

  // ---------------------------------------------------------------------------
  // Fetch / decode
  // ---------------------------------------------------------------------------

  typedef struct packed {
    logic                    valid;
    logic [VA_BITS-1:0]      pc;
    logic [31:0]             instr;
    logic                    pred_taken;
    logic [VA_BITS-1:0]      pred_target;
    logic [7:0]              pred_index;
    logic                    fetch_exc_valid;
    exception_cause_e        fetch_exc_cause;
    logic [VA_BITS-1:0]      fetch_exc_tval;
    logic [FETCH_GEN_W-1:0]  fetch_gen;
  } fetch_slot_t;

  // slot_valid is a contiguous program-order prefix. accept_count is the
  // number of leading slots accepted by the consumer (0, 1, or 2).
  typedef struct packed {
    logic [NUM_SLOTS-1:0]       slot_valid;
    fetch_slot_t [NUM_SLOTS-1:0] slot;
  } fetch_bundle_t;

  typedef struct packed {
    logic                    valid;
    logic [VA_BITS-1:0]      pc;
    logic [31:0]             instr;
    op_class_e               op;
    exec_op_e                exec_op;
    logic [REG_ADDR_W-1:0]   rd;
    logic [REG_ADDR_W-1:0]   rs1;
    logic [REG_ADDR_W-1:0]   rs2;
    logic [XLEN-1:0]         imm;
    logic                    uses_rs1;
    logic                    uses_rs2;
    logic                    rd_we;
    logic                    is_branch;
    logic                    is_jump;
    logic                    is_load;
    logic                    is_store;
    logic                    is_csr;
    logic                    is_fence;
    logic                    is_fence_i;
    logic                    is_mret;
    logic                    is_sret;
    logic                    is_wfi;
    logic                    illegal;
    exception_cause_e        illegal_cause;
    logic [XLEN-1:0]         illegal_tval;
    mem_size_e               mem_size;
    csr_op_e                 csr_op;
    logic [CSR_ADDR_W-1:0]   csr_addr;
    logic [4:0]              csr_uimm;
    logic                    csr_uimm_valid;
    logic [7:0]              pred_index;
    logic                    fetch_exc_valid;
    exception_cause_e        fetch_exc_cause;
    logic [VA_BITS-1:0]      fetch_exc_tval;
    logic [FETCH_GEN_W-1:0]  fetch_gen;
    logic                    pred_taken;
    logic [VA_BITS-1:0]      pred_target;
  } decoded_slot_t;

  typedef struct packed {
    logic [NUM_SLOTS-1:0]        slot_valid;
    decoded_slot_t [NUM_SLOTS-1:0] slot;
  } decoded_bundle_t;

  // ---------------------------------------------------------------------------
  // Rename / dispatch
  // ---------------------------------------------------------------------------

  typedef struct packed {
    logic                    valid;
    rob_token_t              token;
    op_class_e               op;
    exec_op_e                exec_op;
    logic [REG_ADDR_W-1:0]   rd;
    logic [REG_ADDR_W-1:0]   rs1;
    logic [REG_ADDR_W-1:0]   rs2;
    logic                    rd_we;
    logic                    src1_ready;
    logic [XLEN-1:0]         src1_value;
    rob_token_t              src1_tag;
    logic                    src2_ready;
    logic [XLEN-1:0]         src2_value;
    rob_token_t              src2_tag;
    logic [XLEN-1:0]         imm;
    logic [VA_BITS-1:0]      pc;
    logic [31:0]             instr;
    mem_size_e               mem_size;
    csr_op_e                 csr_op;
    logic [CSR_ADDR_W-1:0]   csr_addr;
    logic [XLEN-1:0]         csr_wdata;
    logic [4:0]              csr_uimm;
    logic                    csr_uimm_valid;
    logic [7:0]              pred_index;
    logic                    fetch_exc_valid;
    exception_cause_e        fetch_exc_cause;
    logic [VA_BITS-1:0]      fetch_exc_tval;
    logic [FETCH_GEN_W-1:0]  fetch_gen;
    logic                    illegal;
    exception_cause_e        illegal_cause;
    logic [XLEN-1:0]         illegal_tval;
    logic                    pred_taken;
    logic [VA_BITS-1:0]      pred_target;
    logic [XLEN-1:0]         next_pc;
    logic                    is_load;
    logic                    is_store;
    logic                    is_csr;
    logic                    is_fence;
    logic                    is_fence_i;
    logic                    is_mret;
    logic                    is_sret;
    logic                    is_wfi;
  } renamed_slot_t;

  // Reverse prefix-accept response. The sender keeps the complete bundle
  // stable until the consumer returns accept_count; the consumer accepts only
  // the leading 0/1/2 slots in program order.
  typedef struct packed {
    logic [1:0] accept_count;
  } prefix_accept_t;

  typedef prefix_accept_t fetch_accept_t;
  typedef prefix_accept_t decode_accept_t;
  typedef prefix_accept_t dispatch_accept_t;

  typedef struct packed {
    logic [NUM_SLOTS-1:0]       slot_valid;
    renamed_slot_t [NUM_SLOTS-1:0] slot;
  } dispatch_bundle_t;

  // ---------------------------------------------------------------------------
  // Issue / execute / writeback
  // ---------------------------------------------------------------------------

  typedef struct packed {
    logic                    valid;
    rob_token_t              token;
    fu_type_e                fu;
    op_class_e               op;
    exec_op_e                exec_op;
    logic [31:0]             instr;
    logic [XLEN-1:0]         src1;
    logic [XLEN-1:0]         src2;
    logic [XLEN-1:0]         imm;
    logic [VA_BITS-1:0]      pc;
    logic [REG_ADDR_W-1:0]   rd;
    logic                    rd_we;
    mem_size_e               mem_size;
    csr_op_e                 csr_op;
    logic [CSR_ADDR_W-1:0]   csr_addr;
    logic [XLEN-1:0]         csr_wdata;
    logic [4:0]              csr_uimm;
    logic                    csr_uimm_valid;
    logic [7:0]              pred_index;
    logic                    fetch_exc_valid;
    exception_cause_e        fetch_exc_cause;
    logic [VA_BITS-1:0]      fetch_exc_tval;
    logic                    illegal;
    exception_cause_e        illegal_cause;
    logic [XLEN-1:0]         illegal_tval;
    logic                    pred_taken;
    logic [VA_BITS-1:0]      pred_target;
    logic [XLEN-1:0]         next_pc;
  } issue_slot_t;

  typedef struct packed {
    logic [NUM_SLOTS-1:0]    slot_valid;
    issue_slot_t [NUM_SLOTS-1:0] slot;
  } issue_bundle_t;

  typedef struct packed {
    logic                    valid;
    rob_token_t              token;
    logic [XLEN-1:0]         result;
    logic                    exc_valid;
    exception_cause_e        exc_cause;
    logic [XLEN-1:0]         exc_tval;
    logic                    branch_resolved;
    logic                    branch_taken;
    logic [VA_BITS-1:0]      actual_next_pc;
    logic                    mem_wb_valid;
    logic [XLEN-1:0]         mem_rdata;
  } wb_msg_t;

  typedef struct packed {
    logic [1:0]              msg_valid;
    wb_msg_t [1:0]           msg;
  } wb_bundle_t;

  // ---------------------------------------------------------------------------
  // Commit / retire / trap
  // ---------------------------------------------------------------------------

  // Normal retirement record. Optional observations use explicit valid bits;
  // a zero value is never used to mean "not observed".
  typedef struct packed {
    logic                    valid;
    rob_token_t              token;
    logic [VA_BITS-1:0]      pc;
    logic [31:0]             instr;
    logic [VA_BITS-1:0]      next_pc;
    priv_mode_e              priv;
    logic                    rd_we;
    logic [REG_ADDR_W-1:0]   rd;
    logic [XLEN-1:0]         rd_data;
    logic                    csr_rd_valid;
    logic                    csr_wr_valid;
    logic [CSR_ADDR_W-1:0]   csr_addr;
    logic [XLEN-1:0]         csr_wdata;
    logic [XLEN-1:0]         csr_rdata;
    logic                    mem_valid;
    logic                    mem_we;
    logic [VA_BITS-1:0]      mem_va;
    logic [PA_BITS-1:0]      mem_pa;
    mem_size_e               mem_size;
    logic [BYTE_MASK_W-1:0]  mem_mask;
    logic [XLEN-1:0]         mem_wdata;
    logic [XLEN-1:0]         mem_rdata;
  } retire_record_t;

  typedef struct packed {
    logic                    valid;
    logic [VA_BITS-1:0]      pc;
    logic [VA_BITS-1:0]      epc;
    logic [VA_BITS-1:0]      target_pc;
    exception_cause_e        cause;
    logic                    is_interrupt;
    logic [XLEN-1:0]         tval;
    priv_mode_e              from_priv;
    priv_mode_e              to_priv;
    logic [XLEN-1:0]         mstatus_before;
    logic [XLEN-1:0]         mstatus_after;
    logic [XLEN-1:0]         cause_csr_before;
    logic [XLEN-1:0]         cause_csr_after;
    logic [XLEN-1:0]         epc_csr_before;
    logic [XLEN-1:0]         epc_csr_after;
  } trap_event_t;

  typedef struct packed {
    logic [1:0]              slot_valid;
    retire_record_t [1:0]    slot;
    logic                    trap_valid;
    trap_event_t             trap;
  } commit_bundle_t;

  // ---------------------------------------------------------------------------
  // Memory request/response
  // ---------------------------------------------------------------------------

  typedef struct packed {
    logic                    valid;
    logic                    is_store;
    logic [VA_BITS-1:0]      va;
    logic [PA_BITS-1:0]      pa;
    mem_size_e               size;
    logic [BYTE_MASK_W-1:0]  byte_mask;
    logic [XLEN-1:0]         wdata;
    logic                    cacheable;
    priv_mode_e              priv;
    logic [REQ_ID_W-1:0]     req_id;
    logic [ROB_GEN_W-1:0]    gen;
  } mem_req_t;

  typedef struct packed {
    logic                    valid;
    logic [REQ_ID_W-1:0]     req_id;
    logic [ROB_GEN_W-1:0]    gen;
    logic [XLEN-1:0]         rdata;
    logic                    error;
    exception_cause_e        error_cause;
  } mem_resp_t;

  // ---------------------------------------------------------------------------
  // Redirect / flush
  // ---------------------------------------------------------------------------

  typedef struct packed {
    logic                    valid;
    flush_cause_e            cause;
    logic [VA_BITS-1:0]      target_pc;
    logic [FETCH_GEN_W-1:0]  new_fetch_gen;
    logic                    flush_all;
    logic                    cancel_pending_mem;
  } redirect_t;

  // ---------------------------------------------------------------------------
  // Independent FPU interface
  // ---------------------------------------------------------------------------

  typedef struct packed {
    logic                    valid;
    rob_token_t              token;
    fpu_op_e                 op;
    logic [31:0]             a;
    logic [31:0]             b;
    fpu_rm_e                 rm;
    logic [FPU_TXN_ID_W-1:0] txn_id;
  } fpu_req_t;

  typedef struct packed {
    logic                    valid;
    logic [FPU_TXN_ID_W-1:0] txn_id;
    logic [31:0]             result;
    logic [FPU_FLAGS_W-1:0]  flags;
    logic                    error;
  } fpu_resp_t;

  // ---------------------------------------------------------------------------
  // Simulation-only trace extension
  // ---------------------------------------------------------------------------

  // The global sequence number and full retirement history are verification
  // aids. They must not be on the synthesizable critical path.
  typedef struct packed {
    logic [63:0]             seq;
    retire_record_t          record;
  } retire_trace_t;

endpackage
