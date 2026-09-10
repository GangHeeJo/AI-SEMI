// Four pose/timestamp-tagged 4x4 AER leaves arranged as one 8x8 sensor.
//
// Each leaf expands its two row bitmaps into an eight-event batch.  A local
// FIFO absorbs that batch, then a fair arbiter serializes the four FIFO heads
// into one ready/valid affine-transform lane.  Events rejected by a full tile
// FIFO are terminal drops and therefore retire from the pose in-flight guard.
module aer_tx64_pose_affine2d_serial #(
  parameter integer POSE_W = 4,
  parameter integer SENSOR_W = 10,
  parameter integer RESULT_W = 16,
  parameter integer MATRIX_W = 16,
  parameter integer OFFSET_W = 24,
  parameter integer FRAC_W = 14,
  parameter integer TIMESTAMP_W = 32,
  parameter integer FIFO_DEPTH = 32,
  parameter integer GUARD_COUNT_W = 10,
  parameter integer X_MIN = 0,
  parameter integer X_MAX = 255,
  parameter integer Y_MIN = 0,
  parameter integer Y_MAX = 255
) (
  input                              clk,
  input                              rst,
  input      [63:0]                  arrival,
  input      [63:0]                  polarity_in,
  input      [POSE_W-1:0]            occurrence_pose_version,
  input      [TIMESTAMP_W-1:0]       occurrence_timestamp,
  output     [63:0]                  aer_overrun,
  output     [31:0]                  tile_fifo_overflow,

  input                              pose_wr_req,
  input      [POSE_W-1:0]            pose_wr_id,
  input signed [MATRIX_W-1:0]        pose_wr_m00,
  input signed [MATRIX_W-1:0]        pose_wr_m01,
  input signed [MATRIX_W-1:0]        pose_wr_m10,
  input signed [MATRIX_W-1:0]        pose_wr_m11,
  input signed [OFFSET_W-1:0]        pose_wr_tx,
  input signed [OFFSET_W-1:0]        pose_wr_ty,
  output                             pose_wr_ready,
  output                             pose_wr_commit,
  output                             pose_wr_rejected,
  output                             pose_accounting_error,

  input      [SENSOR_W-1:0]          base_sensor_origin_x,
  input      [SENSOR_W-1:0]          base_sensor_origin_y,

  output                             world_valid,
  input                              world_ready,
  output                             mapped_valid,
  output                             pose_found,
  output                             in_range,
  output reg [SENSOR_W-1:0]          sensor_x,
  output reg [SENSOR_W-1:0]          sensor_y,
  output reg [1:0]                   tile_id,
  output                             polarity,
  output     [POSE_W-1:0]            pose_version,
  output     [TIMESTAMP_W-1:0]       occurrence_timestamp_out,
  output signed [RESULT_W-1:0]       world_x,
  output signed [RESULT_W-1:0]       world_y
);
  localparam integer EVENTS_PER_TILE = 8;
  localparam integer TILE_COUNT = 4;
  localparam integer EVENT_W = (2*SENSOR_W) + 1 + POSE_W + TIMESTAMP_W;
  localparam integer SX_LSB = 0;
  localparam integer SY_LSB = SX_LSB + SENSOR_W;
  localparam integer POL_LSB = SY_LSB + SENSOR_W;
  localparam integer POSE_LSB = POL_LSB + 1;
  localparam integer TIME_LSB = POSE_LSB + POSE_W;

  initial begin
    if (SENSOR_W < 3)
      $fatal(1, "aer_tx64_pose_affine2d_serial requires SENSOR_W >= 3");
  end

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
        .time_tags0(leaf_times0_flat[tile*4*TIMESTAMP_W +: 4*TIMESTAMP_W]),
        .valid1(leaf_valid1[tile]),
        .row1(leaf_row1_flat[tile*2 +: 2]),
        .col_mask1(leaf_cols1_flat[tile*4 +: 4]),
        .pol_mask1(leaf_pols1_flat[tile*4 +: 4]),
        .pose_tags1(leaf_poses1_flat[tile*4*POSE_W +: 4*POSE_W]),
        .time_tags1(leaf_times1_flat[tile*4*TIMESTAMP_W +: 4*TIMESTAMP_W])
      );

      aer_bitmap_to_event8_pose #(
        .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W), .SENSOR_W(SENSOR_W)
      ) u_expand (
        .valid0(leaf_valid0[tile]),
        .row0(leaf_row0_flat[tile*2 +: 2]),
        .col_mask0(leaf_cols0_flat[tile*4 +: 4]),
        .pol_mask0(leaf_pols0_flat[tile*4 +: 4]),
        .pose_tags0(leaf_poses0_flat[tile*4*POSE_W +: 4*POSE_W]),
        .time_tags0(leaf_times0_flat[tile*4*TIMESTAMP_W +: 4*TIMESTAMP_W]),
        .valid1(leaf_valid1[tile]),
        .row1(leaf_row1_flat[tile*2 +: 2]),
        .col_mask1(leaf_cols1_flat[tile*4 +: 4]),
        .pol_mask1(leaf_pols1_flat[tile*4 +: 4]),
        .pose_tags1(leaf_poses1_flat[tile*4*POSE_W +: 4*POSE_W]),
        .time_tags1(leaf_times1_flat[tile*4*TIMESTAMP_W +: 4*TIMESTAMP_W]),
        .tile_origin_x(tile_origin_x), .tile_origin_y(tile_origin_y),
        .event_valid(expanded_valid[tile*EVENTS_PER_TILE +: EVENTS_PER_TILE]),
        .sensor_x_flat(expanded_x_flat[tile*EVENTS_PER_TILE*SENSOR_W
                                      +: EVENTS_PER_TILE*SENSOR_W]),
        .sensor_y_flat(expanded_y_flat[tile*EVENTS_PER_TILE*SENSOR_W
                                      +: EVENTS_PER_TILE*SENSOR_W]),
        .polarity(expanded_polarity[tile*EVENTS_PER_TILE +: EVENTS_PER_TILE]),
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

  wire rr_valid;
  wire [EVENT_W-1:0] rr_data;
  wire [1:0] rr_source;
  wire transform_upstream_ready;

  rr_stream_arbiter4 #(.DATA_W(EVENT_W)) u_rr (
    .clk(clk), .rst(rst),
    .in_valid(fifo_valid), .in_data_flat(fifo_data_flat),
    .in_ready(fifo_ready),
    .out_valid(rr_valid), .out_data(rr_data), .out_source(rr_source),
    .out_ready(transform_upstream_ready)
  );

  wire [SENSOR_W-1:0] rr_sensor_x = rr_data[SX_LSB +: SENSOR_W];
  wire [SENSOR_W-1:0] rr_sensor_y = rr_data[SY_LSB +: SENSOR_W];
  wire rr_polarity = rr_data[POL_LSB];
  wire [POSE_W-1:0] rr_pose = rr_data[POSE_LSB +: POSE_W];
  wire [TIMESTAMP_W-1:0] rr_time = rr_data[TIME_LSB +: TIMESTAMP_W];
  wire rr_handshake = rr_valid & transform_upstream_ready;

  // Count every event admitted to a leaf.  AER overruns were never admitted.
  wire [63:0] aer_accepted_mask = arrival & ~aer_overrun;
  wire [32:0] retire_valid;
  wire [(33*POSE_W)-1:0] retire_pose_flat;
  assign retire_valid[31:0] = tile_fifo_overflow;
  assign retire_valid[32] = rr_handshake;
  generate
    for (lane = 0; lane < 32; lane = lane + 1) begin: drop_retire_pose
      assign retire_pose_flat[lane*POSE_W +: POSE_W] =
        expanded_pose_flat[lane*POSE_W +: POSE_W];
    end
  endgenerate
  assign retire_pose_flat[32*POSE_W +: POSE_W] = rr_pose;

  pose_inflight_guard8 #(
    .POSE_W(POSE_W), .COUNT_W(GUARD_COUNT_W),
    .ACCEPT_SOURCES(64), .RETIRE_LANES(33)
  ) u_pose_guard (
    .clk(clk), .rst(rst),
    .accepted_mask(aer_accepted_mask),
    .accepted_pose_version(occurrence_pose_version),
    .retire_valid(retire_valid),
    .retire_pose_version_flat(retire_pose_flat),
    .pose_wr_req(pose_wr_req), .pose_wr_id(pose_wr_id),
    .pose_wr_ready(pose_wr_ready),
    .pose_wr_commit(pose_wr_commit),
    .pose_wr_rejected(pose_wr_rejected),
    .accounting_error(pose_accounting_error)
  );

  wire [0:0] lookup_found;
  wire [MATRIX_W-1:0] lookup_m00;
  wire [MATRIX_W-1:0] lookup_m01;
  wire [MATRIX_W-1:0] lookup_m10;
  wire [MATRIX_W-1:0] lookup_m11;
  wire [OFFSET_W-1:0] lookup_tx;
  wire [OFFSET_W-1:0] lookup_ty;

  pose_history_affine8 #(
    .POSE_W(POSE_W), .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .LANES(1)
  ) u_pose_history (
    .clk(clk), .rst(rst),
    .pose_wr_en(pose_wr_commit), .pose_wr_id(pose_wr_id),
    .pose_wr_m00(pose_wr_m00), .pose_wr_m01(pose_wr_m01),
    .pose_wr_m10(pose_wr_m10), .pose_wr_m11(pose_wr_m11),
    .pose_wr_tx(pose_wr_tx), .pose_wr_ty(pose_wr_ty),
    .pose_rd_id_flat(rr_pose), .pose_rd_found(lookup_found),
    .pose_rd_m00_flat(lookup_m00), .pose_rd_m01_flat(lookup_m01),
    .pose_rd_m10_flat(lookup_m10), .pose_rd_m11_flat(lookup_m11),
    .pose_rd_tx_flat(lookup_tx), .pose_rd_ty_flat(lookup_ty)
  );

  coord_transform_affine2d #(
    .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W),
    .X_MIN(X_MIN), .X_MAX(X_MAX), .Y_MIN(Y_MIN), .Y_MAX(Y_MAX)
  ) u_transform (
    .clk(clk), .rst(rst), .downstream_ready(world_ready),
    .event_valid_in(rr_valid), .pose_found_in(lookup_found[0]),
    .polarity_in(rr_polarity), .pose_version_in(rr_pose),
    .occurrence_timestamp_in(rr_time),
    .sensor_x_in(rr_sensor_x), .sensor_y_in(rr_sensor_y),
    .m00_in(lookup_m00), .m01_in(lookup_m01),
    .m10_in(lookup_m10), .m11_in(lookup_m11),
    .tx_in(lookup_tx), .ty_in(lookup_ty),
    .event_valid_out(world_valid), .upstream_ready(transform_upstream_ready),
    .mapped_valid_out(mapped_valid), .pose_found_out(pose_found),
    .in_range_out(in_range), .polarity_out(polarity),
    .pose_version_out(pose_version),
    .occurrence_timestamp_out(occurrence_timestamp_out),
    .world_x_out(world_x), .world_y_out(world_y)
  );

  // The affine block registers every other output field under the same ready
  // condition.  Carry source coordinates and tile ID beside that register.
  always @(posedge clk) begin
    if (rst) begin
      sensor_x <= {SENSOR_W{1'b0}};
      sensor_y <= {SENSOR_W{1'b0}};
      tile_id <= 2'b00;
    end else if (transform_upstream_ready) begin
      if (rr_valid) begin
        sensor_x <= rr_sensor_x;
        sensor_y <= rr_sensor_y;
        tile_id <= rr_source;
      end else begin
        sensor_x <= {SENSOR_W{1'b0}};
        sensor_y <= {SENSOR_W{1'b0}};
        tile_id <= 2'b00;
      end
    end
  end
endmodule
