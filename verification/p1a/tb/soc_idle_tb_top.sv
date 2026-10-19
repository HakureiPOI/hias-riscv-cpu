// P1-A SoC idle wrapper: exposes the skeleton retirement/memory state.
module soc_idle_tb_top (
    input  logic clk,
    input  logic reset,
    output logic commit_slot_valid,
    output logic commit_trap_valid,
    output logic core_idle_o,
    output logic mem_req_valid_o,
    output logic mem_resp_ready_o,
    output logic ram_write_o
);
  import core_types_pkg::*;

  commit_bundle_t commit;
  logic core_idle;
  logic mem_req_valid;
  logic mem_resp_ready;

  p1_soc_top dut (
      .clk(clk), .reset(reset), .flush_i(1'b0), .resp_delay_i(2'd0),
      .commit_o(commit), .core_idle_o(core_idle),
      .mem_req_valid_o(mem_req_valid), .mem_resp_ready_o(mem_resp_ready),
      .ram_write_o(ram_write_o));

  logic unused_commit;
  assign unused_commit = ^commit;
  assign commit_slot_valid = |commit.slot_valid;
  assign commit_trap_valid = commit.trap_valid;
  assign core_idle_o = core_idle;
  assign mem_req_valid_o = mem_req_valid;
  assign mem_resp_ready_o = mem_resp_ready;

endmodule
