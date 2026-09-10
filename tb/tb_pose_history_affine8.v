`timescale 1ns/1ps
module tb_pose_history_affine8;
  localparam POSE_W = 4;
  localparam MATRIX_W = 16;
  localparam OFFSET_W = 24;
  localparam LANES = 8;

  reg clk = 0;
  reg rst;
  reg pose_wr_en;
  reg [POSE_W-1:0] pose_wr_id;
  reg signed [MATRIX_W-1:0] pose_wr_m00;
  reg signed [MATRIX_W-1:0] pose_wr_m01;
  reg signed [MATRIX_W-1:0] pose_wr_m10;
  reg signed [MATRIX_W-1:0] pose_wr_m11;
  reg signed [OFFSET_W-1:0] pose_wr_tx;
  reg signed [OFFSET_W-1:0] pose_wr_ty;
  reg [LANES*POSE_W-1:0] pose_rd_id_flat;
  wire [LANES-1:0] pose_rd_found;
  wire [LANES*MATRIX_W-1:0] pose_rd_m00_flat;
  wire [LANES*MATRIX_W-1:0] pose_rd_m01_flat;
  wire [LANES*MATRIX_W-1:0] pose_rd_m10_flat;
  wire [LANES*MATRIX_W-1:0] pose_rd_m11_flat;
  wire [LANES*OFFSET_W-1:0] pose_rd_tx_flat;
  wire [LANES*OFFSET_W-1:0] pose_rd_ty_flat;

  integer errors;
  integer lane;

  pose_history_affine8 #(
    .POSE_W(POSE_W), .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .LANES(LANES)
  ) dut (
    .clk(clk), .rst(rst),
    .pose_wr_en(pose_wr_en), .pose_wr_id(pose_wr_id),
    .pose_wr_m00(pose_wr_m00), .pose_wr_m01(pose_wr_m01),
    .pose_wr_m10(pose_wr_m10), .pose_wr_m11(pose_wr_m11),
    .pose_wr_tx(pose_wr_tx), .pose_wr_ty(pose_wr_ty),
    .pose_rd_id_flat(pose_rd_id_flat), .pose_rd_found(pose_rd_found),
    .pose_rd_m00_flat(pose_rd_m00_flat), .pose_rd_m01_flat(pose_rd_m01_flat),
    .pose_rd_m10_flat(pose_rd_m10_flat), .pose_rd_m11_flat(pose_rd_m11_flat),
    .pose_rd_tx_flat(pose_rd_tx_flat), .pose_rd_ty_flat(pose_rd_ty_flat)
  );

  always #5 clk = ~clk;

  task automatic set_read_id;
    input integer lane_in;
    input [POSE_W-1:0] id_in;
    begin
      pose_rd_id_flat[lane_in*POSE_W +: POSE_W] = id_in;
    end
  endtask

  task automatic drive_write;
    input [POSE_W-1:0] id_in;
    input signed [MATRIX_W-1:0] m00_in;
    input signed [MATRIX_W-1:0] m01_in;
    input signed [MATRIX_W-1:0] m10_in;
    input signed [MATRIX_W-1:0] m11_in;
    input signed [OFFSET_W-1:0] tx_in;
    input signed [OFFSET_W-1:0] ty_in;
    begin
      pose_wr_en = 1'b1;
      pose_wr_id = id_in;
      pose_wr_m00 = m00_in;
      pose_wr_m01 = m01_in;
      pose_wr_m10 = m10_in;
      pose_wr_m11 = m11_in;
      pose_wr_tx = tx_in;
      pose_wr_ty = ty_in;
    end
  endtask

  task automatic commit_write;
    begin
      @(posedge clk);
      #1;
      pose_wr_en = 1'b0;
    end
  endtask

  task automatic expect_not_found;
    input integer lane_in;
    begin
      if (pose_rd_found[lane_in] !== 1'b0) begin
        errors = errors + 1;
        $display("EXPECTED_NOT_FOUND lane=%0d id=%0d got=%b",
                 lane_in, pose_rd_id_flat[lane_in*POSE_W +: POSE_W],
                 pose_rd_found[lane_in]);
      end
    end
  endtask

  task automatic expect_pose;
    input integer lane_in;
    input signed [MATRIX_W-1:0] m00_expected;
    input signed [MATRIX_W-1:0] m01_expected;
    input signed [MATRIX_W-1:0] m10_expected;
    input signed [MATRIX_W-1:0] m11_expected;
    input signed [OFFSET_W-1:0] tx_expected;
    input signed [OFFSET_W-1:0] ty_expected;
    reg signed [MATRIX_W-1:0] m00_got;
    reg signed [MATRIX_W-1:0] m01_got;
    reg signed [MATRIX_W-1:0] m10_got;
    reg signed [MATRIX_W-1:0] m11_got;
    reg signed [OFFSET_W-1:0] tx_got;
    reg signed [OFFSET_W-1:0] ty_got;
    begin
      m00_got = pose_rd_m00_flat[lane_in*MATRIX_W +: MATRIX_W];
      m01_got = pose_rd_m01_flat[lane_in*MATRIX_W +: MATRIX_W];
      m10_got = pose_rd_m10_flat[lane_in*MATRIX_W +: MATRIX_W];
      m11_got = pose_rd_m11_flat[lane_in*MATRIX_W +: MATRIX_W];
      tx_got = pose_rd_tx_flat[lane_in*OFFSET_W +: OFFSET_W];
      ty_got = pose_rd_ty_flat[lane_in*OFFSET_W +: OFFSET_W];
      if (pose_rd_found[lane_in] !== 1'b1 ||
          m00_got !== m00_expected || m01_got !== m01_expected ||
          m10_got !== m10_expected || m11_got !== m11_expected ||
          tx_got !== tx_expected || ty_got !== ty_expected) begin
        errors = errors + 1;
        $display("POSE_MISMATCH lane=%0d id=%0d found=%b got=(%0d,%0d,%0d,%0d,%0d,%0d) expected=(%0d,%0d,%0d,%0d,%0d,%0d)",
                 lane_in, pose_rd_id_flat[lane_in*POSE_W +: POSE_W],
                 pose_rd_found[lane_in],
                 m00_got, m01_got, m10_got, m11_got, tx_got, ty_got,
                 m00_expected, m01_expected, m10_expected, m11_expected,
                 tx_expected, ty_expected);
      end
    end
  endtask

  initial begin
    errors = 0;
    rst = 1'b1;
    pose_wr_en = 1'b0;
    pose_wr_id = 0;
    pose_wr_m00 = 0;
    pose_wr_m01 = 0;
    pose_wr_m10 = 0;
    pose_wr_m11 = 0;
    pose_wr_tx = 0;
    pose_wr_ty = 0;
    pose_rd_id_flat = 0;

    repeat (2) @(posedge clk);
    #1;
    for (lane = 0; lane < LANES; lane = lane + 1) begin
      set_read_id(lane, lane);
      #1;
      expect_not_found(lane);
    end
    rst = 1'b0;

    // Store two records containing positive, negative, and signed-limit values.
    drive_write(4'd3, 16'sd16384, -16'sd512, 16'sh8000, 16'sh7fff,
                -24'sd765432, 24'sd765431);
    commit_write;
    drive_write(4'd10, -16'sd1, 16'sd2, -16'sd3, 16'sd4,
                24'sh800000, 24'sh7fffff);
    commit_write;

    // All eight read ports operate at once and may select the same or different IDs.
    set_read_id(0, 4'd3);
    set_read_id(1, 4'd10);
    set_read_id(2, 4'd7);
    set_read_id(3, 4'd3);
    set_read_id(4, 4'd10);
    set_read_id(5, 4'd1);
    set_read_id(6, 4'd14);
    set_read_id(7, 4'd9);
    #1;
    expect_pose(0, 16'sd16384, -16'sd512, 16'sh8000, 16'sh7fff,
                -24'sd765432, 24'sd765431);
    expect_pose(1, -16'sd1, 16'sd2, -16'sd3, 16'sd4,
                24'sh800000, 24'sh7fffff);
    expect_not_found(2);
    expect_pose(3, 16'sd16384, -16'sd512, 16'sh8000, 16'sh7fff,
                -24'sd765432, 24'sd765431);
    expect_pose(4, -16'sd1, 16'sd2, -16'sd3, 16'sd4,
                24'sh800000, 24'sh7fffff);
    expect_not_found(5);
    expect_not_found(6);
    expect_not_found(7);

    // A new ID is visible combinationally before its write edge.
    set_read_id(0, 4'd5);
    set_read_id(1, 4'd3);
    set_read_id(2, 4'd5);
    drive_write(4'd5, -16'sd2222, 16'sd3333, -16'sd4444, 16'sd5555,
                -24'sd1234567, 24'sd2345678);
    #1;
    expect_pose(0, -16'sd2222, 16'sd3333, -16'sd4444, 16'sd5555,
                -24'sd1234567, 24'sd2345678);
    expect_pose(1, 16'sd16384, -16'sd512, 16'sh8000, 16'sh7fff,
                -24'sd765432, 24'sd765431);
    expect_pose(2, -16'sd2222, 16'sd3333, -16'sd4444, 16'sd5555,
                -24'sd1234567, 24'sd2345678);
    commit_write;
    #1;
    expect_pose(0, -16'sd2222, 16'sd3333, -16'sd4444, 16'sd5555,
                -24'sd1234567, 24'sd2345678);

    // Reusing an ID replaces only that record; write-through returns the new data.
    set_read_id(0, 4'd3);
    set_read_id(1, 4'd10);
    drive_write(4'd3, -16'sd32767, 16'sd32767, -16'sd12345, 16'sd23456,
                24'sh800000, 24'sh7fffff);
    #1;
    expect_pose(0, -16'sd32767, 16'sd32767, -16'sd12345, 16'sd23456,
                24'sh800000, 24'sh7fffff);
    expect_pose(1, -16'sd1, 16'sd2, -16'sd3, 16'sd4,
                24'sh800000, 24'sh7fffff);
    commit_write;
    #1;
    expect_pose(0, -16'sd32767, 16'sd32767, -16'sd12345, 16'sd23456,
                24'sh800000, 24'sh7fffff);
    expect_pose(1, -16'sd1, 16'sd2, -16'sd3, 16'sd4,
                24'sh800000, 24'sh7fffff);

    // Reset invalidates old IDs, including overwritten and write-through records.
    rst = 1'b1;
    @(posedge clk);
    #1;
    set_read_id(0, 4'd3);
    set_read_id(1, 4'd5);
    set_read_id(2, 4'd10);
    #1;
    expect_not_found(0);
    expect_not_found(1);
    expect_not_found(2);

    if (errors == 0) begin
      $display("POSE_HISTORY_AFFINE8_PASS");
      $finish;
    end else begin
      $fatal(1, "POSE_HISTORY_AFFINE8_FAIL errors=%0d", errors);
    end
  end
endmodule
