// Region-affine world mapping for an already serialized DAVIS-like stream.
//
// The upstream source must attach the pose epoch that was current at the
// event's occurrence timestamp.  active_pose_version is exposed only so that
// upstream can synchronize tags; it is not substituted for that input tag.
// Events are backpressured until the first complete coefficient epoch is
// published.  Before reusing an epoch slot, upstream must also have stopped
// presenting older events for that slot: the local guard can count accepted
// events, but cannot see a pose-tagged backlog still outside this interface.
// Coordinates outside SENSOR_COLS x SENSOR_ROWS use an invalid table sentinel
// and emerge once as deterministic unmapped diagnostics.
module serialized_sensor_region_affine2d #(
  parameter integer SENSOR_COLS = 240,
  parameter integer SENSOR_ROWS = 180,
  parameter integer SENSOR_W = 8,
  parameter integer REGION_COLS = 30,
  parameter integer REGION_ROWS = 23,
  parameter integer REGION_X_W = 5,
  parameter integer REGION_Y_W = 5,
  parameter integer REGION_ID_W =
    (REGION_COLS*REGION_ROWS+1 < 2) ? 1 :
    $clog2(REGION_COLS*REGION_ROWS+1),
  parameter integer RESULT_W = 16,
  parameter integer MATRIX_W = 16,
  parameter integer OFFSET_W = 24,
  parameter integer FRAC_W = 14,
  // Contract: POSE_W must remain 1; table and guard have two fixed slots.
  parameter integer POSE_W = 1,
  // 35 bits cover the 59.8 s UZH trace at 200 MHz while preserving the
  // half-range ordering contract used by the downstream time surface.
  parameter integer TIMESTAMP_W = 35,
  parameter integer GUARD_COUNT_W = 2,
  parameter integer X_MIN = 0,
  parameter integer X_MAX = 511,
  parameter integer Y_MIN = 0,
  parameter integer Y_MAX = 255
) (
  input                                  clk,
  input                                  rst,

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

  input                                  event_valid_in,
  output                                 event_ready_in,
  input      [SENSOR_W-1:0]              sensor_x_in,
  input      [SENSOR_W-1:0]              sensor_y_in,
  input                                  polarity_in,
  input      [POSE_W-1:0]                occurrence_pose_version_in,
  input      [TIMESTAMP_W-1:0]           occurrence_timestamp_in,

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
  localparam integer REGION_COUNT = REGION_COLS * REGION_ROWS;
  localparam [REGION_ID_W-1:0] INVALID_REGION_ID = REGION_COUNT;

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

  wire lane_event_ready;
  wire event_admission_enabled =
    !rst && active_pose_valid && !pose_accounting_error;
  wire lane_event_valid = event_valid_in && event_admission_enabled;
  wire event_fire = event_valid_in && event_ready_in;
  wire terminal_retire;
  wire [POSE_W-1:0] terminal_retire_pose_version;
  wire [1:0] pose_idle;

  wire coordinate_valid =
    (sensor_x_in < SENSOR_COLS) && (sensor_y_in < SENSOR_ROWS);
  wire [REGION_X_W-1:0] event_region_x = sensor_x_in >> 3;
  wire [REGION_Y_W-1:0] event_region_y = sensor_y_in >> 3;
  wire [REGION_ID_W-1:0] valid_region_id =
    event_region_y * REGION_COLS + event_region_x;
  wire [REGION_ID_W-1:0] event_region_id =
    coordinate_valid ? valid_region_id : INVALID_REGION_ID;

  assign event_ready_in = event_admission_enabled && lane_event_ready;

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
    .expected_region_x(), .expected_region_y(), .load_pose_version(),
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
    .publish_pose_version(active_pose_version),
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

  pose_epoch_count_guard2 #(
    .COUNT_W(GUARD_COUNT_W), .DELTA_W(1)
  ) u_guard (
    .clk(clk), .rst(rst),
    .accept_pose_id(occurrence_pose_version_in),
    .accept_count(event_fire),
    .retire_count0(terminal_retire &&
                   !terminal_retire_pose_version),
    .retire_count1(terminal_retire &&
                   terminal_retire_pose_version),
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
    .event_valid_in(lane_event_valid),
    .event_ready_in(lane_event_ready),
    .region_id_in(event_region_id),
    .sensor_x_in(sensor_x_in), .sensor_y_in(sensor_y_in),
    .polarity_in(polarity_in),
    .pose_version_in(occurrence_pose_version_in),
    .occurrence_timestamp_in(occurrence_timestamp_in),
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
