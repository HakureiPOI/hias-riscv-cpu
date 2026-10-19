// P0-02-R2 minimal commit-event contract fixture (not a CPU/ROB).
// S0 normal + S1 exception: retire S0 now, emit the Trap on the next cycle.
// Normal retirement and Trap are mutually exclusive on every cycle, and the
// exception metadata is held while deferred.
module retire_event_fixture #(
    parameter int CAUSE_W = 5
) (
    input  logic             clk,
    input  logic             reset,
    input  logic [1:0]       slot_valid,
    input  logic             s1_exc_valid,
    input  logic [CAUSE_W-1:0] s1_exc_cause,
    input  logic [31:0]      s1_exc_tval,
    input  logic [31:0]      s1_pc,
    output logic [1:0]       retire_valid,
    output logic             trap_valid,
    output logic [CAUSE_W-1:0] trap_cause,
    output logic [31:0]      trap_tval,
    output logic [31:0]      trap_pc
);

  logic             pending_trap;
  logic [CAUSE_W-1:0] pending_cause;
  logic [31:0]      pending_tval;
  logic [31:0]      pending_pc;

  always_ff @(posedge clk) begin
    if (reset) begin
      retire_valid <= 2'b00;
      trap_valid <= 1'b0;
      trap_cause <= '0;
      trap_tval <= '0;
      trap_pc <= '0;
      pending_trap <= 1'b0;
      pending_cause <= '0;
      pending_tval <= '0;
      pending_pc <= '0;
    end else begin
      retire_valid <= 2'b00;
      trap_valid <= 1'b0;
      if (pending_trap) begin
        // Trap-only cycle; no normal retirement.
        trap_valid <= 1'b1;
        trap_cause <= pending_cause;
        trap_tval <= pending_tval;
        trap_pc <= pending_pc;
        pending_trap <= 1'b0;
      end else if (s1_exc_valid) begin
        // Only the older normal slot may retire this cycle.
        if (slot_valid[0]) retire_valid <= 2'b01;
        pending_trap <= 1'b1;
        pending_cause <= s1_exc_cause;
        pending_tval <= s1_exc_tval;
        pending_pc <= s1_pc;
      end else begin
        // Contiguous prefix: slot 1 cannot retire without slot 0.
        retire_valid <= slot_valid[0] ? {slot_valid[1], 1'b1} : 2'b00;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!reset) begin
      assert (!(trap_valid && (retire_valid != 2'b00))) else
        $error("P0-02_EVENT_FIXTURE: Trap and normal retire in the same cycle");
    end
  end

endmodule
