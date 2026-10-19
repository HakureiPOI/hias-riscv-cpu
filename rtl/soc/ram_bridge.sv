// P1-A single-transaction RAM bridge.
//
// Contract:
//   - accepted requests are not cancelled by flush_i; a store is irrevocable
//     once accepted, a load response may be returned and discarded by the
//     caller using req_id/gen.
//   - request and response payloads remain stable while backpressured.
//   - one request in flight; every accepted request produces exactly one
//     response with the original req_id/gen.
//   - all range/alignment/size/mask checks happen before any RAM write.
module ram_bridge (
    input  logic        clk,
    input  logic        reset,
    input  logic        load_valid,
    input  logic [14:0] load_word_addr,
    input  logic [31:0] load_data,
    input  logic        flush_i,       // cancels only not-yet-accepted requests
    input  core_types_pkg::mem_req_t  req_i,
    output logic        req_ready_o,
    output core_types_pkg::mem_resp_t resp_o,
    input  logic        resp_ready_i,
    input  logic [1:0]  resp_delay_i
);

  import core_config_pkg::*;
  import core_types_pkg::*;

  logic        busy_q;
  mem_resp_t   resp_q;
  logic [REQ_ID_W-1:0] id_q;
  logic [ROB_GEN_W-1:0] gen_q;
  logic        is_store_q;
  logic [1:0]  size_q;
  logic [1:0]  lane_q;
  logic [1:0]  lane_captured_q;

  // RAM port.
  logic        ram_req;
  logic        ram_ready;
  logic [14:0] ram_addr;
  logic [3:0]  ram_mask;
  logic [31:0] ram_wdata;
  logic        ram_resp_valid;
  logic [31:0] ram_rdata;
  logic        unused_req;

  // Validation (combinational) for the presented request.
  logic [2:0]  size_bytes;
  logic        in_range;
  logic        aligned;
  logic        mask_ok;
  logic        wdata_ok;
  logic        legal;
  exception_cause_e err_cause;

  always_comb begin
    size_bytes = 3'd0;
    case (req_i.size)
      MEM_BYTE: size_bytes = 3'd1;
      MEM_HALF: size_bytes = 3'd2;
      MEM_WORD: size_bytes = 3'd4;
      default:  size_bytes = 3'd0;
    endcase

    in_range = (req_i.pa >= RAM_BASE) &&
               (req_i.pa + PA_BITS'(size_bytes) <= RAM_END);
    lane_q = req_i.pa[1:0];
    aligned = (req_i.size == MEM_BYTE) ||
              ((req_i.size == MEM_HALF) && (req_i.pa[0] == 1'b0)) ||
              ((req_i.size == MEM_WORD) && (req_i.pa[1:0] == 2'b00));

    case (req_i.size)
      MEM_BYTE: mask_ok = (req_i.byte_mask == (4'b0001 << lane_q));
      MEM_HALF: mask_ok = (req_i.byte_mask == (4'b0011 << lane_q));
      MEM_WORD: mask_ok = (req_i.byte_mask == 4'b1111);
      default:  mask_ok = 1'b0;
    endcase

    case (req_i.size)
      MEM_BYTE: wdata_ok = (req_i.wdata[31:8] == 24'd0);
      MEM_HALF: wdata_ok = (req_i.wdata[31:16] == 16'd0);
      MEM_WORD: wdata_ok = 1'b1;
      default:  wdata_ok = 1'b0;
    endcase

    legal = in_range && aligned && mask_ok &&
            (!req_i.is_store || wdata_ok);

    if (!in_range) begin
      err_cause = req_i.is_store ? EXC_STORE_ACCESS_FAULT : EXC_LOAD_ACCESS_FAULT;
    end else if (!aligned) begin
      err_cause = req_i.is_store ? EXC_STORE_MISALIGNED : EXC_LOAD_MISALIGNED;
    end else begin
      err_cause = req_i.is_store ? EXC_STORE_ACCESS_FAULT : EXC_LOAD_ACCESS_FAULT;
    end
  end

  // Lane-aligned store data: low scalar bytes placed at the target lanes.
  logic [31:0] lane_wdata;
  always_comb begin
    case (req_i.size)
      MEM_BYTE: lane_wdata = 32'(req_i.wdata[7:0]) << (8 * lane_q);
      MEM_HALF: lane_wdata = 32'(req_i.wdata[15:0]) << (8 * lane_q);
      MEM_WORD: lane_wdata = req_i.wdata;
      default:  lane_wdata = '0;
    endcase
  end

  assign req_ready_o = !busy_q && (!resp_q.valid || resp_ready_i) && !flush_i;
  assign ram_req = req_i.valid && req_ready_o && legal;
  assign ram_addr = req_i.pa[16:2];
  assign ram_mask = req_i.byte_mask;
  assign ram_wdata = lane_wdata;
  assign resp_o = resp_q;
  assign unused_req = ^req_i;

  ram_128k u_ram (
      .clk(clk), .reset(reset),
      .load_valid(load_valid), .load_word_addr(load_word_addr),
      .load_data(load_data),
      .req(ram_req), .ready(ram_ready),
      .we(req_i.is_store), .word_addr(ram_addr),
      .byte_mask(ram_mask), .wdata(ram_wdata),
      .resp_delay(resp_delay_i),
      .resp_valid(ram_resp_valid), .resp_ready(1'b1), .rdata(ram_rdata));

  always_ff @(posedge clk) begin
    if (reset) begin
      busy_q <= 1'b0;
      resp_q <= '0;
      id_q <= '0;
      gen_q <= '0;
      is_store_q <= 1'b0;
      size_q <= 2'd0;
    end else begin
      if (resp_q.valid && resp_ready_i) resp_q.valid <= 1'b0;

      if (req_i.valid && req_ready_o) begin
        id_q <= req_i.req_id;
        gen_q <= req_i.gen;
        is_store_q <= req_i.is_store;
        size_q <= 2'(req_i.size);
        lane_captured_q <= req_i.pa[1:0];
        if (!legal) begin
          resp_q.valid <= 1'b1;
          resp_q.req_id <= req_i.req_id;
          resp_q.gen <= req_i.gen;
          resp_q.rdata <= '0;
          resp_q.error <= 1'b1;
          resp_q.error_cause <= err_cause;
        end else begin
          busy_q <= 1'b1;
        end
      end

      if (ram_resp_valid) begin
        busy_q <= 1'b0;
        resp_q.valid <= 1'b1;
        resp_q.req_id <= id_q;
        resp_q.gen <= gen_q;
        resp_q.error <= 1'b0;
        resp_q.error_cause <= EXC_INST_ACCESS_FAULT; // don't-care when error=0
        if (is_store_q) begin
          resp_q.rdata <= '0;
        end else begin
          automatic logic [2:0] nbytes = 3'd1 << size_q;
          automatic logic [31:0] mask = 32'((1 << (8 * nbytes)) - 1);
          resp_q.rdata <= (ram_rdata >> (8 * lane_captured_q)) & mask;
        end
      end
    end
  end

  // Contract checks.
  always_ff @(posedge clk) begin
    if (!reset) begin
      assert (!(resp_q.valid && busy_q)) else
        $error("P1-A_BRIDGE: response and busy simultaneously");
      if (req_i.valid && req_ready_o && !legal)
        assert (!ram_req) else
          $error("P1-A_BRIDGE: illegal request reached RAM");
      if (ram_req)
        assert (ram_ready) else
          $error("P1-A_BRIDGE: RAM not ready for accepted request");
    end
  end

endmodule
