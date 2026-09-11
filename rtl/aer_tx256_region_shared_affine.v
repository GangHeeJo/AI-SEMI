// Four raw 8x8 AER regions arranged as one 16x16 pulse sensor front end.
// Their loss-bearing leaf paths merge into one lossless shared FIFO and one
// central region-coefficient lookup/affine lane.
//
// Parallel arrivals are pulses and therefore cannot be backpressured.  Before
// the first complete coefficient epoch is published, or after pose accounting
// fails, they are masked and reported in arrival_blocked.  Once admission is
// enabled, active_pose_version is sampled by every accepted AER source.
// sensor_admission_enabled is only that admission enable; it is deliberately
// independent of downstream ready/backpressure.
//
// Contract: POSE_W=1, base_sensor_origin_x/y are 8-pixel aligned and static,
// and the complete 16x16 block lies inside the 240x180 sensor raster.
// arrival/polarity bits are front-major, then 4x4-leaf-major, then row-major
// pixel: index = front*64 + leaf*16 + local_y*4 + local_x; both 2x2 levels
// use order (upper bits of y,x) 00,01,10,11.
module aer_tx256_region_shared_affine #(
  parameter integer SENSOR_COLS = 240,
  parameter integer SENSOR_ROWS = 180,
  parameter integer SENSOR_W = 8,
  parameter integer REGION_COLS = 30,
  parameter integer REGION_ROWS = 23,
  parameter integer REGION_X_W = 5,
  parameter integer REGION_Y_W = 5,
  parameter integer REGION_ID_W = 10,
  parameter integer RESULT_W = 16,
  parameter integer MATRIX_W = 16,
  parameter integer OFFSET_W = 24,
  parameter integer FRAC_W = 14,
  parameter integer POSE_W = 1,
  parameter integer TIMESTAMP_W = 35,
  parameter integer REGION_FIFO_DEPTH = 32,
  parameter integer SHARED_FIFO_DEPTH = 8,
  parameter integer GUARD_COUNT_W =
    $clog2(514 + 16*REGION_FIFO_DEPTH + SHARED_FIFO_DEPTH),
  parameter integer X_MIN = 0,
  parameter integer X_MAX = 511,
  parameter integer Y_MIN = 0,
  parameter integer Y_MAX = 255
) (
  input                                  clk,
  input                                  rst,

  input      [255:0]                     arrival,
  input      [255:0]                     polarity_in,
  input      [TIMESTAMP_W-1:0]           occurrence_timestamp,
  input      [SENSOR_W-1:0]              base_sensor_origin_x,
  input      [SENSOR_W-1:0]              base_sensor_origin_y,
  output     [255:0]                     arrival_blocked,
  output                                 sensor_admission_enabled,
  output     [255:0]                     aer_overrun,
  output     [127:0]                     leaf_fifo_overflow,
  output                                 shared_fifo_overflow,

  input                                  cfg_valid,
  output                                 cfg_ready,
  input      [1:0]                       cfg_op,
  input      [REGION_X_W-1:0]            cfg_region_x,
  input      [REGION_Y_W-1:0]            cfg_region_y,
  input      [POSE_W-1:0]                cfg_pose_version,
  input signed [MATRIX_W-1:0]            cfg_m00,
  input signed [MATRIX_W-1:0]            cfg_m01,
  input signed [MATRIX_W-1:0]            cfg_m10,
  input signed [MATRIX_W-1:0]            cfg_m11,
  input signed [OFFSET_W-1:0]            cfg_tx,
  input signed [OFFSET_W-1:0]            cfg_ty,
  output                                 active_pose_valid,
  output     [POSE_W-1:0]                active_pose_version,
  output                                 cfg_busy,
  output                                 cfg_awaiting_publish,
  output                                 cfg_publish_pulse,
  output                                 cfg_protocol_error,

  output                                 world_valid,
  input                                  world_ready,
  output                                 mapped_valid,
  output                                 pose_found,
  output                                 in_range,
  output     [REGION_ID_W-1:0]           region_id_out,
  output     [SENSOR_W-1:0]              sensor_x_out,
  output     [SENSOR_W-1:0]              sensor_y_out,
  output                                 polarity_out,
  output     [POSE_W-1:0]                pose_version_out,
  output     [TIMESTAMP_W-1:0]           occurrence_timestamp_out,
  output signed [RESULT_W-1:0]           world_x_out,
  output signed [RESULT_W-1:0]           world_y_out,

  output     [GUARD_COUNT_W-1:0]         pose_outstanding0,
  output     [GUARD_COUNT_W-1:0]         pose_outstanding1,
  output     [1:0]                       pose_overwrite_ready,
  output                                 pose_accounting_error
);
  localparam integer FRONT_COUNT = 4;
  localparam integer RAW_W = (2*SENSOR_W) + 1 + POSE_W + TIMESTAMP_W;
  localparam integer SX_LSB = 0;
  localparam integer SY_LSB = SX_LSB + SENSOR_W;
  localparam integer POL_LSB = SY_LSB + SENSOR_W;
  localparam integer POSE_LSB = POL_LSB + 1;
  localparam integer TIME_LSB = POSE_LSB + POSE_W;
  localparam integer SHARED_OCC_W = $clog2(SHARED_FIFO_DEPTH + 1);

  assign sensor_admission_enabled =
    !rst && active_pose_valid && !pose_accounting_error;
  assign arrival_blocked = arrival &
    {256{!sensor_admission_enabled}};
  wire [255:0] admitted_arrival = arrival &
    {256{sensor_admission_enabled}};

  wire [FRONT_COUNT-1:0] front_valid;
  wire [FRONT_COUNT-1:0] front_ready;
  wire [(FRONT_COUNT*SENSOR_W)-1:0] front_sensor_x_flat;
  wire [(FRONT_COUNT*SENSOR_W)-1:0] front_sensor_y_flat;
  wire [FRONT_COUNT-1:0] front_polarity;
  wire [(FRONT_COUNT*POSE_W)-1:0] front_pose_flat;
  wire [(FRONT_COUNT*TIMESTAMP_W)-1:0] front_time_flat;
  wire [(FRONT_COUNT*RAW_W)-1:0] front_data_flat;
  wire [(FRONT_COUNT*7)-1:0] front_admitted_count_flat;
  wire [(FRONT_COUNT*6)-1:0] front_drop_count0_flat;
  wire [(FRONT_COUNT*6)-1:0] front_drop_count1_flat;

  genvar front;
  generate
    for (front = 0; front < FRONT_COUNT; front = front + 1) begin: front_path
      localparam integer FRONT_X_OFFSET = (front & 1) * 8;
      localparam integer FRONT_Y_OFFSET = ((front >> 1) & 1) * 8;
      wire [SENSOR_W-1:0] front_origin_x =
        base_sensor_origin_x + FRONT_X_OFFSET;
      wire [SENSOR_W-1:0] front_origin_y =
        base_sensor_origin_y + FRONT_Y_OFFSET;

      aer_region8x8_event_stream #(
        .POSE_W(POSE_W), .SENSOR_W(SENSOR_W),
        .TIMESTAMP_W(TIMESTAMP_W), .FIFO_DEPTH(REGION_FIFO_DEPTH)
      ) u_front (
        .clk(clk), .rst(rst),
        .arrival(admitted_arrival[front*64 +: 64]),
        .polarity_in(polarity_in[front*64 +: 64]),
        .occurrence_pose_version(active_pose_version),
        .occurrence_timestamp(occurrence_timestamp),
        .base_sensor_origin_x(front_origin_x),
        .base_sensor_origin_y(front_origin_y),
        .aer_overrun(aer_overrun[front*64 +: 64]),
        .tile_fifo_overflow(leaf_fifo_overflow[front*32 +: 32]),
        .admitted_count(front_admitted_count_flat[front*7 +: 7]),
        .drop_count0(front_drop_count0_flat[front*6 +: 6]),
        .drop_count1(front_drop_count1_flat[front*6 +: 6]),
        .event_valid(front_valid[front]),
        .event_ready(front_ready[front]),
        .sensor_x(front_sensor_x_flat[front*SENSOR_W +: SENSOR_W]),
        .sensor_y(front_sensor_y_flat[front*SENSOR_W +: SENSOR_W]),
        .polarity(front_polarity[front]),
        .pose_version(front_pose_flat[front*POSE_W +: POSE_W]),
        .occurrence_timestamp_out(
          front_time_flat[front*TIMESTAMP_W +: TIMESTAMP_W])
      );

      assign front_data_flat[front*RAW_W +: RAW_W] = {
        front_time_flat[front*TIMESTAMP_W +: TIMESTAMP_W],
        front_pose_flat[front*POSE_W +: POSE_W],
        front_polarity[front],
        front_sensor_y_flat[front*SENSOR_W +: SENSOR_W],
        front_sensor_x_flat[front*SENSOR_W +: SENSOR_W]
      };
    end
  endgenerate

  wire merge_valid;
  wire [RAW_W-1:0] merge_data;
  wire [1:0] merge_source;
  wire merge_ready;
  rr_stream_arbiter4 #(.DATA_W(RAW_W)) u_region_merge (
    .clk(clk), .rst(rst),
    .in_valid(front_valid), .in_data_flat(front_data_flat),
    .in_ready(front_ready),
    .out_valid(merge_valid), .out_data(merge_data),
    .out_source(merge_source), .out_ready(merge_ready)
  );

  wire shared_fifo_valid;
  wire [RAW_W-1:0] shared_fifo_data;
  wire shared_fifo_ready;
  wire [SHARED_OCC_W-1:0] shared_fifo_occupancy;
  wire [0:0] shared_fifo_in_overflow;
  wire shared_fifo_pop = shared_fifo_valid && shared_fifo_ready;
  wire shared_fifo_can_accept =
    (shared_fifo_occupancy < SHARED_FIFO_DEPTH) || shared_fifo_pop;
  assign merge_ready = !rst && shared_fifo_can_accept;

  // The one-lane batch FIFO has no input-ready port.  Gate in_valid with the
  // actual merge handshake, including a same-edge pop from a full FIFO.  Thus
  // a held merge head is never repeatedly presented as an overflowed event.
  wire [0:0] shared_fifo_in_valid = {merge_valid && merge_ready};
  event_batch_fifo #(
    .DATA_W(RAW_W), .IN_LANES(1), .DEPTH(SHARED_FIFO_DEPTH)
  ) u_shared_fifo (
    .clk(clk), .rst(rst),
    .in_valid(shared_fifo_in_valid), .in_data_flat(merge_data),
    .in_overflow(shared_fifo_in_overflow),
    .out_valid(shared_fifo_valid), .out_data(shared_fifo_data),
    .out_ready(shared_fifo_ready), .occupancy(shared_fifo_occupancy)
  );
  assign shared_fifo_overflow = shared_fifo_in_overflow[0];

  wire [SENSOR_W-1:0] lane_sensor_x =
    shared_fifo_data[SX_LSB +: SENSOR_W];
  wire [SENSOR_W-1:0] lane_sensor_y =
    shared_fifo_data[SY_LSB +: SENSOR_W];
  wire lane_polarity = shared_fifo_data[POL_LSB];
  wire [POSE_W-1:0] lane_pose =
    shared_fifo_data[POSE_LSB +: POSE_W];
  wire [TIMESTAMP_W-1:0] lane_time =
    shared_fifo_data[TIME_LSB +: TIMESTAMP_W];
  wire [REGION_X_W-1:0] lane_region_x = lane_sensor_x >> 3;
  wire [REGION_Y_W-1:0] lane_region_y = lane_sensor_y >> 3;
  wire [REGION_ID_W-1:0] lane_region_id =
    lane_region_y * REGION_COLS + lane_region_x;

  wire region_wr_req;
  wire [REGION_X_W-1:0] region_wr_x;
  wire [REGION_Y_W-1:0] region_wr_y;
  wire [POSE_W-1:0] region_wr_pose_version;
  wire signed [MATRIX_W-1:0] region_wr_m00;
  wire signed [MATRIX_W-1:0] region_wr_m01;
  wire signed [MATRIX_W-1:0] region_wr_m10;
  wire signed [MATRIX_W-1:0] region_wr_m11;
  wire signed [OFFSET_W-1:0] region_wr_tx;
  wire signed [OFFSET_W-1:0] region_wr_ty;
  wire region_wr_ready;
  wire region_wr_commit;
  wire [POSE_W-1:0] loader_load_pose_version;

  wire lookup_valid;
  wire lookup_ready;
  wire [POSE_W-1:0] lookup_pose_version;
  wire [REGION_ID_W-1:0] lookup_region_id;
  wire lookup_rsp_valid;
  wire lookup_rsp_ready;
  wire lookup_rsp_found;
  wire signed [MATRIX_W-1:0] lookup_rsp_m00;
  wire signed [MATRIX_W-1:0] lookup_rsp_m01;
  wire signed [MATRIX_W-1:0] lookup_rsp_m10;
  wire signed [MATRIX_W-1:0] lookup_rsp_m11;
  wire signed [OFFSET_W-1:0] lookup_rsp_tx;
  wire signed [OFFSET_W-1:0] lookup_rsp_ty;
  wire terminal_retire;
  wire [POSE_W-1:0] terminal_retire_pose_version;
  wire [1:0] pose_idle;

  affine_region_pose_loader #(
    .REGION_COLS(REGION_COLS), .REGION_ROWS(REGION_ROWS),
    .REGION_X_W(REGION_X_W), .REGION_Y_W(REGION_Y_W),
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
    .region_wr_pose_version(region_wr_pose_version),
    .region_wr_m00(region_wr_m00), .region_wr_m01(region_wr_m01),
    .region_wr_m10(region_wr_m10), .region_wr_m11(region_wr_m11),
    .region_wr_tx(region_wr_tx), .region_wr_ty(region_wr_ty),
    .region_wr_ready(region_wr_ready),
    .region_wr_commit(region_wr_commit),
    .region_pose_accounting_error(pose_accounting_error),
    .active_pose_valid(active_pose_valid),
    .active_pose_version(active_pose_version),
    .load_busy(cfg_busy), .awaiting_publish(cfg_awaiting_publish),
    .expected_region_x(), .expected_region_y(),
    .load_pose_version(loader_load_pose_version),
    .publish_pulse(cfg_publish_pulse),
    .cfg_protocol_error(cfg_protocol_error)
  );

  affine_region_coeff_table2 #(
    .REGION_COLS(REGION_COLS), .REGION_ROWS(REGION_ROWS),
    .REGION_X_W(REGION_X_W), .REGION_Y_W(REGION_Y_W),
    .REGION_ID_W(REGION_ID_W), .POSE_W(POSE_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W)
  ) u_coeff_table (
    .clk(clk), .rst(rst),
    .region_wr_req(region_wr_req),
    .region_wr_x(region_wr_x), .region_wr_y(region_wr_y),
    .region_wr_pose_version(region_wr_pose_version),
    .region_wr_m00(region_wr_m00), .region_wr_m01(region_wr_m01),
    .region_wr_m10(region_wr_m10), .region_wr_m11(region_wr_m11),
    .region_wr_tx(region_wr_tx), .region_wr_ty(region_wr_ty),
    .region_wr_ready(region_wr_ready),
    .region_wr_commit(region_wr_commit),
    .pose_overwrite_ready(pose_overwrite_ready),
    .publish_pulse(cfg_publish_pulse),
    .publish_pose_version(loader_load_pose_version),
    .lookup_valid(lookup_valid), .lookup_ready(lookup_ready),
    .lookup_pose_version(lookup_pose_version),
    .lookup_region_id(lookup_region_id),
    .lookup_rsp_valid(lookup_rsp_valid),
    .lookup_rsp_ready(lookup_rsp_ready),
    .lookup_rsp_found(lookup_rsp_found),
    .lookup_rsp_m00(lookup_rsp_m00), .lookup_rsp_m01(lookup_rsp_m01),
    .lookup_rsp_m10(lookup_rsp_m10), .lookup_rsp_m11(lookup_rsp_m11),
    .lookup_rsp_tx(lookup_rsp_tx), .lookup_rsp_ty(lookup_rsp_ty)
  );

  wire [8:0] global_admitted_count =
    {2'b00, front_admitted_count_flat[0*7 +: 7]} +
    {2'b00, front_admitted_count_flat[1*7 +: 7]} +
    {2'b00, front_admitted_count_flat[2*7 +: 7]} +
    {2'b00, front_admitted_count_flat[3*7 +: 7]};
  wire [8:0] leaf_drop0_total =
    {3'b000, front_drop_count0_flat[0*6 +: 6]} +
    {3'b000, front_drop_count0_flat[1*6 +: 6]} +
    {3'b000, front_drop_count0_flat[2*6 +: 6]} +
    {3'b000, front_drop_count0_flat[3*6 +: 6]};
  wire [8:0] leaf_drop1_total =
    {3'b000, front_drop_count1_flat[0*6 +: 6]} +
    {3'b000, front_drop_count1_flat[1*6 +: 6]} +
    {3'b000, front_drop_count1_flat[2*6 +: 6]} +
    {3'b000, front_drop_count1_flat[3*6 +: 6]};
  wire [8:0] retire_count0 = leaf_drop0_total +
    ((terminal_retire && !terminal_retire_pose_version[0]) ? 9'd1 : 9'd0);
  wire [8:0] retire_count1 = leaf_drop1_total +
    ((terminal_retire && terminal_retire_pose_version[0]) ? 9'd1 : 9'd0);

  pose_epoch_count_guard2 #(
    .COUNT_W(GUARD_COUNT_W), .DELTA_W(9)
  ) u_guard (
    .clk(clk), .rst(rst),
    .accept_pose_id(active_pose_version[0]),
    .accept_count(global_admitted_count),
    .retire_count0(retire_count0), .retire_count1(retire_count1),
    .outstanding0(pose_outstanding0),
    .outstanding1(pose_outstanding1),
    .idle(pose_idle), .overwrite_ready(pose_overwrite_ready),
    .accounting_error(pose_accounting_error)
  );

  region_affine_shared_lane #(
    .REGION_ID_W(REGION_ID_W), .SENSOR_W(SENSOR_W),
    .RESULT_W(RESULT_W), .MATRIX_W(MATRIX_W),
    .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W),
    .X_MIN(X_MIN), .X_MAX(X_MAX), .Y_MIN(Y_MIN), .Y_MAX(Y_MAX)
  ) u_shared_lane (
    .clk(clk), .rst(rst),
    .event_valid_in(shared_fifo_valid),
    .event_ready_in(shared_fifo_ready),
    .region_id_in(lane_region_id),
    .sensor_x_in(lane_sensor_x), .sensor_y_in(lane_sensor_y),
    .polarity_in(lane_polarity), .pose_version_in(lane_pose),
    .occurrence_timestamp_in(lane_time),
    .lookup_valid(lookup_valid), .lookup_ready(lookup_ready),
    .lookup_pose_version(lookup_pose_version),
    .lookup_region_id(lookup_region_id),
    .lookup_rsp_valid(lookup_rsp_valid),
    .lookup_rsp_ready(lookup_rsp_ready),
    .lookup_rsp_found(lookup_rsp_found),
    .lookup_rsp_m00(lookup_rsp_m00), .lookup_rsp_m01(lookup_rsp_m01),
    .lookup_rsp_m10(lookup_rsp_m10), .lookup_rsp_m11(lookup_rsp_m11),
    .lookup_rsp_tx(lookup_rsp_tx), .lookup_rsp_ty(lookup_rsp_ty),
    .world_valid(world_valid), .world_ready(world_ready),
    .mapped_valid(mapped_valid), .pose_found(pose_found),
    .in_range(in_range), .region_id_out(region_id_out),
    .sensor_x_out(sensor_x_out), .sensor_y_out(sensor_y_out),
    .polarity_out(polarity_out), .pose_version_out(pose_version_out),
    .occurrence_timestamp_out(occurrence_timestamp_out),
    .world_x_out(world_x_out), .world_y_out(world_y_out),
    .terminal_retire(terminal_retire),
    .terminal_retire_pose_version(terminal_retire_pose_version)
  );
endmodule
