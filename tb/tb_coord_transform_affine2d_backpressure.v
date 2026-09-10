`timescale 1ns/1ps

module tb_coord_transform_affine2d_backpressure;
  localparam POSE_W = 4;
  localparam TIMESTAMP_W = 16;

  reg clk = 1'b0;
  reg rst;
  reg downstream_ready;
  reg event_valid_in;
  reg pose_found_in;
  reg polarity_in;
  reg [POSE_W-1:0] pose_version_in;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp_in;
  reg [3:0] sensor_x_in, sensor_y_in;
  reg signed [15:0] m00_in, m01_in, m10_in, m11_in;
  reg signed [23:0] tx_in, ty_in;

  wire upstream_ready;
  wire event_valid_out, mapped_valid_out, pose_found_out, in_range_out;
  wire polarity_out;
  wire [POSE_W-1:0] pose_version_out;
  wire [TIMESTAMP_W-1:0] occurrence_timestamp_out;
  wire signed [15:0] world_x_out, world_y_out;

  integer errors;
  integer stall_cycle;

  coord_transform_affine2d #(
    .SENSOR_W(4), .RESULT_W(16), .MATRIX_W(16), .OFFSET_W(24),
    .FRAC_W(14), .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W),
    .X_MIN(0), .X_MAX(31), .Y_MIN(0), .Y_MAX(31)
  ) dut (
    .clk(clk), .rst(rst), .downstream_ready(downstream_ready),
    .event_valid_in(event_valid_in), .upstream_ready(upstream_ready),
    .pose_found_in(pose_found_in), .polarity_in(polarity_in),
    .pose_version_in(pose_version_in),
    .occurrence_timestamp_in(occurrence_timestamp_in),
    .sensor_x_in(sensor_x_in), .sensor_y_in(sensor_y_in),
    .m00_in(m00_in), .m01_in(m01_in), .m10_in(m10_in), .m11_in(m11_in),
    .tx_in(tx_in), .ty_in(ty_in),
    .event_valid_out(event_valid_out), .mapped_valid_out(mapped_valid_out),
    .pose_found_out(pose_found_out), .in_range_out(in_range_out),
    .polarity_out(polarity_out), .pose_version_out(pose_version_out),
    .occurrence_timestamp_out(occurrence_timestamp_out),
    .world_x_out(world_x_out), .world_y_out(world_y_out)
  );

  always #5 clk = ~clk;

  task check_a;
    begin
      if (event_valid_out !== 1'b1 || mapped_valid_out !== 1'b1 ||
          pose_found_out !== 1'b1 || in_range_out !== 1'b1 ||
          polarity_out !== 1'b1 || pose_version_out !== 4'h3 ||
          occurrence_timestamp_out !== 16'h1234 ||
          $signed(world_x_out) !== 7 || $signed(world_y_out) !== 11) begin
        errors = errors + 1;
        $display("EVENT_A_MISMATCH valid=%b mapped=%b pose=%h time=%h xy=(%0d,%0d)",
          event_valid_out, mapped_valid_out, pose_version_out,
          occurrence_timestamp_out, $signed(world_x_out), $signed(world_y_out));
      end
    end
  endtask

  initial begin
    errors = 0;
    rst = 1'b1;
    downstream_ready = 1'b0;
    event_valid_in = 1'b0;
    pose_found_in = 1'b0;
    polarity_in = 1'b0;
    pose_version_in = 0;
    occurrence_timestamp_in = 0;
    sensor_x_in = 0;
    sensor_y_in = 0;
    // Identity Q2.14.
    m00_in = 16'sd16384;
    m01_in = 0;
    m10_in = 0;
    m11_in = 16'sd16384;
    tx_in = 0;
    ty_in = 0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    // Empty output must accept A even while the consumer is stalled.
    event_valid_in = 1'b1;
    pose_found_in = 1'b1;
    polarity_in = 1'b1;
    pose_version_in = 4'h3;
    occurrence_timestamp_in = 16'h1234;
    sensor_x_in = 4'd7;
    sensor_y_in = 4'd11;
    if (upstream_ready !== 1'b1) begin
      errors = errors + 1;
      $display("EMPTY_NOT_READY");
    end
    @(posedge clk); #1;
    check_a();

    // Present B, but hold the output. A and ready state must remain stable.
    sensor_x_in = 4'd2;
    sensor_y_in = 4'd4;
    polarity_in = 1'b0;
    pose_version_in = 4'h9;
    occurrence_timestamp_in = 16'hbeef;
    tx_in = 24'sd16384;
    ty_in = -24'sd16384;
    for (stall_cycle = 0; stall_cycle < 5; stall_cycle = stall_cycle + 1) begin
      @(negedge clk);
      if (upstream_ready !== 1'b0) begin
        errors = errors + 1;
        $display("STALL_READY_HIGH cycle=%0d", stall_cycle);
      end
      @(posedge clk); #1;
      check_a();
    end

    // Consume A and replace it with B in the same edge.
    @(negedge clk);
    downstream_ready = 1'b1;
    #1;
    if (upstream_ready !== 1'b1) begin
      errors = errors + 1;
      $display("REPLACE_NOT_READY");
    end
    @(posedge clk); #1;
    if (event_valid_out !== 1'b1 || mapped_valid_out !== 1'b1 ||
        polarity_out !== 1'b0 || pose_version_out !== 4'h9 ||
        occurrence_timestamp_out !== 16'hbeef ||
        $signed(world_x_out) !== 3 || $signed(world_y_out) !== 3) begin
      errors = errors + 1;
      $display("EVENT_B_MISMATCH pose=%h time=%h xy=(%0d,%0d)",
        pose_version_out, occurrence_timestamp_out,
        $signed(world_x_out), $signed(world_y_out));
    end

    // Drain B and verify an invalid input clears the valid bit.
    @(negedge clk);
    event_valid_in = 1'b0;
    @(posedge clk); #1;
    if (event_valid_out !== 1'b0 || mapped_valid_out !== 1'b0) begin
      errors = errors + 1;
      $display("DRAIN_VALID_STUCK");
    end

    $display("COORD_TRANSFORM_BACKPRESSURE_ERRORS=%0d", errors);
    if (errors == 0)
      $display("COORD_TRANSFORM_AFFINE2D_BACKPRESSURE_PASS");
    else
      $fatal(1, "COORD_TRANSFORM_AFFINE2D_BACKPRESSURE_FAIL");
    $finish;
  end
endmodule
