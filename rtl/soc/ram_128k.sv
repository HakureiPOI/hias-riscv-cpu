// P1-A simulation RAM: little-endian 128 KiB at 0x8000_0000.
//
// The array is intentionally not cleared by reset: reset only clears the
// handshake/response registers. Testbenches or software image loading must
// provide known contents. This avoids a full-RAM reset that would hinder later
// FPGA inference and keeps reset and data initialization separate.
module ram_128k (
    input  logic        clk,
    input  logic        reset,
    input  logic        load_valid,
    input  logic [14:0] load_word_addr,
    input  logic [31:0] load_data,
    input  logic        req,
    output logic        ready,
    input  logic        we,
    input  logic [14:0] word_addr,
    input  logic [3:0]  byte_mask,
    input  logic [31:0] wdata,      // lane-aligned by the bridge
    input  logic [1:0]  resp_delay, // test/debug latency in cycles
    output logic        resp_valid,
    input  logic        resp_ready,
    output logic [31:0] rdata
);

  localparam int unsigned BYTES = 128 * 1024;

  logic [7:0] mem[0:BYTES-1];
  logic [31:0] rdata_q;
  logic [1:0]  delay_q;
  logic        pending_q;
  logic [16:0] word_base;

  assign word_base = {word_addr, 2'b00};
  assign ready = !pending_q && (!resp_valid || resp_ready);

  always_ff @(posedge clk) begin
    if (load_valid) begin
      mem[{load_word_addr, 2'b00} + 16'd0] <= load_data[7:0];
      mem[{load_word_addr, 2'b00} + 16'd1] <= load_data[15:8];
      mem[{load_word_addr, 2'b00} + 16'd2] <= load_data[23:16];
      mem[{load_word_addr, 2'b00} + 16'd3] <= load_data[31:24];
    end else if (reset) begin
      pending_q <= 1'b0;
      resp_valid <= 1'b0;
      delay_q <= '0;
      rdata_q <= '0;
    end else begin
      if (resp_valid && resp_ready) resp_valid <= 1'b0;

      if (pending_q) begin
        if (delay_q == '0) begin
          resp_valid <= 1'b1;
          pending_q <= 1'b0;
        end else begin
          delay_q <= delay_q - 1'b1;
        end
      end else if (req && ready) begin
        if (we) begin
          for (int i = 0; i < 4; i++) begin
            if (byte_mask[i]) mem[word_base + i[16:0]] <= wdata[8*i +: 8];
          end
          rdata_q <= '0;
        end else begin
          rdata_q <= {mem[word_base + 16'd3], mem[word_base + 16'd2],
                      mem[word_base + 16'd1], mem[word_base]};
        end
        delay_q <= resp_delay;
        if (resp_delay == '0) begin
          resp_valid <= 1'b1;
        end else begin
          pending_q <= 1'b1;
        end
      end
    end
  end

  assign rdata = rdata_q;

endmodule
