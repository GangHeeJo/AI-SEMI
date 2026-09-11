// One raw ready/valid event stream from four pose/timestamp-aware 4x4 AER
// leaves arranged as an 8x8 region.  This block stops before coefficient
// lookup and coordinate transformation so many regions can share those units.
//
// Contract:
// - POSE_W=1.  admitted_count belongs to occurrence_pose_version for this
//   cycle; drop_count0/1 retire FIFO-overflowed events from the named epoch.
// - SENSOR_W>=3, FIFO_DEPTH is a positive power of two, and the base origin is
//   static while rst is deasserted.  Each base coordinate must be at most
//   2^SENSOR_W-8 so the 8x8 coordinates cannot wrap.
// - region_id is intentionally added once at the shared wrapper from global
//   sensor_x/y.  Per-source and per-tile order is preserved; there is no total
//   timestamp order across the four ready streams.
// - A 240x180 bottom-edge instance starts at y=176 and has only four physical
//   rows; its unused lower two leaves must be tied to zero by the integrator.
module aer_region8x8_event_stream #(
  parameter integer POSE_W = 1,
  parameter integer SENSOR_W = 8,
  parameter integer TIMESTAMP_W = 35,
  parameter integer FIFO_DEPTH = 8
) (
  input                              clk,
  input                              rst,
  input      [63:0]                  arrival,
  input      [63:0]                  polarity_in,
  input      [POSE_W-1:0]            occurrence_pose_version,
  input      [TIMESTAMP_W-1:0]       occurrence_timestamp,
  input      [SENSOR_W-1:0]          base_sensor_origin_x,
  input      [SENSOR_W-1:0]          base_sensor_origin_y,

  output     [63:0]                  aer_overrun,
  output     [31:0]                  tile_fifo_overflow,
  output reg [6:0]                   admitted_count,
  output reg [5:0]                   drop_count0,
  output reg [5:0]                   drop_count1,

  output                             event_valid,
  input                              event_ready,
  output     [SENSOR_W-1:0]          sensor_x,
  output     [SENSOR_W-1:0]          sensor_y,
  output                             polarity,
  output     [POSE_W-1:0]            pose_version,
  output     [TIMESTAMP_W-1:0]       occurrence_timestamp_out
);
  localparam integer EVENTS_PER_TILE = 8;
  localparam integer TILE_COUNT = 4;
  localparam integer EVENT_W = (2*SENSOR_W) + 1 + POSE_W + TIMESTAMP_W;
  localparam integer SX_LSB = 0;
  localparam integer SY_LSB = SX_LSB + SENSOR_W;
  localparam integer POL_LSB = SY_LSB + SENSOR_W;
  localparam integer POSE_LSB = POL_LSB + 1;
  localparam integer TIME_LSB = POSE_LSB + POSE_W;

  wire [TILE_COUNT-1:0] leaf_valid0;
  wire [TILE_COUNT-1:0] leaf_valid1;
  wire [(TILE_COUNT*2)-1:0] leaf_row0_flat;
  wire [(TILE_COUNT*2)-1:0] leaf_row1_flat;
  wire [(TILE_COUNT*4)-1:0] leaf_cols0_flat;
  wire [(TILE_COUNT*4)-1:0] leaf_cols1_flat;
  wire [(TILE_COUNT*4)-1:0] leaf_pols0_flat;
  wire [(TILE_COUNT*4)-1:0] leaf_pols1_flat;
  wire [(TILE_COUNT*4*POSE_W)-1:0] leaf_poses0_flat;
  wire [(TILE_COUNT*4*POSE_W)-1:0] leaf_poses1_flat;
  wire [(TILE_COUNT*4*TIMESTAMP_W)-1:0] leaf_times0_flat;
  wire [(TILE_COUNT*4*TIMESTAMP_W)-1:0] leaf_times1_flat;

  wire [(TILE_COUNT*EVENTS_PER_TILE)-1:0] expanded_valid;
  wire [(TILE_COUNT*EVENTS_PER_TILE)-1:0] expanded_polarity;
  wire [(TILE_COUNT*EVENTS_PER_TILE*SENSOR_W)-1:0] expanded_x_flat;
  wire [(TILE_COUNT*EVENTS_PER_TILE*SENSOR_W)-1:0] expanded_y_flat;
  wire [(TILE_COUNT*EVENTS_PER_TILE*POSE_W)-1:0] expanded_pose_flat;
  wire [(TILE_COUNT*EVENTS_PER_TILE*TIMESTAMP_W)-1:0] expanded_time_flat;
  wire [(TILE_COUNT*EVENTS_PER_TILE*EVENT_W)-1:0] fifo_input_data_flat;

  genvar tile;
  genvar lane;
  generate
    for (tile = 0; tile < TILE_COUNT; tile = tile + 1) begin: tile_path
      localparam integer TILE_X_OFFSET = (tile & 1) * 4;
      localparam integer TILE_Y_OFFSET = ((tile >> 1) & 1) * 4;
      wire [SENSOR_W-1:0] tile_origin_x =
        base_sensor_origin_x + TILE_X_OFFSET;
      wire [SENSOR_W-1:0] tile_origin_y =
        base_sensor_origin_y + TILE_Y_OFFSET;

      aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose #(
        .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W)
      ) u_leaf (
        .clk(clk), .rst(rst),
        .arrival(arrival[tile*16 +: 16]),
        .polarity_in(polarity_in[tile*16 +: 16]),
        .pose_version(occurrence_pose_version),
        .occurrence_timestamp(occurrence_timestamp),
        .overrun(aer_overrun[tile*16 +: 16]),
        .valid0(leaf_valid0[tile]),
        .row0(leaf_row0_flat[tile*2 +: 2]),
        .col_mask0(leaf_cols0_flat[tile*4 +: 4]),
        .pol_mask0(leaf_pols0_flat[tile*4 +: 4]),
        .pose_tags0(leaf_poses0_flat[tile*4*POSE_W +: 4*POSE_W]),
        .time_tags0(leaf_times0_flat[tile*4*TIMESTAMP_W
                                    +: 4*TIMESTAMP_W]),
        .valid1(leaf_valid1[tile]),
        .row1(leaf_row1_flat[tile*2 +: 2]),
        .col_mask1(leaf_cols1_flat[tile*4 +: 4]),
        .pol_mask1(leaf_pols1_flat[tile*4 +: 4]),
        .pose_tags1(leaf_poses1_flat[tile*4*POSE_W +: 4*POSE_W]),
        .time_tags1(leaf_times1_flat[tile*4*TIMESTAMP_W
                                    +: 4*TIMESTAMP_W])
      );

      aer_bitmap_to_event8_pose #(
        .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W), .SENSOR_W(SENSOR_W)
      ) u_expand (
        .valid0(leaf_valid0[tile]),
        .row0(leaf_row0_flat[tile*2 +: 2]),
        .col_mask0(leaf_cols0_flat[tile*4 +: 4]),
        .pol_mask0(leaf_pols0_flat[tile*4 +: 4]),
        .pose_tags0(leaf_poses0_flat[tile*4*POSE_W +: 4*POSE_W]),
        .time_tags0(leaf_times0_flat[tile*4*TIMESTAMP_W
                                    +: 4*TIMESTAMP_W]),
        .valid1(leaf_valid1[tile]),
        .row1(leaf_row1_flat[tile*2 +: 2]),
        .col_mask1(leaf_cols1_flat[tile*4 +: 4]),
        .pol_mask1(leaf_pols1_flat[tile*4 +: 4]),
        .pose_tags1(leaf_poses1_flat[tile*4*POSE_W +: 4*POSE_W]),
        .time_tags1(leaf_times1_flat[tile*4*TIMESTAMP_W
                                    +: 4*TIMESTAMP_W]),
        .tile_origin_x(tile_origin_x), .tile_origin_y(tile_origin_y),
        .event_valid(expanded_valid[tile*EVENTS_PER_TILE
                                    +: EVENTS_PER_TILE]),
        .sensor_x_flat(expanded_x_flat[tile*EVENTS_PER_TILE*SENSOR_W
                                      +: EVENTS_PER_TILE*SENSOR_W]),
        .sensor_y_flat(expanded_y_flat[tile*EVENTS_PER_TILE*SENSOR_W
                                      +: EVENTS_PER_TILE*SENSOR_W]),
        .polarity(expanded_polarity[tile*EVENTS_PER_TILE
                                    +: EVENTS_PER_TILE]),
        .pose_version_flat(expanded_pose_flat[tile*EVENTS_PER_TILE*POSE_W
                                             +: EVENTS_PER_TILE*POSE_W]),
        .occurrence_timestamp_flat(
          expanded_time_flat[tile*EVENTS_PER_TILE*TIMESTAMP_W
                             +: EVENTS_PER_TILE*TIMESTAMP_W])
      );

      for (lane = 0; lane < EVENTS_PER_TILE; lane = lane + 1) begin: pack_event
        localparam integer EVENT_INDEX = tile*EVENTS_PER_TILE + lane;
        assign fifo_input_data_flat[EVENT_INDEX*EVENT_W +: EVENT_W] = {
          expanded_time_flat[EVENT_INDEX*TIMESTAMP_W +: TIMESTAMP_W],
          expanded_pose_flat[EVENT_INDEX*POSE_W +: POSE_W],
          expanded_polarity[EVENT_INDEX],
          expanded_y_flat[EVENT_INDEX*SENSOR_W +: SENSOR_W],
          expanded_x_flat[EVENT_INDEX*SENSOR_W +: SENSOR_W]
        };
      end
    end
  endgenerate

  wire [TILE_COUNT-1:0] fifo_valid;
  wire [(TILE_COUNT*EVENT_W)-1:0] fifo_data_flat;
  wire [TILE_COUNT-1:0] fifo_ready;
  wire [(TILE_COUNT*$clog2(FIFO_DEPTH+1))-1:0] fifo_occupancy_flat;

  generate
    for (tile = 0; tile < TILE_COUNT; tile = tile + 1) begin: tile_fifo
      event_batch_fifo #(
        .DATA_W(EVENT_W), .IN_LANES(EVENTS_PER_TILE), .DEPTH(FIFO_DEPTH)
      ) u_fifo (
        .clk(clk), .rst(rst),
        .in_valid(expanded_valid[tile*EVENTS_PER_TILE +: EVENTS_PER_TILE]),
        .in_data_flat(fifo_input_data_flat[tile*EVENTS_PER_TILE*EVENT_W
                                          +: EVENTS_PER_TILE*EVENT_W]),
        .in_overflow(tile_fifo_overflow[tile*EVENTS_PER_TILE
                                       +: EVENTS_PER_TILE]),
        .out_valid(fifo_valid[tile]),
        .out_data(fifo_data_flat[tile*EVENT_W +: EVENT_W]),
        .out_ready(fifo_ready[tile]),
        .occupancy(fifo_occupancy_flat[tile*$clog2(FIFO_DEPTH+1)
                                      +: $clog2(FIFO_DEPTH+1)])
      );
    end
  endgenerate

  wire [EVENT_W-1:0] rr_data;
  wire [1:0] rr_source;
  rr_stream_arbiter4 #(.DATA_W(EVENT_W)) u_rr (
    .clk(clk), .rst(rst),
    .in_valid(fifo_valid), .in_data_flat(fifo_data_flat),
    .in_ready(fifo_ready),
    .out_valid(event_valid), .out_data(rr_data), .out_source(rr_source),
    .out_ready(event_ready)
  );

  assign sensor_x = rr_data[SX_LSB +: SENSOR_W];
  assign sensor_y = rr_data[SY_LSB +: SENSOR_W];
  assign polarity = rr_data[POL_LSB];
  assign pose_version = rr_data[POSE_LSB +: POSE_W];
  assign occurrence_timestamp_out = rr_data[TIME_LSB +: TIMESTAMP_W];

  wire [63:0] admitted_mask = {64{!rst}} & arrival & ~aer_overrun;
  integer count_i;
  always @(*) begin
    admitted_count = 7'd0;
    for (count_i = 0; count_i < 64; count_i = count_i + 1)
      admitted_count = admitted_count + admitted_mask[count_i];
  end

  integer drop_i;
  always @(*) begin
    drop_count0 = 6'd0;
    drop_count1 = 6'd0;
    for (drop_i = 0; drop_i < 32; drop_i = drop_i + 1) begin
      if (tile_fifo_overflow[drop_i]) begin
        if (expanded_pose_flat[drop_i*POSE_W +: POSE_W] ==
            {POSE_W{1'b0}})
          drop_count0 = drop_count0 + 1'b1;
        else
          drop_count1 = drop_count1 + 1'b1;
      end
    end
  end
endmodule
