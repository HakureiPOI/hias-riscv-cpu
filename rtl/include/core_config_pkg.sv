// P0-02 shared core configuration. Candidate baseline for review; no CPU
// datapath exists yet. Values follow docs/项目设计书.md and
// docs/architecture/memory-map.md.
//
// The interface is designed for the final two-slot machine. P1 may limit the
// active width to one slot at runtime/elaboration, but the shared types must
// not be hard-wired to a single slot.
package core_config_pkg;

  // Several constants are documented baseline values consumed by future
  // modules. They are intentionally exported before those modules exist.
  /* verilator lint_off UNUSEDPARAM */

  // Base widths.
  localparam int unsigned XLEN = 32;
  localparam int unsigned VA_BITS = 32;
  localparam int unsigned PA_BITS = 34;

  // Two-slot pipeline. NUM_SLOTS is structural; ACTIVE_SLOTS_P1 is the
  // reduced P1 acceptance width.
  localparam int unsigned NUM_SLOTS = 2;
  localparam int unsigned SLOT_ID_W = 1;
  localparam int unsigned ACTIVE_SLOTS_P1 = 1;
  localparam int unsigned ACTIVE_SLOTS_FINAL = 2;

  // Reorder buffer: item index plus generation. A generation counter prevents
  // an old response from matching a reused index after flush/rollback.
  localparam int unsigned ROB_ENTRIES = 32;
  localparam int unsigned ROB_IDX_W = $clog2(ROB_ENTRIES);
  localparam int unsigned ROB_GEN_W = 8;

  // Integer issue queue and ordered memory FIFO.
  localparam int unsigned IQ_ENTRIES = 16;
  localparam int unsigned IQ_IDX_W = $clog2(IQ_ENTRIES);
  localparam int unsigned MEM_FIFO_ENTRIES = 8;
  localparam int unsigned MEM_FIFO_IDX_W = $clog2(MEM_FIFO_ENTRIES);

  // Front-end buffers and request identity.
  localparam int unsigned FETCH_BUF_ENTRIES = 8;
  localparam int unsigned FETCH_BUF_IDX_W = $clog2(FETCH_BUF_ENTRIES);
  localparam int unsigned FETCH_GEN_W = 8;
  localparam int unsigned REQ_ID_W = 6;

  // Register file / CSR / memory encodings.
  localparam int unsigned REG_ADDR_W = 5;
  localparam int unsigned REG_COUNT = 32;
  localparam int unsigned CSR_ADDR_W = 12;
  localparam int unsigned BYTE_MASK_W = XLEN / 8;
  localparam int unsigned MEM_SIZE_W = 2;
  localparam int unsigned CAUSE_W = 5;

  // Sv32 geometry.
  localparam int unsigned PAGE_OFFSET_W = 12;
  localparam int unsigned VPN_W = VA_BITS - PAGE_OFFSET_W;
  localparam int unsigned PPN_W = PA_BITS - PAGE_OFFSET_W;
  localparam int unsigned PTE_W = 32;
  localparam int unsigned ASID_W = 0;

  // Independent FPU transaction interface.
  localparam int unsigned FPU_TXN_ID_W = 6;
  localparam int unsigned FPU_FLAGS_W = 5;

  // Platform RAM: P1/final DUT RAM is 128 KiB at 0x8000_0000. This must stay
  // consistent with config/platform.json; the RTL package only carries the
  // values needed for address checks.
  localparam logic [PA_BITS-1:0] RAM_BASE = PA_BITS'(32'h8000_0000);
  localparam logic [PA_BITS-1:0] RAM_SIZE = PA_BITS'(32'h0002_0000);
  localparam logic [PA_BITS-1:0] RAM_END = RAM_BASE + RAM_SIZE;

  // P1 reset vector equals the RAM base.
  localparam logic [VA_BITS-1:0] RESET_VECTOR = VA_BITS'(32'h8000_0000);

  // Reset is synchronous active-high on posedge clk. Flush has priority over
  // ordinary enqueue/complete events (see docs/interfaces.md).
  localparam logic RESET_ACTIVE_LEVEL = 1'b1;

  /* verilator lint_on UNUSEDPARAM */

endpackage
