// Scalar testbench wrapper for p1_decode.
module decode_tb_top (
    input  logic        fetch_valid,
    input  logic [31:0] fetch_pc,
    input  logic [31:0] fetch_instr,
    input  logic        fetch_pred_taken,
    input  logic [31:0] fetch_pred_target,
    input  logic [7:0]  fetch_pred_index,
    input  logic        fetch_exc_valid,
    input  logic [4:0]  fetch_exc_cause,
    input  logic [31:0] fetch_exc_tval,
    input  logic [7:0]  fetch_gen,

    output logic        dec_valid,
    output logic [31:0] dec_pc,
    output logic [31:0] dec_instr,
    output logic [4:0]  dec_op,
    output logic [5:0]  dec_exec,
    output logic [4:0]  dec_rd,
    output logic [4:0]  dec_rs1,
    output logic [4:0]  dec_rs2,
    output logic [31:0] dec_imm,
    output logic        dec_uses1,
    output logic        dec_uses2,
    output logic        dec_rd_we,
    output logic        dec_is_branch,
    output logic        dec_is_jump,
    output logic        dec_is_load,
    output logic        dec_is_store,
    output logic        dec_is_csr,
    output logic        dec_is_fence,
    output logic        dec_is_fence_i,
    output logic        dec_is_mret,
    output logic        dec_is_sret,
    output logic        dec_is_wfi,
    output logic        dec_illegal,
    output logic [4:0]  dec_illegal_cause,
    output logic [31:0] dec_illegal_tval,
    output logic [1:0]  dec_mem_size,
    output logic [1:0]  dec_csr_op,
    output logic [11:0] dec_csr_addr,
    output logic [4:0]  dec_csr_uimm,
    output logic        dec_csr_uimm_valid,
    output logic [7:0]  dec_pred_index,
    output logic        dec_fetch_exc_valid,
    output logic [4:0]  dec_fetch_exc_cause,
    output logic [31:0] dec_fetch_exc_tval,
    output logic [7:0]  dec_fetch_gen,
    output logic        dec_pred_taken,
    output logic [31:0] dec_pred_target
);

  import core_types_pkg::*;

  fetch_slot_t fetch;
  decoded_slot_t decoded;

  always_comb begin
    fetch = '0;
    fetch.valid = fetch_valid;
    fetch.pc = fetch_pc;
    fetch.instr = fetch_instr;
    fetch.pred_taken = fetch_pred_taken;
    fetch.pred_target = fetch_pred_target;
    fetch.pred_index = fetch_pred_index;
    fetch.fetch_exc_valid = fetch_exc_valid;
    fetch.fetch_exc_cause = exception_cause_e'(fetch_exc_cause);
    fetch.fetch_exc_tval = fetch_exc_tval;
    fetch.fetch_gen = fetch_gen;
  end

  p1_decode dut (.fetch_i(fetch), .decoded_o(decoded));

  assign dec_valid = decoded.valid;
  assign dec_pc = decoded.pc;
  assign dec_instr = decoded.instr;
  assign dec_op = decoded.op;
  assign dec_exec = decoded.exec_op;
  assign dec_rd = decoded.rd;
  assign dec_rs1 = decoded.rs1;
  assign dec_rs2 = decoded.rs2;
  assign dec_imm = decoded.imm;
  assign dec_uses1 = decoded.uses_rs1;
  assign dec_uses2 = decoded.uses_rs2;
  assign dec_rd_we = decoded.rd_we;
  assign dec_is_branch = decoded.is_branch;
  assign dec_is_jump = decoded.is_jump;
  assign dec_is_load = decoded.is_load;
  assign dec_is_store = decoded.is_store;
  assign dec_is_csr = decoded.is_csr;
  assign dec_is_fence = decoded.is_fence;
  assign dec_is_fence_i = decoded.is_fence_i;
  assign dec_is_mret = decoded.is_mret;
  assign dec_is_sret = decoded.is_sret;
  assign dec_is_wfi = decoded.is_wfi;
  assign dec_illegal = decoded.illegal;
  assign dec_illegal_cause = decoded.illegal_cause;
  assign dec_illegal_tval = decoded.illegal_tval;
  assign dec_mem_size = decoded.mem_size;
  assign dec_csr_op = decoded.csr_op;
  assign dec_csr_addr = decoded.csr_addr;
  assign dec_csr_uimm = decoded.csr_uimm;
  assign dec_csr_uimm_valid = decoded.csr_uimm_valid;
  assign dec_pred_index = decoded.pred_index;
  assign dec_fetch_exc_valid = decoded.fetch_exc_valid;
  assign dec_fetch_exc_cause = decoded.fetch_exc_cause;
  assign dec_fetch_exc_tval = decoded.fetch_exc_tval;
  assign dec_fetch_gen = decoded.fetch_gen;
  assign dec_pred_taken = decoded.pred_taken;
  assign dec_pred_target = decoded.pred_target;

endmodule
