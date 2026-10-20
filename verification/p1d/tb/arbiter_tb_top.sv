module arbiter_tb_top (
    input  logic        clk,
    input  logic        reset,

    input  logic        fetch_valid,
    input  logic        fetch_is_store,
    input  logic [31:0] fetch_va,
    input  logic [33:0] fetch_pa,
    input  logic [1:0]  fetch_size,
    input  logic [3:0]  fetch_mask,
    input  logic [31:0] fetch_wdata,
    input  logic [5:0]  fetch_id,
    input  logic [7:0]  fetch_gen,
    output logic        fetch_ready,
    output logic        fetch_resp_valid,
    input  logic        fetch_resp_ready,

    input  logic        lsu_valid,
    input  logic        lsu_is_store,
    input  logic [31:0] lsu_va,
    input  logic [33:0] lsu_pa,
    input  logic [1:0]  lsu_size,
    input  logic [3:0]  lsu_mask,
    input  logic [31:0] lsu_wdata,
    input  logic [5:0]  lsu_id,
    input  logic [7:0]  lsu_gen,
    output logic        lsu_ready,
    output logic        lsu_resp_valid,
    input  logic        lsu_resp_ready,

    input  logic        bus_ready,
    input  logic        bus_resp_valid,
    input  logic [5:0]  bus_resp_id,
    input  logic [7:0]  bus_resp_gen,
    input  logic [31:0] bus_resp_rdata,
    input  logic        bus_resp_error,
    output logic        bus_req_valid,
    output logic        bus_req_is_store,
    output logic [31:0] bus_req_va,
    output logic [33:0] bus_req_pa,
    output logic [1:0]  bus_req_size,
    output logic [3:0]  bus_req_mask,
    output logic [31:0] bus_req_wdata,
    output logic [5:0]  bus_req_id,
    output logic [7:0]  bus_req_gen,
    output logic        bus_resp_ready,
    output logic        fetch_outstanding,
    output logic        lsu_outstanding
);
  import core_types_pkg::*;
  /* verilator lint_off UNUSEDSIGNAL */
  mem_req_t fr, lr, br;
  mem_resp_t fresp, lresp, bresp;
  /* verilator lint_on UNUSEDSIGNAL */
  always_comb begin
    fr = '0; fr.valid = fetch_valid; fr.is_store = fetch_is_store;
    fr.va = fetch_va; fr.pa = fetch_pa; fr.size = mem_size_e'(fetch_size);
    fr.byte_mask = fetch_mask; fr.wdata = fetch_wdata; fr.cacheable = 1'b1;
    fr.priv = PRIV_M; fr.req_id = fetch_id; fr.gen = fetch_gen;
    lr = '0; lr.valid = lsu_valid; lr.is_store = lsu_is_store;
    lr.va = lsu_va; lr.pa = lsu_pa; lr.size = mem_size_e'(lsu_size);
    lr.byte_mask = lsu_mask; lr.wdata = lsu_wdata; lr.cacheable = 1'b1;
    lr.priv = PRIV_M; lr.req_id = lsu_id; lr.gen = lsu_gen;
    bresp = '0; bresp.valid = bus_resp_valid; bresp.req_id = bus_resp_id;
    bresp.gen = bus_resp_gen; bresp.rdata = bus_resp_rdata;
    bresp.error = bus_resp_error;
  end
  assign bus_req_valid = br.valid;
  assign bus_req_is_store = br.is_store;
  assign bus_req_va = br.va;
  assign bus_req_pa = br.pa;
  assign bus_req_size = br.size;
  assign bus_req_mask = br.byte_mask;
  assign bus_req_wdata = br.wdata;
  assign bus_req_id = br.req_id;
  assign bus_req_gen = br.gen;
  assign fetch_resp_valid = fresp.valid;
  assign lsu_resp_valid = lresp.valid;
  p1_bus_arbiter u_arb (
      .clk(clk), .reset(reset),
      .fetch_req_i(fr), .fetch_req_ready_o(fetch_ready),
      .fetch_resp_o(fresp), .fetch_resp_ready_i(fetch_resp_ready),
      .lsu_req_i(lr), .lsu_req_ready_o(lsu_ready),
      .lsu_resp_o(lresp), .lsu_resp_ready_i(lsu_resp_ready),
      .bus_req_o(br), .bus_req_ready_i(bus_ready),
      .bus_resp_i(bresp), .bus_resp_ready_o(bus_resp_ready),
      .fetch_outstanding_o(fetch_outstanding),
      .lsu_outstanding_o(lsu_outstanding));
endmodule
