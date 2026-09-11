// Sixteen-input ready/valid merge built from the existing four-way arbiter.
// Arbitration is hierarchical and fair; it does not sort events by timestamp.
module rr_stream_merge16 #(
  parameter DATA_W = 32
) (
  input                       clk,
  input                       rst,
  input      [15:0]           in_valid,
  input      [16*DATA_W-1:0]  in_data_flat,
  output     [15:0]           in_ready,
  output                      out_valid,
  output     [DATA_W-1:0]     out_data,
  output     [3:0]            out_source,
  input                       out_ready
);
  wire [3:0] leaf_valid;
  wire [3:0] leaf_ready;
  wire [4*DATA_W-1:0] leaf_data_flat;
  wire [7:0] leaf_source_flat;
  wire [4*(DATA_W+2)-1:0] root_data_flat;
  wire [DATA_W+1:0] root_data;
  wire [1:0] root_source;

  genvar leaf_i;
  generate
    for (leaf_i = 0; leaf_i < 4; leaf_i = leaf_i + 1) begin : gen_leaf
      rr_stream_arbiter4 #(.DATA_W(DATA_W)) leaf (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid[leaf_i*4 +: 4]),
        .in_data_flat(in_data_flat[leaf_i*4*DATA_W +: 4*DATA_W]),
        .in_ready(in_ready[leaf_i*4 +: 4]),
        .out_valid(leaf_valid[leaf_i]),
        .out_data(leaf_data_flat[leaf_i*DATA_W +: DATA_W]),
        .out_source(leaf_source_flat[leaf_i*2 +: 2]),
        .out_ready(leaf_ready[leaf_i])
      );

      assign root_data_flat[leaf_i*(DATA_W+2) +: (DATA_W+2)] = {
        leaf_source_flat[leaf_i*2 +: 2],
        leaf_data_flat[leaf_i*DATA_W +: DATA_W]
      };
    end
  endgenerate

  rr_stream_arbiter4 #(.DATA_W(DATA_W+2)) root (
    .clk(clk),
    .rst(rst),
    .in_valid(leaf_valid),
    .in_data_flat(root_data_flat),
    .in_ready(leaf_ready),
    .out_valid(out_valid),
    .out_data(root_data),
    .out_source(root_source),
    .out_ready(out_ready)
  );

  assign out_data = root_data[DATA_W-1:0];
  assign out_source = {root_source, root_data[DATA_W+1:DATA_W]};
endmodule
