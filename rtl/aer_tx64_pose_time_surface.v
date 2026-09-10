// Closed Stage-2 path:
//   8x8 sensor -> four AER leaves -> tile FIFOs/RR -> pose transform
//   -> occurrence-time-ordered reference-grid surface.
//
// world_time_surface is the sole stream consumer and is always ready outside
// reset.  Transform bounds exactly match the memory grid, so an out-of-range
// transform is consumed for accounting but cannot update the surface.
module aer_tx64_pose_time_surface #(
  parameter integer POSE_W = 4,
  parameter integer SENSOR_W = 10,
  parameter integer COORD_W = 16,
  parameter integer MATRIX_W = 16,
  parameter integer OFFSET_W = 24,
  parameter integer FRAC_W = 14,
  parameter integer TIMESTAMP_W = 32,
  parameter integer FIFO_DEPTH = 32,
  parameter integer GUARD_COUNT_W = $clog2(129 + 4*FIFO_DEPTH),
  parameter integer GRID_W = 16,
  parameter integer GRID_H = 16
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

  output                             world_event_valid,
  output                             world_event_ready,
  output                             world_mapped_valid,
  output                             world_pose_found,
  output                             world_in_range,
  output     [SENSOR_W-1:0]          world_sensor_x,
  output     [SENSOR_W-1:0]          world_sensor_y,
  output     [1:0]                   world_tile_id,
  output                             world_polarity,
  output     [POSE_W-1:0]            world_pose_version,
  output     [TIMESTAMP_W-1:0]       world_occurrence_timestamp,
  output signed [COORD_W-1:0]        world_x,
  output signed [COORD_W-1:0]        world_y,

  output                             surface_update_applied,
  output                             surface_equal_time_merged,
  output                             surface_stale_ignored,
  output                             surface_range_error,
  input      [$clog2(GRID_W)-1:0]    read_x,
  input      [$clog2(GRID_H)-1:0]    read_y,
  output                             read_valid,
  output     [TIMESTAMP_W-1:0]       read_timestamp,
  output     [1:0]                   read_polarity_seen
);
  aer_tx64_pose_affine2d_serial #(
    .POSE_W(POSE_W), .SENSOR_W(SENSOR_W), .RESULT_W(COORD_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .TIMESTAMP_W(TIMESTAMP_W), .FIFO_DEPTH(FIFO_DEPTH),
    .GUARD_COUNT_W(GUARD_COUNT_W),
    .X_MIN(0), .X_MAX(GRID_W-1), .Y_MIN(0), .Y_MAX(GRID_H-1)
  ) u_serial (
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in),
    .occurrence_pose_version(occurrence_pose_version),
    .occurrence_timestamp(occurrence_timestamp),
    .aer_overrun(aer_overrun),
    .tile_fifo_overflow(tile_fifo_overflow),
    .pose_wr_req(pose_wr_req), .pose_wr_id(pose_wr_id),
    .pose_wr_m00(pose_wr_m00), .pose_wr_m01(pose_wr_m01),
    .pose_wr_m10(pose_wr_m10), .pose_wr_m11(pose_wr_m11),
    .pose_wr_tx(pose_wr_tx), .pose_wr_ty(pose_wr_ty),
    .pose_wr_ready(pose_wr_ready), .pose_wr_commit(pose_wr_commit),
    .pose_wr_rejected(pose_wr_rejected),
    .pose_accounting_error(pose_accounting_error),
    .base_sensor_origin_x(base_sensor_origin_x),
    .base_sensor_origin_y(base_sensor_origin_y),
    .world_valid(world_event_valid), .world_ready(world_event_ready),
    .mapped_valid(world_mapped_valid), .pose_found(world_pose_found),
    .in_range(world_in_range),
    .sensor_x(world_sensor_x), .sensor_y(world_sensor_y),
    .tile_id(world_tile_id), .polarity(world_polarity),
    .pose_version(world_pose_version),
    .occurrence_timestamp_out(world_occurrence_timestamp),
    .world_x(world_x), .world_y(world_y)
  );

  world_time_surface #(
    .GRID_W(GRID_W), .GRID_H(GRID_H), .COORD_W(COORD_W),
    .TIMESTAMP_W(TIMESTAMP_W)
  ) u_surface (
    .clk(clk), .rst(rst),
    .event_valid(world_event_valid), .event_ready(world_event_ready),
    .mapped_valid(world_mapped_valid),
    .world_x(world_x), .world_y(world_y),
    .polarity(world_polarity),
    .occurrence_timestamp(world_occurrence_timestamp),
    .update_applied(surface_update_applied),
    .equal_time_merged(surface_equal_time_merged),
    .stale_ignored(surface_stale_ignored),
    .range_error(surface_range_error),
    .read_x(read_x), .read_y(read_y),
    .read_valid(read_valid), .read_timestamp(read_timestamp),
    .read_polarity_seen(read_polarity_seen)
  );
endmodule
