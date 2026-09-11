// Two real 8x8 AER/affine regions arranged as one 16x8 sensor proof.
// The loader owns occurrence pose tags and gives each region its own affine.
// Outputs stay independent; a full-sensor merge is outside this proof.
module aer_tx128_region_pose_affine2d_dual #(
  parameter integer POSE_W = 1,
  parameter integer SENSOR_W = 10,
  parameter integer RESULT_W = 16,
  parameter integer MATRIX_W = 16,
  parameter integer OFFSET_W = 24,
  parameter integer FRAC_W = 14,
  parameter integer TIMESTAMP_W = 32,
  parameter integer FIFO_DEPTH = 32,
  parameter integer GUARD_COUNT_W = $clog2(129 + 4*FIFO_DEPTH),
  parameter integer X_MIN = 0,
  parameter integer X_MAX = 511,
  parameter integer Y_MIN = 0,
  parameter integer Y_MAX = 255
) (
  input                              clk,
  input                              rst,
  input      [127:0]                 arrival,
  input      [127:0]                 polarity_in,
  input      [TIMESTAMP_W-1:0]       occurrence_timestamp,
  output                             sensor_ready,
  output     [127:0]                 arrival_blocked,
  output     [127:0]                 aer_overrun,
  output     [63:0]                  region_fifo_overflow,
  input                              cfg_valid,
  output                             cfg_ready,
  input      [1:0]                   cfg_op,
  input                              cfg_region_x,
  input                              cfg_region_y,
  input      [POSE_W-1:0]            cfg_pose_version,
  input signed [MATRIX_W-1:0]        cfg_m00,
  input signed [MATRIX_W-1:0]        cfg_m01,
  input signed [MATRIX_W-1:0]        cfg_m10,
  input signed [MATRIX_W-1:0]        cfg_m11,
  input signed [OFFSET_W-1:0]        cfg_tx,
  input signed [OFFSET_W-1:0]        cfg_ty,
  output                             active_pose_valid,
  output     [POSE_W-1:0]            active_pose_version,
  output                             cfg_busy,
  output                             cfg_awaiting_publish,
  output                             cfg_publish_pulse,
  output                             cfg_protocol_error,
  input      [SENSOR_W-1:0]          base_sensor_origin_x,
  input      [SENSOR_W-1:0]          base_sensor_origin_y,
  output     [1:0]                   world_valid,
  input      [1:0]                   world_ready,
  output     [1:0]                   mapped_valid,
  output     [(2*SENSOR_W)-1:0]      sensor_x_flat,
  output     [(2*SENSOR_W)-1:0]      sensor_y_flat,
  output     [1:0]                   polarity,
  output     [(2*POSE_W)-1:0]        pose_version_flat,
  output     [(2*TIMESTAMP_W)-1:0]   timestamp_flat,
  output     [(2*RESULT_W)-1:0]      world_x_flat,
  output     [(2*RESULT_W)-1:0]      world_y_flat,
  output     [1:0]                   pose_wr_rejected,
  output     [1:0]                   pose_accounting_error
);
  wire region_wr_req;
  wire region_wr_x;
  wire region_wr_y;
  wire [POSE_W-1:0] region_wr_pose;
  wire signed [MATRIX_W-1:0] region_wr_m00;
  wire signed [MATRIX_W-1:0] region_wr_m01;
  wire signed [MATRIX_W-1:0] region_wr_m10;
  wire signed [MATRIX_W-1:0] region_wr_m11;
  wire signed [OFFSET_W-1:0] region_wr_tx;
  wire signed [OFFSET_W-1:0] region_wr_ty;
  wire [1:0] local_wr_req;
  wire [1:0] local_wr_ready;
  wire [1:0] local_wr_commit;
  wire address_valid = !region_wr_y;

  assign local_wr_req[0] = region_wr_req && address_valid && !region_wr_x;
  assign local_wr_req[1] = region_wr_req && address_valid && region_wr_x;

  affine_region_pose_loader #(
    .REGION_COLS(2), .REGION_ROWS(1),
    .REGION_X_W(1), .REGION_Y_W(1),
    .POSE_W(POSE_W), .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W)
  ) u_loader (
    .clk(clk), .rst(rst),
    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_op(cfg_op),
    .cfg_region_x(cfg_region_x), .cfg_region_y(cfg_region_y),
    .cfg_pose_version(cfg_pose_version),
    .cfg_m00(cfg_m00), .cfg_m01(cfg_m01),
    .cfg_m10(cfg_m10), .cfg_m11(cfg_m11),
    .cfg_tx(cfg_tx), .cfg_ty(cfg_ty),
    .region_wr_req(region_wr_req),
    .region_wr_x(region_wr_x), .region_wr_y(region_wr_y),
    .region_wr_pose_version(region_wr_pose),
    .region_wr_m00(region_wr_m00), .region_wr_m01(region_wr_m01),
    .region_wr_m10(region_wr_m10), .region_wr_m11(region_wr_m11),
    .region_wr_tx(region_wr_tx), .region_wr_ty(region_wr_ty),
    .region_wr_ready(address_valid && local_wr_ready[region_wr_x]),
    .region_wr_commit(address_valid && local_wr_commit[region_wr_x]),
    .region_pose_accounting_error(|pose_accounting_error),
    .active_pose_valid(active_pose_valid),
    .active_pose_version(active_pose_version),
    .load_busy(cfg_busy), .awaiting_publish(cfg_awaiting_publish),
    .expected_region_x(), .expected_region_y(), .load_pose_version(),
    .publish_pulse(cfg_publish_pulse),
    .cfg_protocol_error(cfg_protocol_error)
  );

  // The pulse-source AER has no ready input.  Report and gate arrivals until
  // the first complete coefficient epoch is published.
  assign sensor_ready = !rst && active_pose_valid &&
                        !(|pose_accounting_error);
  assign arrival_blocked = arrival & {128{!sensor_ready}};
  wire [127:0] admitted_arrival = arrival & {128{sensor_ready}};

  genvar region;
  generate
    for (region = 0; region < 2; region = region + 1) begin: region_path
      localparam integer X_OFFSET = region * 8;
      wire [SENSOR_W-1:0] region_origin_x =
        base_sensor_origin_x + X_OFFSET;
      wire unused_pose_found;
      wire unused_in_range;
      wire [1:0] unused_tile_id;

      aer_tx64_pose_affine2d_serial #(
        .POSE_W(POSE_W), .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
        .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
        .TIMESTAMP_W(TIMESTAMP_W), .FIFO_DEPTH(FIFO_DEPTH),
        .GUARD_COUNT_W(GUARD_COUNT_W),
        .X_MIN(X_MIN), .X_MAX(X_MAX), .Y_MIN(Y_MIN), .Y_MAX(Y_MAX)
      ) u_region (
        .clk(clk), .rst(rst),
        .arrival(admitted_arrival[region*64 +: 64]),
        .polarity_in(polarity_in[region*64 +: 64]),
        .occurrence_pose_version(active_pose_version),
        .occurrence_timestamp(occurrence_timestamp),
        .aer_overrun(aer_overrun[region*64 +: 64]),
        .tile_fifo_overflow(region_fifo_overflow[region*32 +: 32]),
        .pose_wr_req(local_wr_req[region]), .pose_wr_id(region_wr_pose),
        .pose_wr_m00(region_wr_m00), .pose_wr_m01(region_wr_m01),
        .pose_wr_m10(region_wr_m10), .pose_wr_m11(region_wr_m11),
        .pose_wr_tx(region_wr_tx), .pose_wr_ty(region_wr_ty),
        .pose_wr_ready(local_wr_ready[region]),
        .pose_wr_commit(local_wr_commit[region]),
        .pose_wr_rejected(pose_wr_rejected[region]),
        .pose_accounting_error(pose_accounting_error[region]),
        .base_sensor_origin_x(region_origin_x),
        .base_sensor_origin_y(base_sensor_origin_y),
        .world_valid(world_valid[region]),
        .world_ready(world_ready[region]),
        .mapped_valid(mapped_valid[region]),
        .pose_found(unused_pose_found), .in_range(unused_in_range),
        .sensor_x(sensor_x_flat[region*SENSOR_W +: SENSOR_W]),
        .sensor_y(sensor_y_flat[region*SENSOR_W +: SENSOR_W]),
        .tile_id(unused_tile_id), .polarity(polarity[region]),
        .pose_version(pose_version_flat[region*POSE_W +: POSE_W]),
        .occurrence_timestamp_out(
          timestamp_flat[region*TIMESTAMP_W +: TIMESTAMP_W]),
        .world_x(world_x_flat[region*RESULT_W +: RESULT_W]),
        .world_y(world_y_flat[region*RESULT_W +: RESULT_W])
      );
    end
  endgenerate
endmodule
