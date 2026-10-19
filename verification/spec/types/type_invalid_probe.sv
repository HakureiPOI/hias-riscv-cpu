// P0-02 negative fixture: parameter validation must reject an illegal shared
// configuration. Run with -GINJECT_INVALID=1; the expected message is
// P0-02_INVALID_PARAM_DETECTED and the process must exit non-zero.
module type_invalid_probe #(
    parameter int INJECT_INVALID = 0
  /* verilator lint_off WIDTHTRUNC */
);
  import core_config_pkg::*;

  localparam int TEST_ROB_ENTRIES = INJECT_INVALID ? 33 : ROB_ENTRIES;
  localparam int TEST_IQ_ENTRIES  = INJECT_INVALID ? 0 : IQ_ENTRIES;
  localparam int TEST_RAM_SIZE    = INJECT_INVALID ? 32'h0001_8000 : int'(RAM_SIZE);
  /* verilator lint_on WIDTHTRUNC */

  initial begin
    if ((TEST_ROB_ENTRIES < 2) || ((TEST_ROB_ENTRIES & (TEST_ROB_ENTRIES - 1)) != 0))
      $fatal(1, "P0-02_INVALID_PARAM_DETECTED: ROB_ENTRIES=%0d", TEST_ROB_ENTRIES);
    if ((TEST_IQ_ENTRIES < 2) || ((TEST_IQ_ENTRIES & (TEST_IQ_ENTRIES - 1)) != 0))
      $fatal(1, "P0-02_INVALID_PARAM_DETECTED: IQ_ENTRIES=%0d", TEST_IQ_ENTRIES);
    if ((TEST_RAM_SIZE < 4096) || ((TEST_RAM_SIZE % 4096) != 0))
      $fatal(1, "P0-02_INVALID_PARAM_DETECTED: RAM_SIZE=0x%0h", TEST_RAM_SIZE);
    $display("P0-02_INVALID_PARAM_CHECK_PASS");
    $finish;
  end
endmodule
