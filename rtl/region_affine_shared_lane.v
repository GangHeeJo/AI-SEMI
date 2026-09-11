// One shared lookup/affine lane for region-tagged sensor events.
//
// The lane deliberately holds only one event.  Its pose reference retires
// when the coefficient response and held event enter the affine stage, not
// when the lookup is requested and not when the world output is consumed.
// Missing/unpublished coefficient records still produce one unmapped event.
module region_affine_shared_lane #(
  parameter integer REGION_ID_W = 10,
  parameter integer SENSOR_W = 10,
  parameter integer RESULT_W = 16,
  parameter integer MATRIX_W = 16,
  parameter integer OFFSET_W = 24,
  parameter integer FRAC_W = 14,
  parameter integer POSE_W = 1,
  // At 5 ns units, 35 bits keeps a 59.8 s recording inside the downstream
  // time-surface writer's strict half-range ordering window.
  parameter integer TIMESTAMP_W = 35,
  parameter integer X_MIN = 0,
  parameter integer X_MAX = 511,
  parameter integer Y_MIN = 0,
  parameter integer Y_MAX = 255
) (
  input                                  clk,
  input                                  rst,

  input                                  event_valid_in,
  output                                 event_ready_in,
  input      [REGION_ID_W-1:0]           region_id_in,
  input      [SENSOR_W-1:0]              sensor_x_in,
  input      [SENSOR_W-1:0]              sensor_y_in,
  input                                  polarity_in,
  input      [POSE_W-1:0]                pose_version_in,
  input      [TIMESTAMP_W-1:0]           occurrence_timestamp_in,

  output                                 lookup_valid,
  input                                  lookup_ready,
  output     [POSE_W-1:0]                lookup_pose_version,
  output     [REGION_ID_W-1:0]           lookup_region_id,
  input                                  lookup_rsp_valid,
  output                                 lookup_rsp_ready,
  input                                  lookup_rsp_found,
  input signed [MATRIX_W-1:0]            lookup_rsp_m00,
  input signed [MATRIX_W-1:0]            lookup_rsp_m01,
  input signed [MATRIX_W-1:0]            lookup_rsp_m10,
  input signed [MATRIX_W-1:0]            lookup_rsp_m11,
  input signed [OFFSET_W-1:0]            lookup_rsp_tx,
  input signed [OFFSET_W-1:0]            lookup_rsp_ty,

  output                                 world_valid,
  input                                  world_ready,
  output                                 mapped_valid,
  output                                 pose_found,
  output                                 in_range,
  output reg [REGION_ID_W-1:0]           region_id_out,
  output reg [SENSOR_W-1:0]              sensor_x_out,
  output reg [SENSOR_W-1:0]              sensor_y_out,
  output                                 polarity_out,
  output     [POSE_W-1:0]                pose_version_out,
  output     [TIMESTAMP_W-1:0]           occurrence_timestamp_out,
  output signed [RESULT_W-1:0]           world_x_out,
  output signed [RESULT_W-1:0]           world_y_out,

  output                                 terminal_retire,
  output     [POSE_W-1:0]                terminal_retire_pose_version
);
  reg                                    event_held;
  reg [REGION_ID_W-1:0]                  held_region_id;
  reg [SENSOR_W-1:0]                     held_sensor_x;
  reg [SENSOR_W-1:0]                     held_sensor_y;
  reg                                    held_polarity;
  reg [POSE_W-1:0]                       held_pose_version;
  reg [TIMESTAMP_W-1:0]                  held_timestamp;

  wire affine_upstream_ready;
  wire affine_event_valid = event_held && lookup_rsp_valid;
  wire input_fire = event_valid_in && event_ready_in;

  assign lookup_valid = !rst && !event_held && event_valid_in;
  assign event_ready_in = !rst && !event_held && lookup_ready;
  assign lookup_pose_version = pose_version_in;
  assign lookup_region_id = region_id_in;

  assign lookup_rsp_ready = !rst && event_held && affine_upstream_ready;
  assign terminal_retire = lookup_rsp_valid && lookup_rsp_ready;
  assign terminal_retire_pose_version = held_pose_version;

  always @(posedge clk) begin
    if (rst) begin
      event_held <= 1'b0;
      held_region_id <= {REGION_ID_W{1'b0}};
      held_sensor_x <= {SENSOR_W{1'b0}};
      held_sensor_y <= {SENSOR_W{1'b0}};
      held_polarity <= 1'b0;
      held_pose_version <= {POSE_W{1'b0}};
      held_timestamp <= {TIMESTAMP_W{1'b0}};
    end else begin
      if (input_fire) begin
        event_held <= 1'b1;
        held_region_id <= region_id_in;
        held_sensor_x <= sensor_x_in;
        held_sensor_y <= sensor_y_in;
        held_polarity <= polarity_in;
        held_pose_version <= pose_version_in;
        held_timestamp <= occurrence_timestamp_in;
      end else if (terminal_retire) begin
        event_held <= 1'b0;
      end
    end
  end

  // Mirror metadata that coord_transform_affine2d does not carry.  Updating
  // under the same ready condition keeps it aligned and stable on stalls.
  always @(posedge clk) begin
    if (rst) begin
      region_id_out <= {REGION_ID_W{1'b0}};
      sensor_x_out <= {SENSOR_W{1'b0}};
      sensor_y_out <= {SENSOR_W{1'b0}};
    end else if (affine_upstream_ready && affine_event_valid) begin
      region_id_out <= held_region_id;
      sensor_x_out <= held_sensor_x;
      sensor_y_out <= held_sensor_y;
    end
  end

  coord_transform_affine2d #(
    .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W),
    .X_MIN(X_MIN), .X_MAX(X_MAX), .Y_MIN(Y_MIN), .Y_MAX(Y_MAX)
  ) u_affine (
    .clk(clk), .rst(rst), .downstream_ready(world_ready),
    .event_valid_in(affine_event_valid),
    .pose_found_in(lookup_rsp_found),
    .polarity_in(held_polarity),
    .pose_version_in(held_pose_version),
    .occurrence_timestamp_in(held_timestamp),
    .sensor_x_in(held_sensor_x), .sensor_y_in(held_sensor_y),
    .m00_in(lookup_rsp_m00), .m01_in(lookup_rsp_m01),
    .m10_in(lookup_rsp_m10), .m11_in(lookup_rsp_m11),
    .tx_in(lookup_rsp_tx), .ty_in(lookup_rsp_ty),
    .event_valid_out(world_valid),
    .upstream_ready(affine_upstream_ready),
    .mapped_valid_out(mapped_valid),
    .pose_found_out(pose_found), .in_range_out(in_range),
    .polarity_out(polarity_out),
    .pose_version_out(pose_version_out),
    .occurrence_timestamp_out(occurrence_timestamp_out),
    .world_x_out(world_x_out), .world_y_out(world_y_out)
  );
endmodule
