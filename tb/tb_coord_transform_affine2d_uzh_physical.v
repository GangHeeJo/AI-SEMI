`timescale 1ns/1ps

// Bit-exact replay of coefficients generated from measured UZH pose/calib.
module tb_coord_transform_affine2d_uzh_physical;
  localparam SENSOR_W = 8;
  localparam RESULT_W = 11;
  localparam POSE_W = 8;
  localparam TIMESTAMP_W = 64;

  reg clk = 1'b0;
  reg rst;
  reg event_valid_in;
  reg polarity_in;
  reg [POSE_W-1:0] pose_version_in;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp_in;
  reg [SENSOR_W-1:0] sensor_x_in;
  reg [SENSOR_W-1:0] sensor_y_in;
  reg signed [15:0] m00_in;
  reg signed [15:0] m01_in;
  reg signed [15:0] m10_in;
  reg signed [15:0] m11_in;
  reg signed [23:0] tx_in;
  reg signed [23:0] ty_in;

  wire upstream_ready;
  wire event_valid_out;
  wire mapped_valid_out;
  wire pose_found_out;
  wire in_range_out;
  wire polarity_out;
  wire [POSE_W-1:0] pose_version_out;
  wire [TIMESTAMP_W-1:0] occurrence_timestamp_out;
  wire signed [RESULT_W-1:0] world_x_out;
  wire signed [RESULT_W-1:0] world_y_out;

  coord_transform_affine2d #(
    .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(16), .OFFSET_W(24), .FRAC_W(14),
    .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W),
    .X_MIN(0), .X_MAX(511), .Y_MIN(0), .Y_MAX(255)
  ) dut (
    .clk(clk), .rst(rst),
    .downstream_ready(1'b1), .upstream_ready(upstream_ready),
    .event_valid_in(event_valid_in), .pose_found_in(1'b1),
    .polarity_in(polarity_in), .pose_version_in(pose_version_in),
    .occurrence_timestamp_in(occurrence_timestamp_in),
    .sensor_x_in(sensor_x_in), .sensor_y_in(sensor_y_in),
    .m00_in(m00_in), .m01_in(m01_in),
    .m10_in(m10_in), .m11_in(m11_in),
    .tx_in(tx_in), .ty_in(ty_in),
    .event_valid_out(event_valid_out), .mapped_valid_out(mapped_valid_out),
    .pose_found_out(pose_found_out), .in_range_out(in_range_out),
    .polarity_out(polarity_out), .pose_version_out(pose_version_out),
    .occurrence_timestamp_out(occurrence_timestamp_out),
    .world_x_out(world_x_out), .world_y_out(world_y_out)
  );

  always #5 clk = ~clk;

  integer fd;
  integer scan_ret;
  integer line_ret;
  integer event_id_i;
  integer x_i;
  integer y_i;
  integer polarity_i;
  reg [63:0] timestamp_i;
  integer a_i;
  integer b_i;
  integer c_i;
  integer d_i;
  integer tx_i;
  integer ty_i;
  integer rtl_x_i;
  integer rtl_y_i;
  integer exact_x_i;
  integer exact_y_i;
  integer checked;
  integer errors;
  reg [8*1024-1:0] header;

  task check_one;
    begin
      if (!event_valid_out || !mapped_valid_out
          || !pose_found_out || !in_range_out) begin
        errors = errors + 1;
        $display("UZH_VALID_MISMATCH event=%0d", event_id_i);
      end
      if ($signed(world_x_out) !== rtl_x_i
          || $signed(world_y_out) !== rtl_y_i) begin
        errors = errors + 1;
        $display("UZH_COORD_MISMATCH event=%0d got=(%0d,%0d) want=(%0d,%0d)",
                 event_id_i, $signed(world_x_out), $signed(world_y_out),
                 rtl_x_i, rtl_y_i);
      end
      if (polarity_out !== polarity_i[0]
          || pose_version_out !== event_id_i[POSE_W-1:0]
          || occurrence_timestamp_out !== timestamp_i) begin
        errors = errors + 1;
        $display("UZH_METADATA_MISMATCH event=%0d", event_id_i);
      end
      checked = checked + 1;
    end
  endtask

  initial begin
    rst = 1'b1;
    event_valid_in = 1'b0;
    polarity_in = 1'b0;
    pose_version_in = 0;
    occurrence_timestamp_in = 0;
    sensor_x_in = 0;
    sensor_y_in = 0;
    m00_in = 0;
    m01_in = 0;
    m10_in = 0;
    m11_in = 0;
    tx_in = 0;
    ty_in = 0;
    checked = 0;
    errors = 0;

    repeat (2) @(posedge clk);
    #1 rst = 1'b0;
    fd = $fopen("tb/uzh_physical_affine_vectors.tsv", "r");
    if (fd == 0)
      $fatal(1, "cannot open UZH physical affine vectors");
    line_ret = $fgets(header, fd);
    scan_ret = $fscanf(fd,
      "%d %d %d %d %h %d %d %d %d %d %d %d %d %d %d",
      event_id_i, x_i, y_i, polarity_i, timestamp_i,
      a_i, b_i, c_i, d_i, tx_i, ty_i,
      rtl_x_i, rtl_y_i, exact_x_i, exact_y_i);

    while (scan_ret == 15) begin
      @(negedge clk);
      if (!upstream_ready) begin
        errors = errors + 1;
        $display("UZH_UPSTREAM_NOT_READY event=%0d", event_id_i);
      end
      event_valid_in = 1'b1;
      polarity_in = polarity_i[0];
      pose_version_in = event_id_i[POSE_W-1:0];
      occurrence_timestamp_in = timestamp_i;
      sensor_x_in = x_i[SENSOR_W-1:0];
      sensor_y_in = y_i[SENSOR_W-1:0];
      m00_in = a_i;
      m01_in = b_i;
      m10_in = c_i;
      m11_in = d_i;
      tx_in = tx_i;
      ty_in = ty_i;
      @(posedge clk);
      #1 check_one();
      scan_ret = $fscanf(fd,
        "%d %d %d %d %h %d %d %d %d %d %d %d %d %d %d",
        event_id_i, x_i, y_i, polarity_i, timestamp_i,
        a_i, b_i, c_i, d_i, tx_i, ty_i,
        rtl_x_i, rtl_y_i, exact_x_i, exact_y_i);
    end

    @(negedge clk);
    event_valid_in = 1'b0;
    @(posedge clk);
    #1;
    if (event_valid_out || mapped_valid_out) begin
      errors = errors + 1;
      $display("UZH_IDLE_VALID_MISMATCH");
    end
    $fclose(fd);
    $display("UZH_PHYSICAL_AFFINE_RTL_SUMMARY checked=%0d errors=%0d",
             checked, errors);
    if (checked == 8503 && errors == 0)
      $display("UZH_PHYSICAL_AFFINE_RTL_PASS");
    else
      $fatal(1, "UZH_PHYSICAL_AFFINE_RTL_FAIL");
    $finish;
  end
endmodule
