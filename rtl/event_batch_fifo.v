// Converts a multi-lane event batch into a one-event ready/valid stream.
// Valid lanes are enqueued in ascending lane order.  If the batch does not fit,
// the lowest lanes are accepted first and each rejected lane is marked in the
// combinational in_overflow result for that cycle.
module event_batch_fifo #(
  parameter DATA_W = 32,
  parameter IN_LANES = 8,
  parameter DEPTH = 32
) (
  input                              clk,
  input                              rst,
  input      [IN_LANES-1:0]          in_valid,
  input      [IN_LANES*DATA_W-1:0]   in_data_flat,
  output reg [IN_LANES-1:0]          in_overflow,
  output                             out_valid,
  output     [DATA_W-1:0]            out_data,
  input                              out_ready,
  output reg [$clog2(DEPTH+1)-1:0]   occupancy
);
  localparam PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

  reg [DATA_W-1:0] mem [0:DEPTH-1];
  reg [PTR_W-1:0] read_ptr;
  reg [PTR_W-1:0] write_ptr;
  reg [IN_LANES-1:0] accept_mask;
  integer accepted_count;
  integer free_slots;
  integer scan_i;
  integer write_i;
  integer write_offset;

  wire pop = out_valid && out_ready;
  assign out_valid = !rst && (occupancy != 0);
  assign out_data = mem[read_ptr];

  // Contract: DATA_W/IN_LANES are positive and DEPTH is a positive power of 2.
  // Testbenches validate the supported configurations; keeping the RTL free of
  // elaboration-time system tasks makes the block portable to the Genus flow.
  always @(*) begin
    accept_mask = {IN_LANES{1'b0}};
    in_overflow = {IN_LANES{1'b0}};
    accepted_count = 0;
    free_slots = DEPTH - occupancy + (pop ? 1 : 0);

    if (rst) begin
      in_overflow = in_valid;
    end else begin
      for (scan_i = 0; scan_i < IN_LANES; scan_i = scan_i + 1) begin
        if (in_valid[scan_i]) begin
          if (accepted_count < free_slots) begin
            accept_mask[scan_i] = 1'b1;
            accepted_count = accepted_count + 1;
          end else begin
            in_overflow[scan_i] = 1'b1;
          end
        end
      end
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      read_ptr <= {PTR_W{1'b0}};
      write_ptr <= {PTR_W{1'b0}};
      occupancy <= 0;
    end else begin
      write_offset = 0;
      for (write_i = 0; write_i < IN_LANES; write_i = write_i + 1) begin
        if (accept_mask[write_i]) begin
          mem[(write_ptr + write_offset) & (DEPTH - 1)]
            <= in_data_flat[write_i*DATA_W +: DATA_W];
          write_offset = write_offset + 1;
        end
      end

      if (pop)
        read_ptr <= (read_ptr + 1'b1) & (DEPTH - 1);
      if (accepted_count != 0)
        write_ptr <= (write_ptr + accepted_count) & (DEPTH - 1);
      occupancy <= occupancy + accepted_count - (pop ? 1 : 0);
    end
  end
endmodule
