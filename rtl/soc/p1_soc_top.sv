// P1-A SoC wrapper: core skeleton + single-transaction RAM bridge.
module p1_soc_top (
    input  logic        clk,
    input  logic        reset,
    input  logic        flush_i,
    input  logic [1:0]  resp_delay_i,
    output core_types_pkg::commit_bundle_t commit_o,
    output logic        core_idle_o,
    output logic        mem_req_valid_o,
    output logic        mem_resp_ready_o
);

  import core_config_pkg::*;
  import core_types_pkg::*;

  mem_req_t  core_req;
  logic      core_req_ready;
  mem_resp_t bridge_resp;
  logic      bridge_resp_ready;
  redirect_t redirect;

  assign redirect = '0;

  p1_core_skeleton u_core (
      .clk(clk), .reset(reset),
      .mem_resp_i(bridge_resp), .mem_resp_ready_o(bridge_resp_ready),
      .mem_req_o(core_req), .mem_req_ready_i(core_req_ready),
      .redirect_i(redirect), .commit_o(commit_o), .idle_o(core_idle_o));

  ram_bridge u_bridge (
      .clk(clk), .reset(reset),
      .load_valid(1'b0), .load_word_addr(15'd0), .load_data(32'd0),
      .flush_i(flush_i),
      .req_i(core_req), .req_ready_o(core_req_ready),
      .resp_o(bridge_resp), .resp_ready_i(bridge_resp_ready),
      .resp_delay_i(resp_delay_i));

  assign mem_req_valid_o = core_req.valid;
  assign mem_resp_ready_o = bridge_resp_ready;

endmodule
