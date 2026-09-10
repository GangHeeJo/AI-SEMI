// One-stage, fixed-point 2-D affine transform.
//
// Coefficients use signed Q(COEFF_W-FRAC_W).FRAC_W values:
//   world_x = round(m00*sensor_x + m01*sensor_y + tx)
//   world_y = round(m10*sensor_x + m11*sensor_y + ty)
//
// Rounding is nearest, with exact half values rounded away from zero.  An
// event is preserved even when its pose is missing or its coordinate is out
// of range: event_valid_out still pulses, while mapped_valid_out is low.
module coord_transform_affine2d #(
  parameter SENSOR_W = 10,
  parameter RESULT_W = 16,
  parameter MATRIX_W = 16,
  parameter OFFSET_W = 24,
  parameter FRAC_W   = 14,
  parameter POSE_W   = 4,
  parameter TIMESTAMP_W = 32,
  parameter integer X_MIN = 0,
  parameter integer X_MAX = 255,
  parameter integer Y_MIN = 0,
  parameter integer Y_MAX = 255
)(
  input                         clk,
  input                         rst,
  input                         downstream_ready,
  input                         event_valid_in,
  input                         pose_found_in,
  input                         polarity_in,
  input      [POSE_W-1:0]       pose_version_in,
  input      [TIMESTAMP_W-1:0]  occurrence_timestamp_in,
  input      [SENSOR_W-1:0]     sensor_x_in,
  input      [SENSOR_W-1:0]     sensor_y_in,
  input signed [MATRIX_W-1:0]   m00_in,
  input signed [MATRIX_W-1:0]   m01_in,
  input signed [MATRIX_W-1:0]   m10_in,
  input signed [MATRIX_W-1:0]   m11_in,
  input signed [OFFSET_W-1:0]   tx_in,
  input signed [OFFSET_W-1:0]   ty_in,
  output reg                    event_valid_out,
  output wire                   upstream_ready,
  output wire                   mapped_valid_out,
  output reg                    pose_found_out,
  output reg                    in_range_out,
  output reg                    polarity_out,
  output reg [POSE_W-1:0]       pose_version_out,
  output reg [TIMESTAMP_W-1:0]  occurrence_timestamp_out,
  output reg signed [RESULT_W-1:0] world_x_out,
  output reg signed [RESULT_W-1:0] world_y_out
);
  localparam XY_SIGN_W = SENSOR_W + 1;
  localparam PROD_W    = MATRIX_W + XY_SIGN_W;
  localparam BASE_W    = (PROD_W > OFFSET_W) ? PROD_W : OFFSET_W;
  localparam ACC_W     = BASE_W + 3;

  wire signed [XY_SIGN_W-1:0] sensor_x_s = $signed({1'b0, sensor_x_in});
  wire signed [XY_SIGN_W-1:0] sensor_y_s = $signed({1'b0, sensor_y_in});

  wire signed [PROD_W-1:0] prod_xx = m00_in * sensor_x_s;
  wire signed [PROD_W-1:0] prod_xy = m01_in * sensor_y_s;
  wire signed [PROD_W-1:0] prod_yx = m10_in * sensor_x_s;
  wire signed [PROD_W-1:0] prod_yy = m11_in * sensor_y_s;

  wire signed [ACC_W-1:0] prod_xx_e = {{(ACC_W-PROD_W){prod_xx[PROD_W-1]}}, prod_xx};
  wire signed [ACC_W-1:0] prod_xy_e = {{(ACC_W-PROD_W){prod_xy[PROD_W-1]}}, prod_xy};
  wire signed [ACC_W-1:0] prod_yx_e = {{(ACC_W-PROD_W){prod_yx[PROD_W-1]}}, prod_yx};
  wire signed [ACC_W-1:0] prod_yy_e = {{(ACC_W-PROD_W){prod_yy[PROD_W-1]}}, prod_yy};
  wire signed [ACC_W-1:0] tx_e = {{(ACC_W-OFFSET_W){tx_in[OFFSET_W-1]}}, tx_in};
  wire signed [ACC_W-1:0] ty_e = {{(ACC_W-OFFSET_W){ty_in[OFFSET_W-1]}}, ty_in};

  wire signed [ACC_W-1:0] acc_x = prod_xx_e + prod_xy_e + tx_e;
  wire signed [ACC_W-1:0] acc_y = prod_yx_e + prod_yy_e + ty_e;

  wire signed [ACC_W:0] acc_x_w = {acc_x[ACC_W-1], acc_x};
  wire signed [ACC_W:0] acc_y_w = {acc_y[ACC_W-1], acc_y};
  wire signed [ACC_W:0] mag_x = acc_x_w[ACC_W] ? -acc_x_w : acc_x_w;
  wire signed [ACC_W:0] mag_y = acc_y_w[ACC_W] ? -acc_y_w : acc_y_w;
  wire signed [ACC_W:0] half_lsb = ({{ACC_W{1'b0}}, 1'b1} << (FRAC_W-1));
  wire signed [ACC_W:0] rounded_mag_x = (mag_x + half_lsb) >>> FRAC_W;
  wire signed [ACC_W:0] rounded_mag_y = (mag_y + half_lsb) >>> FRAC_W;
  wire signed [ACC_W:0] rounded_x = acc_x_w[ACC_W] ? -rounded_mag_x : rounded_mag_x;
  wire signed [ACC_W:0] rounded_y = acc_y_w[ACC_W] ? -rounded_mag_y : rounded_mag_y;

  wire signed [ACC_W:0] x_min_s = X_MIN;
  wire signed [ACC_W:0] x_max_s = X_MAX;
  wire signed [ACC_W:0] y_min_s = Y_MIN;
  wire signed [ACC_W:0] y_max_s = Y_MAX;
  wire x_in_range = (rounded_x >= x_min_s) && (rounded_x <= x_max_s);
  wire y_in_range = (rounded_y >= y_min_s) && (rounded_y <= y_max_s);

  assign mapped_valid_out = event_valid_out & pose_found_out & in_range_out;
  assign upstream_ready = ~event_valid_out | downstream_ready;

  always @(posedge clk) begin
    if (rst) begin
      event_valid_out  <= 1'b0;
      pose_found_out   <= 1'b0;
      in_range_out     <= 1'b0;
      polarity_out     <= 1'b0;
      pose_version_out <= {POSE_W{1'b0}};
      occurrence_timestamp_out <= {TIMESTAMP_W{1'b0}};
      world_x_out      <= {RESULT_W{1'b0}};
      world_y_out      <= {RESULT_W{1'b0}};
    end else if (upstream_ready) begin
      event_valid_out  <= event_valid_in;
      pose_found_out   <= event_valid_in & pose_found_in;
      in_range_out     <= event_valid_in & pose_found_in & x_in_range & y_in_range;
      polarity_out     <= polarity_in;
      pose_version_out <= pose_version_in;
      occurrence_timestamp_out <= event_valid_in
                                ? occurrence_timestamp_in
                                : {TIMESTAMP_W{1'b0}};
      // Preserve rounded coordinates for diagnostics even when they lie
      // outside the selected map window.  Unknown poses remain deterministic.
      world_x_out      <= pose_found_in
                        ? rounded_x[RESULT_W-1:0] : {RESULT_W{1'b0}};
      world_y_out      <= pose_found_in
                        ? rounded_y[RESULT_W-1:0] : {RESULT_W{1'b0}};
    end
  end
endmodule
