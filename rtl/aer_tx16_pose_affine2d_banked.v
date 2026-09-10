// Configurable banked Stage-2 endpoint for one 4x4 pose/timestamp AER leaf.
//
// Adapter lane L is assigned statically to bank (L mod K).  Each bank owns
// one event_batch_fifo, one pose-table read port, and one affine transform.
// Supported configurations use K=1/2/4/8 and a power-of-two FIFO_DEPTH.
// Each bank preserves its own event order; no total order is promised across
// independently backpressured output lanes.  Occurrence timestamps remain the
// ordering authority for downstream map updates.
// tile_origin_x/y are static physical configuration and must remain constant
// while rst is deasserted.
module aer_tx16_pose_affine2d_banked #(
  parameter integer K = 2,
  parameter integer FIFO_DEPTH = 32,
  parameter integer POSE_W = 4,
  parameter integer SENSOR_W = 10,
  parameter integer RESULT_W = 16,
  parameter integer MATRIX_W = 16,
  parameter integer OFFSET_W = 24,
  parameter integer FRAC_W = 14,
  parameter integer TIMESTAMP_W = 32,
  parameter integer GUARD_COUNT_W = $clog2(33 + K*FIFO_DEPTH),
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

  output     [K-1:0]                 world_valid,
  input      [K-1:0]                 world_ready,
  output     [K-1:0]                 mapped_valid,
  output     [K-1:0]                 pose_found,
  output     [K-1:0]                 in_range,
  output     [K*SENSOR_W-1:0]        sensor_x_out_flat,
  output     [K*SENSOR_W-1:0]        sensor_y_out_flat,
  output     [K-1:0]                 polarity_out,
  output     [K*POSE_W-1:0]          pose_version_out_flat,
  output     [K*TIMESTAMP_W-1:0]     occurrence_timestamp_out_flat,
  output     [K*RESULT_W-1:0]        world_x_out_flat,
  output     [K*RESULT_W-1:0]        world_y_out_flat
);
  localparam integer ADAPTER_LANES = 8;
  localparam integer LANES_PER_BANK = ADAPTER_LANES / K;
  localparam integer EVENT_W = (2*SENSOR_W) + 1 + POSE_W + TIMESTAMP_W;
  localparam integer OCC_W = $clog2(FIFO_DEPTH + 1);
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

  wire [ADAPTER_LANES-1:0] batch_valid;
  wire [ADAPTER_LANES*SENSOR_W-1:0] batch_x_flat;
  wire [ADAPTER_LANES*SENSOR_W-1:0] batch_y_flat;
  wire [ADAPTER_LANES-1:0] batch_polarity;
  wire [ADAPTER_LANES*POSE_W-1:0] batch_pose_flat;
  wire [ADAPTER_LANES*TIMESTAMP_W-1:0] batch_time_flat;

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

  wire [K-1:0] fifo_out_valid;
  wire [K*EVENT_W-1:0] fifo_out_data_flat;
  wire [K-1:0] fifo_out_ready;
  wire [K*OCC_W-1:0] fifo_occupancy_flat;
  wire [K*SENSOR_W-1:0] fifo_sensor_x_flat;
  wire [K*SENSOR_W-1:0] fifo_sensor_y_flat;
  wire [K-1:0] fifo_polarity;
  wire [K*POSE_W-1:0] fifo_pose_flat;
  wire [K*TIMESTAMP_W-1:0] fifo_time_flat;

  genvar bank;
  genvar slot;
  generate
    for (bank = 0; bank < K; bank = bank + 1) begin: bank_fifo
      wire [LANES_PER_BANK-1:0] bank_in_valid;
      wire [LANES_PER_BANK*EVENT_W-1:0] bank_in_data_flat;
      wire [LANES_PER_BANK-1:0] bank_overflow;

      for (slot = 0; slot < LANES_PER_BANK; slot = slot + 1) begin: bank_input
        localparam integer ADAPTER_LANE = slot*K + bank;
        assign bank_in_valid[slot] = batch_valid[ADAPTER_LANE];
        assign bank_in_data_flat[slot*EVENT_W +: EVENT_W] = {
          batch_time_flat[ADAPTER_LANE*TIMESTAMP_W +: TIMESTAMP_W],
          batch_pose_flat[ADAPTER_LANE*POSE_W +: POSE_W],
          batch_polarity[ADAPTER_LANE],
          batch_y_flat[ADAPTER_LANE*SENSOR_W +: SENSOR_W],
          batch_x_flat[ADAPTER_LANE*SENSOR_W +: SENSOR_W]
        };
        assign fifo_overflow[ADAPTER_LANE] = bank_overflow[slot];
      end

      event_batch_fifo #(
        .DATA_W(EVENT_W), .IN_LANES(LANES_PER_BANK), .DEPTH(FIFO_DEPTH)
      ) u_fifo (
        .clk(clk), .rst(rst),
        .in_valid(bank_in_valid), .in_data_flat(bank_in_data_flat),
        .in_overflow(bank_overflow),
        .out_valid(fifo_out_valid[bank]),
        .out_data(fifo_out_data_flat[bank*EVENT_W +: EVENT_W]),
        .out_ready(fifo_out_ready[bank]),
        .occupancy(fifo_occupancy_flat[bank*OCC_W +: OCC_W])
      );

      assign fifo_sensor_x_flat[bank*SENSOR_W +: SENSOR_W] =
        fifo_out_data_flat[bank*EVENT_W + SX_LSB +: SENSOR_W];
      assign fifo_sensor_y_flat[bank*SENSOR_W +: SENSOR_W] =
        fifo_out_data_flat[bank*EVENT_W + SY_LSB +: SENSOR_W];
      assign fifo_polarity[bank] =
        fifo_out_data_flat[bank*EVENT_W + POL_LSB];
      assign fifo_pose_flat[bank*POSE_W +: POSE_W] =
        fifo_out_data_flat[bank*EVENT_W + POSE_LSB +: POSE_W];
      assign fifo_time_flat[bank*TIMESTAMP_W +: TIMESTAMP_W] =
        fifo_out_data_flat[bank*EVENT_W + TIME_LSB +: TIMESTAMP_W];
    end
  endgenerate

  wire [K-1:0] transform_capture = fifo_out_valid & fifo_out_ready;
  wire [(ADAPTER_LANES+K)-1:0] retire_valid;
  wire [(ADAPTER_LANES+K)*POSE_W-1:0] retire_pose_flat;
  assign retire_valid[ADAPTER_LANES-1:0] = fifo_overflow;
  assign retire_valid[ADAPTER_LANES +: K] = transform_capture;

  genvar retire_lane;
  generate
    for (retire_lane = 0; retire_lane < ADAPTER_LANES;
         retire_lane = retire_lane + 1) begin: drop_retire_pose
      assign retire_pose_flat[retire_lane*POSE_W +: POSE_W] =
        batch_pose_flat[retire_lane*POSE_W +: POSE_W];
    end
  endgenerate
  assign retire_pose_flat[ADAPTER_LANES*POSE_W +: K*POSE_W] = fifo_pose_flat;

  pose_inflight_guard8 #(
    .POSE_W(POSE_W), .COUNT_W(GUARD_COUNT_W),
    .ACCEPT_SOURCES(16), .RETIRE_LANES(ADAPTER_LANES + K)
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

  wire [K-1:0] lookup_found;
  wire [K*MATRIX_W-1:0] lookup_m00_flat;
  wire [K*MATRIX_W-1:0] lookup_m01_flat;
  wire [K*MATRIX_W-1:0] lookup_m10_flat;
  wire [K*MATRIX_W-1:0] lookup_m11_flat;
  wire [K*OFFSET_W-1:0] lookup_tx_flat;
  wire [K*OFFSET_W-1:0] lookup_ty_flat;

  pose_history_affine8 #(
    .POSE_W(POSE_W), .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .LANES(K)
  ) u_pose_history (
    .clk(clk), .rst(rst),
    .pose_wr_en(pose_wr_commit), .pose_wr_id(pose_wr_id),
    .pose_wr_m00(pose_wr_m00), .pose_wr_m01(pose_wr_m01),
    .pose_wr_m10(pose_wr_m10), .pose_wr_m11(pose_wr_m11),
    .pose_wr_tx(pose_wr_tx), .pose_wr_ty(pose_wr_ty),
    .pose_rd_id_flat(fifo_pose_flat), .pose_rd_found(lookup_found),
    .pose_rd_m00_flat(lookup_m00_flat),
    .pose_rd_m01_flat(lookup_m01_flat),
    .pose_rd_m10_flat(lookup_m10_flat),
    .pose_rd_m11_flat(lookup_m11_flat),
    .pose_rd_tx_flat(lookup_tx_flat), .pose_rd_ty_flat(lookup_ty_flat)
  );

  genvar transform_lane;
  generate
    for (transform_lane = 0; transform_lane < K;
         transform_lane = transform_lane + 1) begin: bank_transform
      reg [SENSOR_W-1:0] sensor_x_hold;
      reg [SENSOR_W-1:0] sensor_y_hold;
      wire signed [RESULT_W-1:0] world_x_lane;
      wire signed [RESULT_W-1:0] world_y_lane;

      coord_transform_affine2d #(
        .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
        .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
        .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W),
        .X_MIN(X_MIN), .X_MAX(X_MAX), .Y_MIN(Y_MIN), .Y_MAX(Y_MAX)
      ) u_transform (
        .clk(clk), .rst(rst),
        .downstream_ready(world_ready[transform_lane]),
        .event_valid_in(fifo_out_valid[transform_lane]),
        .pose_found_in(lookup_found[transform_lane]),
        .polarity_in(fifo_polarity[transform_lane]),
        .pose_version_in(
          fifo_pose_flat[transform_lane*POSE_W +: POSE_W]),
        .occurrence_timestamp_in(
          fifo_time_flat[transform_lane*TIMESTAMP_W +: TIMESTAMP_W]),
        .sensor_x_in(
          fifo_sensor_x_flat[transform_lane*SENSOR_W +: SENSOR_W]),
        .sensor_y_in(
          fifo_sensor_y_flat[transform_lane*SENSOR_W +: SENSOR_W]),
        .m00_in(lookup_m00_flat[transform_lane*MATRIX_W +: MATRIX_W]),
        .m01_in(lookup_m01_flat[transform_lane*MATRIX_W +: MATRIX_W]),
        .m10_in(lookup_m10_flat[transform_lane*MATRIX_W +: MATRIX_W]),
        .m11_in(lookup_m11_flat[transform_lane*MATRIX_W +: MATRIX_W]),
        .tx_in(lookup_tx_flat[transform_lane*OFFSET_W +: OFFSET_W]),
        .ty_in(lookup_ty_flat[transform_lane*OFFSET_W +: OFFSET_W]),
        .event_valid_out(world_valid[transform_lane]),
        .upstream_ready(fifo_out_ready[transform_lane]),
        .mapped_valid_out(mapped_valid[transform_lane]),
        .pose_found_out(pose_found[transform_lane]),
        .in_range_out(in_range[transform_lane]),
        .polarity_out(polarity_out[transform_lane]),
        .pose_version_out(
          pose_version_out_flat[transform_lane*POSE_W +: POSE_W]),
        .occurrence_timestamp_out(
          occurrence_timestamp_out_flat[
            transform_lane*TIMESTAMP_W +: TIMESTAMP_W]),
        .world_x_out(world_x_lane), .world_y_out(world_y_lane)
      );

      assign sensor_x_out_flat[transform_lane*SENSOR_W +: SENSOR_W] =
        sensor_x_hold;
      assign sensor_y_out_flat[transform_lane*SENSOR_W +: SENSOR_W] =
        sensor_y_hold;
      assign world_x_out_flat[transform_lane*RESULT_W +: RESULT_W] =
        world_x_lane;
      assign world_y_out_flat[transform_lane*RESULT_W +: RESULT_W] =
        world_y_lane;

      always @(posedge clk) begin
        if (rst) begin
          sensor_x_hold <= {SENSOR_W{1'b0}};
          sensor_y_hold <= {SENSOR_W{1'b0}};
        end else if (fifo_out_ready[transform_lane]) begin
          if (fifo_out_valid[transform_lane]) begin
            sensor_x_hold <=
              fifo_sensor_x_flat[transform_lane*SENSOR_W +: SENSOR_W];
            sensor_y_hold <=
              fifo_sensor_y_flat[transform_lane*SENSOR_W +: SENSOR_W];
          end else begin
            sensor_x_hold <= {SENSOR_W{1'b0}};
            sensor_y_hold <= {SENSOR_W{1'b0}};
          end
        end
      end
    end
  endgenerate
endmodule
