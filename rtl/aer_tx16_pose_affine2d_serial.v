// K=1 Stage-2 endpoint:
//   pose/timestamp AER -> bitmap expansion -> batch FIFO
//   -> one-port pose lookup -> ready-aware affine transform.
//
// AER overruns were never admitted. FIFO overflow bits are explicit terminal
// drops. All remaining events retire from the pose in-flight guard when the
// transform captures them, so a pose entry may be reused while the already
// transformed result is held under downstream backpressure.
// tile_origin_x/y are static physical configuration and must remain constant
// while rst is deasserted; they are intentionally not copied into every event.
module aer_tx16_pose_affine2d_serial #(
  parameter integer POSE_W = 4,
  parameter integer SENSOR_W = 10,
  parameter integer RESULT_W = 16,
  parameter integer MATRIX_W = 16,
  parameter integer OFFSET_W = 24,
  parameter integer FRAC_W = 14,
  parameter integer TIMESTAMP_W = 32,
  parameter integer FIFO_DEPTH = 32,
  parameter integer GUARD_COUNT_W = 8,
  parameter integer X_MIN = 0,
  parameter integer X_MAX = 255,
  parameter integer Y_MIN = 0,
  parameter integer Y_MAX = 255
) (
  input                              clk,
  input                              rst,
  input      [15:0]                  arrival,
  input      [15:0]                  polarity_in,
  input      [POSE_W-1:0]            occurrence_pose_version,
  input      [TIMESTAMP_W-1:0]       occurrence_timestamp,
  output     [15:0]                  aer_overrun,
  output     [7:0]                   fifo_overflow,

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

  input      [SENSOR_W-1:0]          tile_origin_x,
  input      [SENSOR_W-1:0]          tile_origin_y,

  output                             world_valid,
  input                              world_ready,
  output                             mapped_valid,
  output                             pose_found,
  output                             in_range,
  output reg [SENSOR_W-1:0]          sensor_x,
  output reg [SENSOR_W-1:0]          sensor_y,
  output                             polarity,
  output     [POSE_W-1:0]            pose_version,
  output     [TIMESTAMP_W-1:0]       occurrence_timestamp_out,
  output signed [RESULT_W-1:0]       world_x,
  output signed [RESULT_W-1:0]       world_y
);
  localparam integer EVENT_W = (2*SENSOR_W) + 1 + POSE_W + TIMESTAMP_W;
  localparam integer SX_LSB = 0;
  localparam integer SY_LSB = SX_LSB + SENSOR_W;
  localparam integer POL_LSB = SY_LSB + SENSOR_W;
  localparam integer POSE_LSB = POL_LSB + 1;
  localparam integer TIME_LSB = POSE_LSB + POSE_W;

  wire aer_valid0;
  wire aer_valid1;
  wire [1:0] aer_row0;
  wire [1:0] aer_row1;
  wire [3:0] aer_cols0;
  wire [3:0] aer_cols1;
  wire [3:0] aer_pols0;
  wire [3:0] aer_pols1;
  wire [(4*POSE_W)-1:0] aer_poses0;
  wire [(4*POSE_W)-1:0] aer_poses1;
  wire [(4*TIMESTAMP_W)-1:0] aer_times0;
  wire [(4*TIMESTAMP_W)-1:0] aer_times1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose #(
    .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W)
  ) u_aer (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in),
    .pose_version(occurrence_pose_version),
    .occurrence_timestamp(occurrence_timestamp),
    .overrun(aer_overrun),
    .valid0(aer_valid0), .row0(aer_row0), .col_mask0(aer_cols0),
    .pol_mask0(aer_pols0), .pose_tags0(aer_poses0), .time_tags0(aer_times0),
    .valid1(aer_valid1), .row1(aer_row1), .col_mask1(aer_cols1),
    .pol_mask1(aer_pols1), .pose_tags1(aer_poses1), .time_tags1(aer_times1)
  );

  wire [7:0] batch_valid;
  wire [8*SENSOR_W-1:0] batch_x_flat;
  wire [8*SENSOR_W-1:0] batch_y_flat;
  wire [7:0] batch_polarity;
  wire [8*POSE_W-1:0] batch_pose_flat;
  wire [8*TIMESTAMP_W-1:0] batch_time_flat;

  aer_bitmap_to_event8_pose #(
    .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W), .SENSOR_W(SENSOR_W)
  ) u_expand (
    .valid0(aer_valid0), .row0(aer_row0), .col_mask0(aer_cols0),
    .pol_mask0(aer_pols0), .pose_tags0(aer_poses0), .time_tags0(aer_times0),
    .valid1(aer_valid1), .row1(aer_row1), .col_mask1(aer_cols1),
    .pol_mask1(aer_pols1), .pose_tags1(aer_poses1), .time_tags1(aer_times1),
    .tile_origin_x(tile_origin_x), .tile_origin_y(tile_origin_y),
    .event_valid(batch_valid), .sensor_x_flat(batch_x_flat),
    .sensor_y_flat(batch_y_flat), .polarity(batch_polarity),
    .pose_version_flat(batch_pose_flat),
    .occurrence_timestamp_flat(batch_time_flat)
  );

  wire [8*EVENT_W-1:0] fifo_in_data_flat;
  genvar lane;
  generate
    for (lane = 0; lane < 8; lane = lane + 1) begin: pack_event
      assign fifo_in_data_flat[lane*EVENT_W +: EVENT_W] = {
        batch_time_flat[lane*TIMESTAMP_W +: TIMESTAMP_W],
        batch_pose_flat[lane*POSE_W +: POSE_W],
        batch_polarity[lane],
        batch_y_flat[lane*SENSOR_W +: SENSOR_W],
        batch_x_flat[lane*SENSOR_W +: SENSOR_W]
      };
    end
  endgenerate

  wire fifo_out_valid;
  wire [EVENT_W-1:0] fifo_out_data;
  wire fifo_out_ready;
  wire [$clog2(FIFO_DEPTH+1)-1:0] fifo_occupancy;

  event_batch_fifo #(
    .DATA_W(EVENT_W), .IN_LANES(8), .DEPTH(FIFO_DEPTH)
  ) u_fifo (
    .clk(clk), .rst(rst),
    .in_valid(batch_valid), .in_data_flat(fifo_in_data_flat),
    .in_overflow(fifo_overflow),
    .out_valid(fifo_out_valid), .out_data(fifo_out_data),
    .out_ready(fifo_out_ready), .occupancy(fifo_occupancy)
  );

  wire [SENSOR_W-1:0] fifo_sensor_x =
    fifo_out_data[SX_LSB +: SENSOR_W];
  wire [SENSOR_W-1:0] fifo_sensor_y =
    fifo_out_data[SY_LSB +: SENSOR_W];
  wire fifo_polarity = fifo_out_data[POL_LSB];
  wire [POSE_W-1:0] fifo_pose = fifo_out_data[POSE_LSB +: POSE_W];
  wire [TIMESTAMP_W-1:0] fifo_time =
    fifo_out_data[TIME_LSB +: TIMESTAMP_W];
  wire transform_accept = fifo_out_valid & fifo_out_ready;

  // Every source accepted by the depth-2 AER is outstanding until either its
  // expanded event is explicitly dropped or the transform captures it.
  wire [8:0] retire_valid;
  wire [(9*POSE_W)-1:0] retire_pose_flat;
  assign retire_valid[7:0] = fifo_overflow;
  assign retire_valid[8] = transform_accept;
  generate
    for (lane = 0; lane < 8; lane = lane + 1) begin: drop_retire_pose
      assign retire_pose_flat[lane*POSE_W +: POSE_W] =
        batch_pose_flat[lane*POSE_W +: POSE_W];
    end
  endgenerate
  assign retire_pose_flat[8*POSE_W +: POSE_W] = fifo_pose;

  pose_inflight_guard8 #(
    .POSE_W(POSE_W), .COUNT_W(GUARD_COUNT_W),
    .ACCEPT_SOURCES(16), .RETIRE_LANES(9)
  ) u_pose_guard (
    .clk(clk), .rst(rst),
    .accepted_mask(arrival & ~aer_overrun),
    .accepted_pose_version(occurrence_pose_version),
    .retire_valid(retire_valid),
    .retire_pose_version_flat(retire_pose_flat),
    .pose_wr_req(pose_wr_req), .pose_wr_id(pose_wr_id),
    .pose_wr_ready(pose_wr_ready), .pose_wr_commit(pose_wr_commit),
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
    .pose_rd_id_flat(fifo_pose), .pose_rd_found(lookup_found),
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
    .event_valid_in(fifo_out_valid), .pose_found_in(lookup_found[0]),
    .polarity_in(fifo_polarity), .pose_version_in(fifo_pose),
    .occurrence_timestamp_in(fifo_time),
    .sensor_x_in(fifo_sensor_x), .sensor_y_in(fifo_sensor_y),
    .m00_in(lookup_m00), .m01_in(lookup_m01),
    .m10_in(lookup_m10), .m11_in(lookup_m11),
    .tx_in(lookup_tx), .ty_in(lookup_ty),
    .event_valid_out(world_valid), .upstream_ready(fifo_out_ready),
    .mapped_valid_out(mapped_valid), .pose_found_out(pose_found),
    .in_range_out(in_range), .polarity_out(polarity),
    .pose_version_out(pose_version),
    .occurrence_timestamp_out(occurrence_timestamp_out),
    .world_x_out(world_x), .world_y_out(world_y)
  );

  // The transform's one-entry elastic output holds its fields while blocked.
  // Register the source coordinate under the identical enable condition.
  always @(posedge clk) begin
    if (rst) begin
      sensor_x <= {SENSOR_W{1'b0}};
      sensor_y <= {SENSOR_W{1'b0}};
    end else if (fifo_out_ready) begin
      if (fifo_out_valid) begin
        sensor_x <= fifo_sensor_x;
        sensor_y <= fifo_sensor_y;
      end else begin
        sensor_x <= {SENSOR_W{1'b0}};
        sensor_y <= {SENSOR_W{1'b0}};
      end
    end
  end
endmodule
