// Expand the two row-bitmap AER packets into at most eight independent events.
// Slots 0..3 correspond to lane0 columns 0..3; slots 4..7 to lane1.
module aer_bitmap_to_event8_pose #(
  parameter POSE_W   = 8,
  parameter TIMESTAMP_W = 32,
  parameter SENSOR_W = 10
)(
  input                         valid0,
  input      [1:0]              row0,
  input      [3:0]              col_mask0,
  input      [3:0]              pol_mask0,
  input      [(4*POSE_W)-1:0]   pose_tags0,
  input      [(4*TIMESTAMP_W)-1:0] time_tags0,
  input                         valid1,
  input      [1:0]              row1,
  input      [3:0]              col_mask1,
  input      [3:0]              pol_mask1,
  input      [(4*POSE_W)-1:0]   pose_tags1,
  input      [(4*TIMESTAMP_W)-1:0] time_tags1,
  input      [SENSOR_W-1:0]     tile_origin_x,
  input      [SENSOR_W-1:0]     tile_origin_y,
  output     [7:0]              event_valid,
  output     [8*SENSOR_W-1:0]   sensor_x_flat,
  output     [8*SENSOR_W-1:0]   sensor_y_flat,
  output     [7:0]              polarity,
  output     [8*POSE_W-1:0]     pose_version_flat,
  output     [8*TIMESTAMP_W-1:0] occurrence_timestamp_flat
);
  genvar c;
  generate
    for (c = 0; c < 4; c = c + 1) begin: lane0_event
      wire active = valid0 & col_mask0[c];
      assign event_valid[c] = active;
      assign sensor_x_flat[c*SENSOR_W +: SENSOR_W] = active
        ? tile_origin_x + c : {SENSOR_W{1'b0}};
      assign sensor_y_flat[c*SENSOR_W +: SENSOR_W] = active
        ? tile_origin_y + row0 : {SENSOR_W{1'b0}};
      assign polarity[c] = active ? pol_mask0[c] : 1'b0;
      assign pose_version_flat[c*POSE_W +: POSE_W] = active
        ? pose_tags0[c*POSE_W +: POSE_W] : {POSE_W{1'b0}};
      assign occurrence_timestamp_flat[c*TIMESTAMP_W +: TIMESTAMP_W] = active
        ? time_tags0[c*TIMESTAMP_W +: TIMESTAMP_W] : {TIMESTAMP_W{1'b0}};
    end
    for (c = 0; c < 4; c = c + 1) begin: lane1_event
      wire active = valid1 & col_mask1[c];
      assign event_valid[c+4] = active;
      assign sensor_x_flat[(c+4)*SENSOR_W +: SENSOR_W] = active
        ? tile_origin_x + c : {SENSOR_W{1'b0}};
      assign sensor_y_flat[(c+4)*SENSOR_W +: SENSOR_W] = active
        ? tile_origin_y + row1 : {SENSOR_W{1'b0}};
      assign polarity[c+4] = active ? pol_mask1[c] : 1'b0;
      assign pose_version_flat[(c+4)*POSE_W +: POSE_W] = active
        ? pose_tags1[c*POSE_W +: POSE_W] : {POSE_W{1'b0}};
      assign occurrence_timestamp_flat[(c+4)*TIMESTAMP_W +: TIMESTAMP_W] = active
        ? time_tags1[c*TIMESTAMP_W +: TIMESTAMP_W] : {TIMESTAMP_W{1'b0}};
    end
  endgenerate
endmodule
