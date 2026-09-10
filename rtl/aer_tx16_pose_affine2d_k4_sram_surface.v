// End-to-end 4x4 K=4 AER -> affine transforms -> four-bank SRAM surface.
//
// Transform lanes are not tied to memory banks. The surface routes each valid
// mapped event by world_x modulo four, so all updates to one world cell reach
// the same timestamp-resolving writer. Same-bank contention backpressures the
// corresponding transforms; no event is dropped inside the map crossbar.
module aer_tx16_pose_affine2d_k4_sram_surface #(
  parameter integer FIFO_DEPTH = 8,
  parameter integer POSE_W = 4,
  parameter integer SENSOR_W = 10,
  parameter integer RESULT_W = 16,
  parameter integer MATRIX_W = 16,
  parameter integer OFFSET_W = 24,
  parameter integer FRAC_W = 14,
  parameter integer TIMESTAMP_W = 32,
  parameter integer GUARD_COUNT_W = $clog2(33 + 4*FIFO_DEPTH),
  parameter integer GRID_W = 256,
  parameter integer GRID_H = 256,
  parameter integer BANK_ADDR_W = (((GRID_W / 4) * GRID_H) <= 1)
                                ? 1 : $clog2((GRID_W / 4) * GRID_H)
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

  output     [3:0]                   world_valid,
  output     [3:0]                   world_ready,
  output     [3:0]                   mapped_valid,
  output     [3:0]                   pose_found,
  output     [3:0]                   in_range,
  output     [4*SENSOR_W-1:0]        sensor_x_out_flat,
  output     [4*SENSOR_W-1:0]        sensor_y_out_flat,
  output     [3:0]                   polarity_out,
  output     [4*POSE_W-1:0]          pose_version_out_flat,
  output     [4*TIMESTAMP_W-1:0]     occurrence_timestamp_out_flat,
  output     [4*RESULT_W-1:0]        world_x_out_flat,
  output     [4*RESULT_W-1:0]        world_y_out_flat,

  output     [3:0]                   surface_update_applied,
  output     [3:0]                   surface_equal_time_merged,
  output     [3:0]                   surface_stale_ignored,
  output     [3:0]                   surface_range_error,

  output     [3:0]                   mem_rd_req_valid,
  input      [3:0]                   mem_rd_req_ready,
  output     [4*BANK_ADDR_W-1:0]     mem_rd_req_addr_flat,
  input      [3:0]                   mem_rd_rsp_valid,
  output     [3:0]                   mem_rd_rsp_ready,
  input      [3:0]                   mem_rd_rsp_cell_valid,
  input      [4*TIMESTAMP_W-1:0]     mem_rd_rsp_timestamp_flat,
  input      [7:0]                   mem_rd_rsp_polarity_seen_flat,
  output     [3:0]                   mem_wr_req_valid,
  input      [3:0]                   mem_wr_req_ready,
  output     [4*BANK_ADDR_W-1:0]     mem_wr_req_addr_flat,
  output     [3:0]                   mem_wr_req_cell_valid,
  output     [4*TIMESTAMP_W-1:0]     mem_wr_req_timestamp_flat,
  output     [7:0]                   mem_wr_req_polarity_seen_flat
);
  aer_tx16_pose_affine2d_banked #(
    .K(4), .FIFO_DEPTH(FIFO_DEPTH), .POSE_W(POSE_W),
    .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .TIMESTAMP_W(TIMESTAMP_W), .GUARD_COUNT_W(GUARD_COUNT_W),
    .X_MIN(0), .X_MAX(GRID_W-1), .Y_MIN(0), .Y_MAX(GRID_H-1)
  ) u_tx (
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
    .world_valid(world_valid), .world_ready(world_ready),
    .mapped_valid(mapped_valid), .pose_found(pose_found),
    .in_range(in_range), .sensor_x_out_flat(sensor_x_out_flat),
    .sensor_y_out_flat(sensor_y_out_flat),
    .polarity_out(polarity_out),
    .pose_version_out_flat(pose_version_out_flat),
    .occurrence_timestamp_out_flat(occurrence_timestamp_out_flat),
    .world_x_out_flat(world_x_out_flat),
    .world_y_out_flat(world_y_out_flat)
  );

  world_time_surface_sram_banked4 #(
    .GRID_W(GRID_W), .GRID_H(GRID_H), .COORD_W(RESULT_W),
    .TIMESTAMP_W(TIMESTAMP_W), .ADDR_W(BANK_ADDR_W)
  ) u_surface (
    .clk(clk), .rst(rst),
    .event_valid(world_valid), .event_ready(world_ready),
    .mapped_valid(mapped_valid), .world_x_flat(world_x_out_flat),
    .world_y_flat(world_y_out_flat), .polarity(polarity_out),
    .occurrence_timestamp_flat(occurrence_timestamp_out_flat),
    .update_applied(surface_update_applied),
    .equal_time_merged(surface_equal_time_merged),
    .stale_ignored(surface_stale_ignored),
    .range_error(surface_range_error),
    .mem_rd_req_valid(mem_rd_req_valid),
    .mem_rd_req_ready(mem_rd_req_ready),
    .mem_rd_req_addr_flat(mem_rd_req_addr_flat),
    .mem_rd_rsp_valid(mem_rd_rsp_valid),
    .mem_rd_rsp_ready(mem_rd_rsp_ready),
    .mem_rd_rsp_cell_valid(mem_rd_rsp_cell_valid),
    .mem_rd_rsp_timestamp_flat(mem_rd_rsp_timestamp_flat),
    .mem_rd_rsp_polarity_seen_flat(mem_rd_rsp_polarity_seen_flat),
    .mem_wr_req_valid(mem_wr_req_valid),
    .mem_wr_req_ready(mem_wr_req_ready),
    .mem_wr_req_addr_flat(mem_wr_req_addr_flat),
    .mem_wr_req_cell_valid(mem_wr_req_cell_valid),
    .mem_wr_req_timestamp_flat(mem_wr_req_timestamp_flat),
    .mem_wr_req_polarity_seen_flat(mem_wr_req_polarity_seen_flat)
  );
endmodule
