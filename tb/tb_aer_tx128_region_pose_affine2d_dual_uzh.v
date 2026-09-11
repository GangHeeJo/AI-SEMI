`timescale 1ns/1ps

// Full-pixel probe of two adjacent 8x8 regions using measured UZH pose/calib.
module tb_aer_tx128_region_pose_affine2d_dual_uzh;
  localparam POSE_W = 1;
  localparam SENSOR_W = 8;
  localparam RESULT_W = 11;
  localparam MATRIX_W = 16;
  localparam OFFSET_W = 24;
  localparam TIMESTAMP_W = 64;
  localparam [1:0] CFG_BEGIN = 2'd0;
  localparam [1:0] CFG_WRITE = 2'd1;
  localparam [1:0] CFG_PUBLISH = 2'd2;

  reg clk = 1'b0;
  reg rst;
  reg [127:0] arrival;
  reg [127:0] polarity_in;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp;
  wire sensor_ready;
  wire [127:0] arrival_blocked;
  wire [127:0] aer_overrun;
  wire [63:0] region_fifo_overflow;

  reg cfg_valid;
  wire cfg_ready;
  reg [1:0] cfg_op;
  reg cfg_region_x;
  reg cfg_region_y;
  reg [POSE_W-1:0] cfg_pose_version;
  reg signed [MATRIX_W-1:0] cfg_m00;
  reg signed [MATRIX_W-1:0] cfg_m01;
  reg signed [MATRIX_W-1:0] cfg_m10;
  reg signed [MATRIX_W-1:0] cfg_m11;
  reg signed [OFFSET_W-1:0] cfg_tx;
  reg signed [OFFSET_W-1:0] cfg_ty;
  wire active_pose_valid;
  wire [POSE_W-1:0] active_pose_version;
  wire cfg_busy;
  wire cfg_awaiting_publish;
  wire cfg_publish_pulse;
  wire cfg_protocol_error;

  reg [SENSOR_W-1:0] base_sensor_origin_x;
  reg [SENSOR_W-1:0] base_sensor_origin_y;
  wire [1:0] world_valid;
  reg [1:0] world_ready;
  wire [1:0] mapped_valid;
  wire [2*SENSOR_W-1:0] sensor_x_flat;
  wire [2*SENSOR_W-1:0] sensor_y_flat;
  wire [1:0] polarity;
  wire [2*POSE_W-1:0] pose_version_flat;
  wire [2*TIMESTAMP_W-1:0] timestamp_flat;
  wire [2*RESULT_W-1:0] world_x_flat;
  wire [2*RESULT_W-1:0] world_y_flat;
  wire [1:0] pose_wr_rejected;
  wire [1:0] pose_accounting_error;
  wire [1:0] world_fire = world_valid & world_ready;

  integer fd;
  integer scan_ret;
  integer line_ret;
  integer kind_i;
  integer pose_i;
  integer region_i;
  integer source_i;
  integer sensor_x_i;
  integer sensor_y_i;
  integer polarity_i;
  reg [63:0] timestamp_i;
  integer m00_i;
  integer m01_i;
  integer m10_i;
  integer m11_i;
  integer tx_i;
  integer ty_i;
  integer rtl_x_i;
  integer rtl_y_i;
  integer exact_x_i;
  integer exact_y_i;
  integer config_rows;
  integer event_rows;
  integer exact_matches;
  integer output_handshakes;
  integer errors;
  integer cycles;
  reg loss_seen;
  reg blocked_seen;
  reg phantom_seen;
  reg expecting_output;
  integer expected_output_region;
  reg [8*1024-1:0] header;

  aer_tx128_region_pose_affine2d_dual #(
    .POSE_W(POSE_W), .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W),
    .TIMESTAMP_W(TIMESTAMP_W), .FIFO_DEPTH(8),
    .X_MIN(0), .X_MAX(511), .Y_MIN(0), .Y_MAX(255)
  ) dut (
    .clk(clk), .rst(rst), .arrival(arrival),
    .polarity_in(polarity_in),
    .occurrence_timestamp(occurrence_timestamp),
    .sensor_ready(sensor_ready), .arrival_blocked(arrival_blocked),
    .aer_overrun(aer_overrun),
    .region_fifo_overflow(region_fifo_overflow),
    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_op(cfg_op),
    .cfg_region_x(cfg_region_x), .cfg_region_y(cfg_region_y),
    .cfg_pose_version(cfg_pose_version),
    .cfg_m00(cfg_m00), .cfg_m01(cfg_m01),
    .cfg_m10(cfg_m10), .cfg_m11(cfg_m11),
    .cfg_tx(cfg_tx), .cfg_ty(cfg_ty),
    .active_pose_valid(active_pose_valid),
    .active_pose_version(active_pose_version),
    .cfg_busy(cfg_busy), .cfg_awaiting_publish(cfg_awaiting_publish),
    .cfg_publish_pulse(cfg_publish_pulse),
    .cfg_protocol_error(cfg_protocol_error),
    .base_sensor_origin_x(base_sensor_origin_x),
    .base_sensor_origin_y(base_sensor_origin_y),
    .world_valid(world_valid), .world_ready(world_ready),
    .mapped_valid(mapped_valid),
    .sensor_x_flat(sensor_x_flat), .sensor_y_flat(sensor_y_flat),
    .polarity(polarity), .pose_version_flat(pose_version_flat),
    .timestamp_flat(timestamp_flat),
    .world_x_flat(world_x_flat), .world_y_flat(world_y_flat),
    .pose_wr_rejected(pose_wr_rejected),
    .pose_accounting_error(pose_accounting_error)
  );

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst) begin
      loss_seen <= 1'b0;
      blocked_seen <= 1'b0;
      phantom_seen <= 1'b0;
      output_handshakes <= 0;
    end else begin
      if (|aer_overrun || |region_fifo_overflow ||
          |pose_wr_rejected || |pose_accounting_error)
        loss_seen <= 1'b1;
      if (|arrival_blocked)
        blocked_seen <= 1'b1;
      if (world_fire == 2'b01 || world_fire == 2'b10)
        output_handshakes <= output_handshakes + 1;
      else if (world_fire == 2'b11)
        output_handshakes <= output_handshakes + 2;
      if (|world_fire) begin
        if (!expecting_output ||
            (world_fire[0] && expected_output_region != 0) ||
            (world_fire[1] && expected_output_region != 1) ||
            world_fire == 2'b11)
          phantom_seen <= 1'b1;
      end
    end
  end

  task automatic fail;
    input [8*112-1:0] message;
    begin
      errors = errors + 1;
      $display("UZH_DUAL_CHECK_FAIL %0s", message);
    end
  endtask

  task automatic check_condition;
    input condition;
    input [8*112-1:0] message;
    begin
      if (condition !== 1'b1)
        fail(message);
    end
  endtask

  task automatic send_cfg;
    input [1:0] op_in;
    input integer region_in;
    input integer pose_in;
    input integer m00_in;
    input integer m01_in;
    input integer m10_in;
    input integer m11_in;
    input integer tx_in;
    input integer ty_in;
    begin
      @(negedge clk);
      cfg_op = op_in;
      cfg_region_x = region_in[0];
      cfg_region_y = 1'b0;
      cfg_pose_version = pose_in[POSE_W-1:0];
      cfg_m00 = m00_in;
      cfg_m01 = m01_in;
      cfg_m10 = m10_in;
      cfg_m11 = m11_in;
      cfg_tx = tx_in;
      cfg_ty = ty_in;
      cfg_valid = 1'b1;
      cycles = 0;
      #1;
      while (cfg_ready !== 1'b1 && cycles < 200) begin
        @(negedge clk);
        #1;
        cycles = cycles + 1;
      end
      check_condition(cfg_ready, "configuration handshake timed out");
      @(posedge clk);
      #1;
      cfg_valid = 1'b0;
    end
  endtask

  task automatic send_event;
    input integer region_in;
    input integer source_in;
    input integer sensor_x_in;
    input integer sensor_y_in;
    input integer polarity_value;
    input integer pose_in;
    input [TIMESTAMP_W-1:0] timestamp_in;
    input integer expected_x;
    input integer expected_y;
    begin
      @(negedge clk);
      arrival = 0;
      polarity_in = 0;
      arrival[region_in*64 + source_in] = 1'b1;
      polarity_in[region_in*64 + source_in] = polarity_value[0];
      occurrence_timestamp = timestamp_in;
      expecting_output = 1'b1;
      expected_output_region = region_in;
      #1;
      check_condition(sensor_ready, "published sensor was not ready");
      check_condition(arrival_blocked == 0, "admitted event was blocked");
      @(posedge clk);
      #1;
      arrival = 0;
      polarity_in = 0;

      cycles = 0;
      while (world_valid[region_in] !== 1'b1 && cycles < 200) begin
        @(posedge clk);
        #1;
        cycles = cycles + 1;
      end
      check_condition(world_valid[region_in], "world event timed out");
      if (world_valid[region_in]) begin
        check_condition(!world_valid[1-region_in],
                        "inactive region emitted a phantom event");
        check_condition(mapped_valid[region_in], "world event did not map");
        check_condition(
          sensor_x_flat[region_in*SENSOR_W +: SENSOR_W] == sensor_x_in &&
          sensor_y_flat[region_in*SENSOR_W +: SENSOR_W] == sensor_y_in,
          "sensor coordinate mismatch");
        check_condition(
          $signed(world_x_flat[region_in*RESULT_W +: RESULT_W]) == expected_x &&
          $signed(world_y_flat[region_in*RESULT_W +: RESULT_W]) == expected_y,
          "Q14 world coordinate mismatch");
        check_condition(polarity[region_in] == polarity_value[0],
                        "polarity mismatch");
        check_condition(
          pose_version_flat[region_in*POSE_W +: POSE_W] == pose_in,
          "pose version mismatch");
        check_condition(
          timestamp_flat[region_in*TIMESTAMP_W +: TIMESTAMP_W] == timestamp_in,
          "occurrence timestamp mismatch");
      end
      @(posedge clk);
      #1;
      expecting_output = 1'b0;
    end
  endtask

  initial begin
    rst = 1'b1;
    arrival = 0;
    polarity_in = 0;
    occurrence_timestamp = 0;
    cfg_valid = 1'b0;
    cfg_op = 0;
    cfg_region_x = 0;
    cfg_region_y = 0;
    cfg_pose_version = 0;
    cfg_m00 = 0;
    cfg_m01 = 0;
    cfg_m10 = 0;
    cfg_m11 = 0;
    cfg_tx = 0;
    cfg_ty = 0;
    base_sensor_origin_x = 32;
    base_sensor_origin_y = 168;
    world_ready = 2'b11;
    config_rows = 0;
    event_rows = 0;
    exact_matches = 0;
    output_handshakes = 0;
    errors = 0;
    loss_seen = 1'b0;
    blocked_seen = 1'b0;
    phantom_seen = 1'b0;
    expecting_output = 1'b0;
    expected_output_region = 0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    fd = $fopen("tb/uzh_dual_region_vectors.tsv", "r");
    if (fd == 0)
      $fatal(1, "cannot open UZH dual-region vectors");
    line_ret = $fgets(header, fd);
    scan_ret = $fscanf(fd,
      "%d %d %d %d %d %d %d %h %d %d %d %d %d %d %d %d %d %d",
      kind_i, pose_i, region_i, source_i, sensor_x_i, sensor_y_i,
      polarity_i, timestamp_i, m00_i, m01_i, m10_i, m11_i, tx_i, ty_i,
      rtl_x_i, rtl_y_i, exact_x_i, exact_y_i);

    while (scan_ret == 18) begin
      if (kind_i == 0) begin
        check_condition(pose_i == config_rows/2 &&
                        region_i == config_rows%2,
                        "configuration raster order mismatch");
        check_condition(event_rows == pose_i*128,
                        "configuration crossed an unfinished pose probe");
        if (region_i == 0)
          send_cfg(CFG_BEGIN, 0, pose_i, 0, 0, 0, 0, 0, 0);
        send_cfg(CFG_WRITE, region_i, pose_i,
                 m00_i, m01_i, m10_i, m11_i, tx_i, ty_i);
        config_rows = config_rows + 1;
        if (region_i == 1) begin
          check_condition(cfg_awaiting_publish,
                          "complete measured epoch did not await publish");
          send_cfg(CFG_PUBLISH, 0, pose_i, 0, 0, 0, 0, 0, 0);
          check_condition(cfg_publish_pulse && active_pose_valid &&
                          active_pose_version == pose_i,
                          "measured epoch publication failed");
        end
      end else if (kind_i == 1) begin
        check_condition(pose_i == event_rows/128 &&
                        region_i == (event_rows%128)/64,
                        "event vector order mismatch");
        check_condition(active_pose_valid && active_pose_version == pose_i,
                        "event used an unpublished pose");
        send_event(region_i, source_i, sensor_x_i, sensor_y_i,
                   polarity_i, pose_i, timestamp_i, rtl_x_i, rtl_y_i);
        exact_matches = exact_matches +
                        ((rtl_x_i == exact_x_i) && (rtl_y_i == exact_y_i));
        event_rows = event_rows + 1;
      end else begin
        fail("unknown vector row kind");
      end
      scan_ret = $fscanf(fd,
        "%d %d %d %d %d %d %d %h %d %d %d %d %d %d %d %d %d %d",
        kind_i, pose_i, region_i, source_i, sensor_x_i, sensor_y_i,
        polarity_i, timestamp_i, m00_i, m01_i, m10_i, m11_i, tx_i, ty_i,
        rtl_x_i, rtl_y_i, exact_x_i, exact_y_i);
    end
    $fclose(fd);

    repeat (20) @(posedge clk);
    #1;
    check_condition(config_rows == 4, "wrong measured coefficient count");
    check_condition(event_rows == 256, "wrong measured event count");
    check_condition(output_handshakes == 256 && !phantom_seen,
                    "world output count, region, or phantom mismatch");
    check_condition(!loss_seen && !blocked_seen,
                    "unexpected AER loss or admission block");
    check_condition(!cfg_protocol_error && !cfg_busy,
                    "configuration did not finish cleanly");

    $display(
      "UZH_DUAL_REGION_RTL_SUMMARY configs=%0d events=%0d exact=%0d errors=%0d",
      config_rows, event_rows, exact_matches, errors);
    if (errors == 0) begin
      $display("UZH_DUAL_REGION_RTL_PASS");
      $finish;
    end else begin
      $fatal(1, "UZH_DUAL_REGION_RTL_FAIL errors=%0d", errors);
    end
  end

  initial begin
    #2000000;
    $fatal(1, "UZH_DUAL_REGION_RTL_TIMEOUT");
  end
endmodule
