// Scalar testbench wrapper around the frozen struct interfaces.
module ram_bridge_tb_top (
    input  logic        clk,
    input  logic        reset,
    input  logic        load_valid,
    input  logic [14:0] load_word_addr,
    input  logic [31:0] load_data,
    input  logic        flush_i,
    input  logic [1:0]  resp_delay_i,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_is_store,
    input  logic [31:0] req_va,
    input  logic [33:0] req_pa,
    input  logic [1:0]  req_size,
    input  logic [3:0]  req_byte_mask,
    input  logic [31:0] req_wdata,
    input  logic        req_cacheable,
    input  logic [1:0]  req_priv,
    input  logic [5:0]  req_id,
    input  logic [7:0]  req_gen,

    output logic        resp_valid,
    input  logic        resp_ready,
    output logic [5:0]  resp_id,
    output logic [7:0]  resp_gen,
    output logic [31:0] resp_rdata,
    output logic        resp_error,
    output logic [4:0]  resp_cause
);

  import core_types_pkg::*;

  mem_req_t  req;
  mem_resp_t resp;

  always_comb begin
    req = '0;
    req.valid = req_valid;
    req.is_store = req_is_store;
    req.va = req_va;
    req.pa = req_pa;
    req.size = mem_size_e'(req_size);
    req.byte_mask = req_byte_mask;
    req.wdata = req_wdata;
    req.cacheable = req_cacheable;
    req.priv = priv_mode_e'(req_priv);
    req.req_id = req_id;
    req.gen = req_gen;
  end

  ram_bridge dut (
      .clk(clk), .reset(reset),
      .load_valid(load_valid), .load_word_addr(load_word_addr),
      .load_data(load_data),
      .flush_i(flush_i),
      .req_i(req), .req_ready_o(req_ready),
      .resp_o(resp), .resp_ready_i(resp_ready),
      .resp_delay_i(resp_delay_i));

  assign resp_valid = resp.valid;
  assign resp_id = resp.req_id;
  assign resp_gen = resp.gen;
  assign resp_rdata = resp.rdata;
  assign resp_error = resp.error;
  assign resp_cause = resp.error_cause;

endmodule
