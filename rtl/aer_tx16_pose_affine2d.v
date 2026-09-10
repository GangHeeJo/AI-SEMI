// Complete 4x4 Stage-2 proof pipeline:
//   pose-tagged AER -> bitmap expansion -> pose-history lookup
//   -> eight parallel affine transforms.
//
// There is deliberately no world memory here.  Every accepted event remains
// visible at the output, including missing-pose and out-of-range events.
module aer_tx16_pose_affine2d #(
  parameter POSE_W   = 4,
  parameter SENSOR_W = 10,
  parameter RESULT_W = 16,
  parameter MATRIX_W = 16,
  parameter OFFSET_W = 24,
  parameter FRAC_W   = 14,
  parameter TIMESTAMP_W = 32,
  parameter POSE_COUNT_W = 8,
  parameter integer X_MIN = 0,
  parameter integer X_MAX = 255,
  parameter integer Y_MIN = 0,
  parameter integer Y_MAX = 255
)(
  input                              clk,
  input                              rst,
  input      [15:0]                  arrival,
  input      [15:0]                  polarity_in,
  input      [POSE_W-1:0]            occurrence_pose_version,
  input      [TIMESTAMP_W-1:0]       occurrence_timestamp,
  output     [15:0]                  overrun,

  input                              pose_wr_en,
  input      [POSE_W-1:0]            pose_wr_id,
  input signed [MATRIX_W-1:0]        pose_wr_m00,
  input signed [MATRIX_W-1:0]        pose_wr_m01,
  input signed [MATRIX_W-1:0]        pose_wr_m10,
  input signed [MATRIX_W-1:0]        pose_wr_m11,
  input signed [OFFSET_W-1:0]        pose_wr_tx,
  input signed [OFFSET_W-1:0]        pose_wr_ty,
  output                             pose_wr_ready,
  output                             pose_wr_rejected,
  output                             pose_accounting_error,

  input      [SENSOR_W-1:0]          tile_origin_x,
  input      [SENSOR_W-1:0]          tile_origin_y,

  output     [7:0]                   event_valid_out,
  output     [7:0]                   mapped_valid_out,
  output     [7:0]                   pose_found_out,
  output     [7:0]                   in_range_out,
  output     [7:0]                   polarity_out,
  output     [8*POSE_W-1:0]          pose_version_out_flat,
  output     [8*TIMESTAMP_W-1:0]     occurrence_timestamp_out_flat,
  output     [8*RESULT_W-1:0]        world_x_out_flat,
  output     [8*RESULT_W-1:0]        world_y_out_flat
);
  wire aer_valid0, aer_valid1;
  wire [1:0] aer_row0, aer_row1;
  wire [3:0] aer_cols0, aer_cols1;
  wire [3:0] aer_pols0, aer_pols1;
  wire [(4*POSE_W)-1:0] aer_poses0, aer_poses1;
  wire [(4*TIMESTAMP_W)-1:0] aer_times0, aer_times1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose #(
    .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W)
  ) u_aer (
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in),
    .pose_version(occurrence_pose_version),
    .occurrence_timestamp(occurrence_timestamp), .overrun(overrun),
    .valid0(aer_valid0), .row0(aer_row0), .col_mask0(aer_cols0),
    .pol_mask0(aer_pols0), .pose_tags0(aer_poses0), .time_tags0(aer_times0),
    .valid1(aer_valid1), .row1(aer_row1), .col_mask1(aer_cols1),
    .pol_mask1(aer_pols1), .pose_tags1(aer_poses1), .time_tags1(aer_times1)
  );

  wire [7:0] event_valid_c;
  wire [8*SENSOR_W-1:0] sensor_x_flat;
  wire [8*SENSOR_W-1:0] sensor_y_flat;
  wire [7:0] polarity_c;
  wire [8*POSE_W-1:0] pose_id_flat;
  wire [8*TIMESTAMP_W-1:0] timestamp_flat;

  aer_bitmap_to_event8_pose #(
    .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W), .SENSOR_W(SENSOR_W)
  ) u_expand (
    .valid0(aer_valid0), .row0(aer_row0), .col_mask0(aer_cols0),
    .pol_mask0(aer_pols0), .pose_tags0(aer_poses0), .time_tags0(aer_times0),
    .valid1(aer_valid1), .row1(aer_row1), .col_mask1(aer_cols1),
    .pol_mask1(aer_pols1), .pose_tags1(aer_poses1), .time_tags1(aer_times1),
    .tile_origin_x(tile_origin_x), .tile_origin_y(tile_origin_y),
    .event_valid(event_valid_c), .sensor_x_flat(sensor_x_flat),
    .sensor_y_flat(sensor_y_flat), .polarity(polarity_c),
    .pose_version_flat(pose_id_flat),
    .occurrence_timestamp_flat(timestamp_flat)
  );

  wire [7:0] pose_found_c;
  wire [8*MATRIX_W-1:0] m00_flat, m01_flat, m10_flat, m11_flat;
  wire [8*OFFSET_W-1:0] tx_flat, ty_flat;
  wire pose_wr_commit;

  pose_inflight_guard8 #(
    .POSE_W(POSE_W), .COUNT_W(POSE_COUNT_W),
    .RETIRE_LANES(8), .ACCEPT_SOURCES(16)
  ) u_pose_guard (
    .clk(clk), .rst(rst),
    .accepted_mask(arrival & ~overrun),
    .accepted_pose_version(occurrence_pose_version),
    .retire_valid(event_valid_c),
    .retire_pose_version_flat(pose_id_flat),
    .pose_wr_req(pose_wr_en), .pose_wr_id(pose_wr_id),
    .pose_wr_ready(pose_wr_ready), .pose_wr_commit(pose_wr_commit),
    .pose_wr_rejected(pose_wr_rejected),
    .accounting_error(pose_accounting_error)
  );

  pose_history_affine8 #(
    .POSE_W(POSE_W), .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .LANES(8)
  ) u_pose_history (
    .clk(clk), .rst(rst), .pose_wr_en(pose_wr_commit), .pose_wr_id(pose_wr_id),
    .pose_wr_m00(pose_wr_m00), .pose_wr_m01(pose_wr_m01),
    .pose_wr_m10(pose_wr_m10), .pose_wr_m11(pose_wr_m11),
    .pose_wr_tx(pose_wr_tx), .pose_wr_ty(pose_wr_ty),
    .pose_rd_id_flat(pose_id_flat), .pose_rd_found(pose_found_c),
    .pose_rd_m00_flat(m00_flat), .pose_rd_m01_flat(m01_flat),
    .pose_rd_m10_flat(m10_flat), .pose_rd_m11_flat(m11_flat),
    .pose_rd_tx_flat(tx_flat), .pose_rd_ty_flat(ty_flat)
  );

  genvar g;
  generate
    for (g = 0; g < 8; g = g + 1) begin: transform_lane
      wire signed [RESULT_W-1:0] world_x_lane;
      wire signed [RESULT_W-1:0] world_y_lane;

      coord_transform_affine2d #(
        .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
        .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
        .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W),
        .X_MIN(X_MIN), .X_MAX(X_MAX),
        .Y_MIN(Y_MIN), .Y_MAX(Y_MAX)
      ) u_transform (
        .clk(clk), .rst(rst),
        .downstream_ready(1'b1), .upstream_ready(),
        .event_valid_in(event_valid_c[g]), .pose_found_in(pose_found_c[g]),
        .polarity_in(polarity_c[g]),
        .pose_version_in(pose_id_flat[g*POSE_W +: POSE_W]),
        .occurrence_timestamp_in(timestamp_flat[g*TIMESTAMP_W +: TIMESTAMP_W]),
        .sensor_x_in(sensor_x_flat[g*SENSOR_W +: SENSOR_W]),
        .sensor_y_in(sensor_y_flat[g*SENSOR_W +: SENSOR_W]),
        .m00_in(m00_flat[g*MATRIX_W +: MATRIX_W]),
        .m01_in(m01_flat[g*MATRIX_W +: MATRIX_W]),
        .m10_in(m10_flat[g*MATRIX_W +: MATRIX_W]),
        .m11_in(m11_flat[g*MATRIX_W +: MATRIX_W]),
        .tx_in(tx_flat[g*OFFSET_W +: OFFSET_W]),
        .ty_in(ty_flat[g*OFFSET_W +: OFFSET_W]),
        .event_valid_out(event_valid_out[g]),
        .mapped_valid_out(mapped_valid_out[g]),
        .pose_found_out(pose_found_out[g]),
        .in_range_out(in_range_out[g]),
        .polarity_out(polarity_out[g]),
        .pose_version_out(pose_version_out_flat[g*POSE_W +: POSE_W]),
        .occurrence_timestamp_out(
          occurrence_timestamp_out_flat[g*TIMESTAMP_W +: TIMESTAMP_W]),
        .world_x_out(world_x_lane), .world_y_out(world_y_lane)
      );

      assign world_x_out_flat[g*RESULT_W +: RESULT_W] = world_x_lane;
      assign world_y_out_flat[g*RESULT_W +: RESULT_W] = world_y_lane;
    end
  endgenerate
endmodule
