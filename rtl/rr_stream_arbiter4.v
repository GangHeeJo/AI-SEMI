// Four-input ready/valid round-robin stream arbiter.
// The priority pointer advances only on an output handshake.  Once an output
// is presented while stalled, its source and data are locked until accepted.
module rr_stream_arbiter4 #(
  parameter DATA_W = 32
) (
  input                       clk,
  input                       rst,
  input      [3:0]            in_valid,
  input      [4*DATA_W-1:0]   in_data_flat,
  output reg [3:0]            in_ready,
  output reg                  out_valid,
  output reg [DATA_W-1:0]     out_data,
  output reg [1:0]            out_source,
  input                       out_ready
);
  reg [1:0] rr_ptr;
  reg lock_valid;
  reg [1:0] lock_source;
  reg [DATA_W-1:0] lock_data;

  reg pick_valid;
  reg [1:0] pick_source;
  reg [DATA_W-1:0] pick_data;
  integer offset_i;
  integer source_i;

  initial begin
    if (DATA_W < 1)
      $fatal(1, "rr_stream_arbiter4 requires DATA_W >= 1");
  end

  always @(*) begin
    pick_valid = 1'b0;
    pick_source = rr_ptr;
    pick_data = {DATA_W{1'b0}};
    for (offset_i = 0; offset_i < 4; offset_i = offset_i + 1) begin
      source_i = (rr_ptr + offset_i) & 3;
      if (!pick_valid && in_valid[source_i]) begin
        pick_valid = 1'b1;
        pick_source = source_i[1:0];
        pick_data = in_data_flat[source_i*DATA_W +: DATA_W];
      end
    end
  end

  always @(*) begin
    in_ready = 4'b0000;
    out_valid = 1'b0;
    out_data = {DATA_W{1'b0}};
    out_source = 2'b00;
    if (!rst) begin
      if (lock_valid) begin
        out_valid = 1'b1;
        out_data = lock_data;
        out_source = lock_source;
        in_ready[lock_source] = out_ready;
      end else if (pick_valid) begin
        out_valid = 1'b1;
        out_data = pick_data;
        out_source = pick_source;
        in_ready[pick_source] = out_ready;
      end
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      rr_ptr <= 2'd0;
      lock_valid <= 1'b0;
      lock_source <= 2'd0;
      lock_data <= {DATA_W{1'b0}};
    end else if (lock_valid) begin
      if (out_ready) begin
        rr_ptr <= lock_source + 2'd1;
        lock_valid <= 1'b0;
      end
    end else if (pick_valid) begin
      if (out_ready) begin
        rr_ptr <= pick_source + 2'd1;
      end else begin
        lock_valid <= 1'b1;
        lock_source <= pick_source;
        lock_data <= pick_data;
      end
    end
  end
endmodule
