// P1-A core interface skeleton.
//
// This is deliberately not an executing CPU. It imports the frozen shared
// types, leaves the two-slot structural types available, exposes the memory
// interface for P1-B, and keeps retirement/Trap outputs at zero. It never
// initiates a memory request.
module p1_core_skeleton (
    input  logic                        clk,
    input  logic                        reset,
    input  core_types_pkg::mem_resp_t   mem_resp_i,
    output logic                        mem_resp_ready_o,
    output core_types_pkg::mem_req_t    mem_req_o,
    input  logic                        mem_req_ready_i,
    input  core_types_pkg::redirect_t   redirect_i,
    output core_types_pkg::commit_bundle_t commit_o,
    output logic                        idle_o
);

  import core_config_pkg::*;
  import core_types_pkg::*;

  // P1 is single-active-slot, but the frozen interfaces remain two-slot.
  localparam int unsigned ACTIVE_SLOTS = ACTIVE_SLOTS_P1;

  always_comb begin
    mem_req_o = '0;
    mem_req_o.valid = 1'b0;
    mem_resp_ready_o = 1'b1;
    commit_o = '0;
    commit_o.slot_valid = '0;
    commit_o.trap_valid = 1'b0;
    idle_o = 1'b1;
  end

  // The skeleton has no internal state yet. P1-B will replace this file's
  // datapath insertion point while keeping the same ports.
  logic unused;
  assign unused = (^mem_resp_i) ^ (^redirect_i) ^ mem_req_ready_i ^
                  (ACTIVE_SLOTS != 1);

  // Guard against accidental fabrication of retirement/trap records.
  always_ff @(posedge clk) begin
    if (!reset) begin
      assert (!mem_req_o.valid) else
        $error("P1-A_CORE: skeleton initiated a memory request");
      assert (!commit_o.trap_valid && commit_o.slot_valid == 2'b00) else
        $error("P1-A_CORE: skeleton fabricated a retire/trap event");
    end
  end

endmodule
