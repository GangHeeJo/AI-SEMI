`timescale 1ns/1ps

module tb_coord_transform_affine2d;
  localparam SENSOR_W = 2;
  localparam RESULT_W = 16;
  localparam POSE_W = 8;
  localparam TIMESTAMP_W = 12;

  reg clk = 1'b0;
  reg rst;
  reg event_valid_in;
  reg pose_found_in;
  reg polarity_in;
  reg [POSE_W-1:0] pose_version_in;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp_in;
  reg [SENSOR_W-1:0] sensor_x_in, sensor_y_in;
  reg signed [15:0] m00_in, m01_in, m10_in, m11_in;
  reg signed [23:0] tx_in, ty_in;

  wire event_valid_out, mapped_valid_out, pose_found_out, in_range_out;
  wire upstream_ready;
  wire polarity_out;
  wire [POSE_W-1:0] pose_version_out;
  wire [TIMESTAMP_W-1:0] occurrence_timestamp_out;
  wire signed [RESULT_W-1:0] world_x_out, world_y_out;

  coord_transform_affine2d #(
    .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(16), .OFFSET_W(24), .FRAC_W(14), .POSE_W(POSE_W),
    .TIMESTAMP_W(TIMESTAMP_W),
    .X_MIN(0), .X_MAX(7), .Y_MIN(0), .Y_MAX(7)
  ) dut (
    .clk(clk), .rst(rst),
    .downstream_ready(1'b1), .upstream_ready(upstream_ready),
    .event_valid_in(event_valid_in), .pose_found_in(pose_found_in),
    .polarity_in(polarity_in), .pose_version_in(pose_version_in),
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

  integer fd, scan_ret, line_ret;
  integer case_id, pose_i, x_i, y_i;
  integer a_i, b_i, c_i, d_i, tx_i, ty_i;
  integer found_i, x_acc_i, y_acc_i, ref_x_i, ref_y_i, range_i, write_i;
  integer checked, errors;
  reg [8*32-1:0] kind_s;
  reg [8*96-1:0] case_s;
  reg [8*64-1:0] pose_s;
  reg [8*1024-1:0] header;

  task check_one;
    begin
      if (event_valid_out !== 1'b1) begin
        errors = errors + 1;
        $display("VALID_MISMATCH case=%0d", case_id);
      end
      if (pose_found_out !== found_i[0]) begin
        errors = errors + 1;
        $display("POSE_FOUND_MISMATCH case=%0d got=%b want=%0d", case_id, pose_found_out, found_i);
      end
      if (in_range_out !== range_i[0]) begin
        errors = errors + 1;
        $display("RANGE_MISMATCH case=%0d got=%b want=%0d", case_id, in_range_out, range_i);
      end
      if (mapped_valid_out !== write_i[0]) begin
        errors = errors + 1;
        $display("WRITE_VALID_MISMATCH case=%0d got=%b want=%0d", case_id, mapped_valid_out, write_i);
      end
      if ($signed(world_x_out) !== ref_x_i || $signed(world_y_out) !== ref_y_i) begin
        errors = errors + 1;
        $display("COORD_MISMATCH case=%0d got=(%0d,%0d) want=(%0d,%0d)",
          case_id, $signed(world_x_out), $signed(world_y_out), ref_x_i, ref_y_i);
      end
      if (pose_version_out !== pose_i[POSE_W-1:0] ||
          occurrence_timestamp_out !== case_id[TIMESTAMP_W-1:0] ||
          polarity_out !== case_id[0]) begin
        errors = errors + 1;
        $display("METADATA_MISMATCH case=%0d pose=%0d/%0d time=%0d/%0d pol=%b/%b",
          case_id, pose_version_out, pose_i,
          occurrence_timestamp_out, case_id[TIMESTAMP_W-1:0],
          polarity_out, case_id[0]);
      end
      checked = checked + 1;
    end
  endtask

  initial begin
    rst = 1'b1;
    event_valid_in = 1'b0;
    pose_found_in = 1'b0;
    polarity_in = 1'b0;
    pose_version_in = 0;
    occurrence_timestamp_in = 0;
    sensor_x_in = 0; sensor_y_in = 0;
    m00_in = 0; m01_in = 0; m10_in = 0; m11_in = 0; tx_in = 0; ty_in = 0;
    checked = 0; errors = 0;

    repeat (2) @(posedge clk);
    #1 rst = 1'b0;

    fd = $fopen("tb/stage2_affine_vectors.tsv", "r");
    if (fd == 0) begin
      $display("CANNOT_OPEN_VECTOR_FILE");
      $finish;
    end
    line_ret = $fgets(header, fd);

    scan_ret = $fscanf(fd,
      "%d %s %s %d %s %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
      case_id, kind_s, case_s, pose_i, pose_s, x_i, y_i,
      a_i, b_i, c_i, d_i, tx_i, ty_i, found_i,
      x_acc_i, y_acc_i, ref_x_i, ref_y_i, range_i, write_i);

    while (scan_ret == 20) begin
      @(negedge clk);
      event_valid_in = 1'b1;
      pose_found_in = found_i[0];
      polarity_in = case_id[0];
      pose_version_in = pose_i[POSE_W-1:0];
      occurrence_timestamp_in = case_id[TIMESTAMP_W-1:0];
      sensor_x_in = x_i[SENSOR_W-1:0];
      sensor_y_in = y_i[SENSOR_W-1:0];
      m00_in = a_i; m01_in = b_i; m10_in = c_i; m11_in = d_i;
      tx_in = tx_i; ty_in = ty_i;
      @(posedge clk); #1;
      check_one();

      scan_ret = $fscanf(fd,
        "%d %s %s %d %s %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
        case_id, kind_s, case_s, pose_i, pose_s, x_i, y_i,
        a_i, b_i, c_i, d_i, tx_i, ty_i, found_i,
        x_acc_i, y_acc_i, ref_x_i, ref_y_i, range_i, write_i);
    end

    @(negedge clk); event_valid_in = 1'b0;
    @(posedge clk); #1;
    if (event_valid_out !== 1'b0 || mapped_valid_out !== 1'b0 ||
        occurrence_timestamp_out !== {TIMESTAMP_W{1'b0}}) begin
      errors = errors + 1;
      $display("IDLE_VALID_MISMATCH");
    end

    $fclose(fd);
    $display("AFFINE_VECTOR_SUMMARY checked=%0d errors=%0d", checked, errors);
    if (checked == 122 && errors == 0)
      $display("COORD_TRANSFORM_AFFINE2D_PASS");
    else
      $display("COORD_TRANSFORM_AFFINE2D_FAIL");
    $finish;
  end
endmodule
