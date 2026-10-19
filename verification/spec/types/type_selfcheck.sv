// P0-02 shared type self-check fixture.
//
// This is a compile/layout check, not a processor. It imports the shared
// packages, verifies key widths and struct layouts, and fails elaboration if
// the candidate interface contradicts core_config_pkg.
module type_selfcheck;

  import core_config_pkg::*;
  import core_types_pkg::*;

  // Base width checks.
  initial begin
    if (XLEN != 32) $fatal(1, "P0-02_TYPE_FAIL: XLEN=%0d", XLEN);
    if (VA_BITS != 32) $fatal(1, "P0-02_TYPE_FAIL: VA_BITS=%0d", VA_BITS);
    if (PA_BITS != 34) $fatal(1, "P0-02_TYPE_FAIL: PA_BITS=%0d", PA_BITS);
    if (NUM_SLOTS != 2) $fatal(1, "P0-02_TYPE_FAIL: NUM_SLOTS=%0d", NUM_SLOTS);
    if (ROB_ENTRIES != 32) $fatal(1, "P0-02_TYPE_FAIL: ROB_ENTRIES=%0d", ROB_ENTRIES);
    if (IQ_ENTRIES != 16) $fatal(1, "P0-02_TYPE_FAIL: IQ_ENTRIES=%0d", IQ_ENTRIES);
    if (MEM_FIFO_ENTRIES != 8) $fatal(1, "P0-02_TYPE_FAIL: MEM_FIFO_ENTRIES=%0d", MEM_FIFO_ENTRIES);
    if (BYTE_MASK_W != 4) $fatal(1, "P0-02_TYPE_FAIL: BYTE_MASK_W=%0d", BYTE_MASK_W);
    if (ROB_IDX_W != 5) $fatal(1, "P0-02_TYPE_FAIL: ROB_IDX_W=%0d", ROB_IDX_W);
    if (PPN_W != 22) $fatal(1, "P0-02_TYPE_FAIL: PPN_W=%0d", PPN_W);
    if (VPN_W != 20) $fatal(1, "P0-02_TYPE_FAIL: VPN_W=%0d", VPN_W);

    // Token layout: generation must be part of the identity.
    if ($bits(rob_token_t) != ROB_IDX_W + ROB_GEN_W)
      $fatal(1, "P0-02_TYPE_FAIL: rob_token_t width=%0d", $bits(rob_token_t));

    // Two-slot bundles carry exactly two records.
    if ($bits(fetch_bundle_t) != 2 + 2 * $bits(fetch_slot_t))
      $fatal(1, "P0-02_TYPE_FAIL: fetch_bundle_t width=%0d", $bits(fetch_bundle_t));
    if ($bits(wb_bundle_t) != 2 + 2 * $bits(wb_msg_t))
      $fatal(1, "P0-02_TYPE_FAIL: wb_bundle_t width=%0d", $bits(wb_bundle_t));
    if ($bits(redirect_t) < VA_BITS + FETCH_GEN_W + 2 + 2)
      $fatal(1, "P0-02_TYPE_FAIL: redirect_t too narrow");
    if ($bits(dispatch_bundle_t) != 2 + 2 + 2 * $bits(renamed_slot_t))
      $fatal(1, "P0-02_TYPE_FAIL: dispatch_bundle_t width=%0d", $bits(dispatch_bundle_t));
    if ($bits(issue_bundle_t) != 2 + 2 * $bits(issue_slot_t))
      $fatal(1, "P0-02_TYPE_FAIL: issue_bundle_t width=%0d", $bits(issue_bundle_t));
    if ($bits(commit_bundle_t) != 2 + 2 * $bits(retire_record_t) + 1 + $bits(trap_event_t))
      $fatal(1, "P0-02_TYPE_FAIL: commit_bundle_t width=%0d", $bits(commit_bundle_t));

    // Memory request carries byte mask and request identity.
    if ($bits(mem_req_t) < BYTE_MASK_W + REQ_ID_W + ROB_GEN_W)
      $fatal(1, "P0-02_TYPE_FAIL: mem_req_t too narrow");

    // FPU request/response carry transaction ID.
    if ($bits(fpu_req_t) < FPU_TXN_ID_W + 32 + 32 + 3)
      $fatal(1, "P0-02_TYPE_FAIL: fpu_req_t too narrow");
    if ($bits(fpu_resp_t) < FPU_TXN_ID_W + 32 + FPU_FLAGS_W)
      $fatal(1, "P0-02_TYPE_FAIL: fpu_resp_t too narrow");

    // Platform constants must match config/platform.json.
    if (RAM_BASE != 34'h8000_0000)
      $fatal(1, "P0-02_TYPE_FAIL: RAM_BASE=0x%0h", RAM_BASE);
    if (RAM_SIZE != 34'h0002_0000)
      $fatal(1, "P0-02_TYPE_FAIL: RAM_SIZE=0x%0h", RAM_SIZE);
    if (RAM_END != 34'h8002_0000)
      $fatal(1, "P0-02_TYPE_FAIL: RAM_END=0x%0h", RAM_END);

    // Construct representative values so the compiler type-checks every field
    // path used by the interface documentation. The local variables are
    // written only to force type/layout checking; the fixture is not a CPU.
    /* verilator lint_off UNUSEDSIGNAL */
    begin : layout_probe
      fetch_slot_t fetch;
      decoded_slot_t decoded;
      renamed_slot_t renamed;
      issue_slot_t issue;
      wb_msg_t wb;
      retire_record_t retire;
      trap_event_t trap;
      commit_bundle_t commit;
      mem_req_t req;
      mem_resp_t resp;
      redirect_t redirect;
      fpu_req_t fpu_req;
      fpu_resp_t fpu_resp;

      fetch = '0;
      fetch.valid = 1'b1;
      fetch.pc = 32'h8000_0000;
      fetch.instr = 32'h0000_0013;
      fetch.fetch_gen = 8'h01;

      decoded = '0;
      decoded.valid = 1'b1;
      decoded.pc = 32'h8000_0004;
      decoded.instr = 32'h0010_0093;
      decoded.op = OP_ALU_I;
      decoded.rd = 5'd1;
      decoded.rs1 = 5'd0;
      decoded.rd_we = 1'b1;
      decoded.mem_size = MEM_WORD;

      renamed = '0;
      renamed.valid = 1'b1;
      renamed.token = '{idx: 5'd3, gen: 8'h2a};
      renamed.op = OP_ALU_R;
      renamed.rd = 5'd5;
      renamed.rd_we = 1'b1;
      renamed.src1_ready = 1'b1;
      renamed.src1_value = 32'hdead_beef;
      renamed.next_pc = 32'h8000_0008;

      issue = '0;
      issue.valid = 1'b1;
      issue.token = renamed.token;
      issue.fu = FU_ALU0;
      issue.op = OP_ALU_R;
      issue.src1 = 32'h0000_0001;
      issue.src2 = 32'h0000_0002;
      issue.rd = 5'd5;
      issue.rd_we = 1'b1;

      wb = '0;
      wb.valid = 1'b1;
      wb.token = renamed.token;
      wb.result = 32'h0000_0003;

      retire = '0;
      retire.valid = 1'b1;
      retire.seq = 64'd1;
      retire.token = renamed.token;
      retire.pc = 32'h8000_0004;
      retire.instr = 32'h0020_8293;
      retire.next_pc = 32'h8000_0008;
      retire.priv = PRIV_M;
      retire.rd_we = 1'b1;
      retire.rd = 5'd5;
      retire.rd_data = 32'h0000_0003;

      trap = '0;
      trap.valid = 1'b1;
      trap.pc = 32'h8000_0010;
      trap.epc = 32'h8000_0010;
      trap.target_pc = 32'h8000_0100;
      trap.cause = EXC_ECALL_M;
      trap.is_interrupt = 1'b0;
      trap.tval = 32'h0000_0000;
      trap.from_priv = PRIV_M;
      trap.to_priv = PRIV_M;

      commit = '0;
      commit.slot_valid = 2'b01;
      commit.slot[0] = retire;
      commit.trap_valid = 1'b0;

      req = '0;
      req.valid = 1'b1;
      req.is_store = 1'b1;
      req.va = 32'h8000_0100;
      req.pa = 34'h0_8000_0100;
      req.size = MEM_WORD;
      req.byte_mask = 4'b1111;
      req.wdata = 32'h1234_5678;
      req.req_id = 6'd7;
      req.gen = 8'h2a;

      resp = '0;
      resp.valid = 1'b1;
      resp.req_id = req.req_id;
      resp.gen = req.gen;
      resp.rdata = 32'h1234_5678;

      redirect = '0;
      redirect.valid = 1'b1;
      redirect.cause = FLUSH_BRANCH;
      redirect.target_pc = 32'h8000_0020;
      redirect.new_fetch_gen = 8'h03;
      redirect.flush_all = 1'b1;

      fpu_req = '0;
      fpu_req.valid = 1'b1;
      fpu_req.op = FPU_ADD;
      fpu_req.a = 32'h3f80_0000;
      fpu_req.b = 32'h4000_0000;
      fpu_req.rm = FPU_RNE;
      fpu_req.txn_id = 6'd1;

      fpu_resp = '0;
      fpu_resp.valid = 1'b1;
      fpu_resp.txn_id = fpu_req.txn_id;
      fpu_resp.result = 32'h4040_0000;
      fpu_resp.flags = 5'b0;

      if (retire.token != renamed.token)
        $fatal(1, "P0-02_TYPE_FAIL: retire token mismatch");
      if (req.byte_mask != 4'b1111)
        $fatal(1, "P0-02_TYPE_FAIL: byte mask layout");
    end
    /* verilator lint_on UNUSEDSIGNAL */

    $display("P0-02_TYPE_SELFCHECK_PASS bits: fetch_slot=%0d decoded_slot=%0d renamed_slot=%0d issue_slot=%0d retire=%0d trap=%0d commit=%0d mem_req=%0d",
             $bits(fetch_slot_t), $bits(decoded_slot_t), $bits(renamed_slot_t),
             $bits(issue_slot_t), $bits(retire_record_t), $bits(trap_event_t),
             $bits(commit_bundle_t), $bits(mem_req_t));
    $finish;
  end

endmodule
