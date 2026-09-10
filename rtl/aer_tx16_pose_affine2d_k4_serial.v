// Fair single-output endpoint for the measured K=4 banked transform.
//
// The four transform banks retain their independent input FIFOs, then reuse
// the verified stall-safe round-robin arbiter to expose one ready/valid world
// stream suitable for a single-port map writer. No extra output FIFO is needed:
// each transform already holds its payload stable until its bank is selected.
module aer_tx16_pose_affine2d_k4_serial #(
  parameter integer FIFO_DEPTH = 8,
  parameter integer POSE_W = 4,
  parameter integer SENSOR_W = 10,
  parameter integer RESULT_W = 16,
  parameter integer MATRIX_W = 16,
  parameter integer OFFSET_W = 24,
  parameter integer FRAC_W = 14,
  parameter integer TIMESTAMP_W = 32,
  parameter integer GUARD_COUNT_W = $clog2(33 + 4*FIFO_DEPTH),
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
  output     [SENSOR_W-1:0]          sensor_x_out,
  output     [SENSOR_W-1:0]          sensor_y_out,
  output     [1:0]                   bank_id_out,
  output                             polarity_out,
  output     [POSE_W-1:0]            pose_version_out,
  output     [TIMESTAMP_W-1:0]       occurrence_timestamp_out,
  output signed [RESULT_W-1:0]       world_x_out,
  output signed [RESULT_W-1:0]       world_y_out
);
  localparam integer K = 4;
  localparam integer MAP_LSB = 0;
  localparam integer FOUND_LSB = MAP_LSB + 1;
  localparam integer RANGE_LSB = FOUND_LSB + 1;
  localparam integer SX_LSB = RANGE_LSB + 1;
  localparam integer SY_LSB = SX_LSB + SENSOR_W;
  localparam integer POL_LSB = SY_LSB + SENSOR_W;
  localparam integer POSE_LSB = POL_LSB + 1;
  localparam integer TIME_LSB = POSE_LSB + POSE_W;
  localparam integer WX_LSB = TIME_LSB + TIMESTAMP_W;
  localparam integer WY_LSB = WX_LSB + RESULT_W;
  localparam integer STREAM_W = WY_LSB + RESULT_W;

  wire [K-1:0] bank_valid;
  wire [K-1:0] bank_ready;
  wire [K-1:0] bank_mapped;
  wire [K-1:0] bank_found;
  wire [K-1:0] bank_range;
  wire [K*SENSOR_W-1:0] bank_sensor_x_flat;
  wire [K*SENSOR_W-1:0] bank_sensor_y_flat;
  wire [K-1:0] bank_polarity;
  wire [K*POSE_W-1:0] bank_pose_flat;
  wire [K*TIMESTAMP_W-1:0] bank_time_flat;
  wire [K*RESULT_W-1:0] bank_world_x_flat;
  wire [K*RESULT_W-1:0] bank_world_y_flat;

  aer_tx16_pose_affine2d_banked #(
    .K(K), .FIFO_DEPTH(FIFO_DEPTH), .POSE_W(POSE_W),
    .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W), .MATRIX_W(MATRIX_W),
    .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W), .TIMESTAMP_W(TIMESTAMP_W),
    .GUARD_COUNT_W(GUARD_COUNT_W),
    .X_MIN(X_MIN), .X_MAX(X_MAX), .Y_MIN(Y_MIN), .Y_MAX(Y_MAX)
  ) u_banked (
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in),
    .occurrence_pose_version(occurrence_pose_version),
    .occurrence_timestamp(occurrence_timestamp),
    .aer_overrun(aer_overrun), .fifo_overflow(fifo_overflow),
    .pose_wr_req(pose_wr_req), .pose_wr_id(pose_wr_id),
    .pose_wr_m00(pose_wr_m00), .pose_wr_m01(pose_wr_m01),
    .pose_wr_m10(pose_wr_m10), .pose_wr_m11(pose_wr_m11),
    .pose_wr_tx(pose_wr_tx), .pose_wr_ty(pose_wr_ty),
    .pose_wr_ready(pose_wr_ready), .pose_wr_commit(pose_wr_commit),
    .pose_wr_rejected(pose_wr_rejected),
    .pose_accounting_error(pose_accounting_error),
    .tile_origin_x(tile_origin_x), .tile_origin_y(tile_origin_y),
    .world_valid(bank_valid), .world_ready(bank_ready),
    .mapped_valid(bank_mapped), .pose_found(bank_found),
    .in_range(bank_range), .sensor_x_out_flat(bank_sensor_x_flat),
    .sensor_y_out_flat(bank_sensor_y_flat),
    .polarity_out(bank_polarity),
    .pose_version_out_flat(bank_pose_flat),
    .occurrence_timestamp_out_flat(bank_time_flat),
    .world_x_out_flat(bank_world_x_flat),
    .world_y_out_flat(bank_world_y_flat)
  );

  wire [K*STREAM_W-1:0] bank_stream_flat;
  genvar bank;
  generate
    for (bank = 0; bank < K; bank = bank + 1) begin: pack_bank
      assign bank_stream_flat[bank*STREAM_W +: STREAM_W] = {
        bank_world_y_flat[bank*RESULT_W +: RESULT_W],
        bank_world_x_flat[bank*RESULT_W +: RESULT_W],
        bank_time_flat[bank*TIMESTAMP_W +: TIMESTAMP_W],
        bank_pose_flat[bank*POSE_W +: POSE_W],
        bank_polarity[bank],
        bank_sensor_y_flat[bank*SENSOR_W +: SENSOR_W],
        bank_sensor_x_flat[bank*SENSOR_W +: SENSOR_W],
        bank_range[bank], bank_found[bank], bank_mapped[bank]
      };
    end
  endgenerate

  wire [STREAM_W-1:0] selected_stream;
  rr_stream_arbiter4 #(.DATA_W(STREAM_W)) u_merge (
    .clk(clk), .rst(rst), .in_valid(bank_valid),
    .in_data_flat(bank_stream_flat), .in_ready(bank_ready),
    .out_valid(world_valid), .out_data(selected_stream),
    .out_source(bank_id_out), .out_ready(world_ready)
  );

  assign mapped_valid = selected_stream[MAP_LSB];
  assign pose_found = selected_stream[FOUND_LSB];
  assign in_range = selected_stream[RANGE_LSB];
  assign sensor_x_out = selected_stream[SX_LSB +: SENSOR_W];
  assign sensor_y_out = selected_stream[SY_LSB +: SENSOR_W];
  assign polarity_out = selected_stream[POL_LSB];
  assign pose_version_out = selected_stream[POSE_LSB +: POSE_W];
  assign occurrence_timestamp_out =
    selected_stream[TIME_LSB +: TIMESTAMP_W];
  assign world_x_out = selected_stream[WX_LSB +: RESULT_W];
  assign world_y_out = selected_stream[WY_LSB +: RESULT_W];
endmodule
