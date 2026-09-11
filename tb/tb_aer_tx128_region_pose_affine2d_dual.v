`timescale 1ns/1ps
module tb_aer_tx128_region_pose_affine2d_dual;
  localparam POSE_W = 1;
  localparam SENSOR_W = 6;
  localparam RESULT_W = 16;
  localparam MATRIX_W = 16;
  localparam OFFSET_W = 24;
  localparam TIMESTAMP_W = 16;
  localparam Q14_ONE = 16384;
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

  integer errors;
  integer cycles;
  integer region;
  integer record_index;
  integer got_sensor_x;
  integer got_sensor_y;
  integer got_world_x;
  integer got_world_y;
  integer got_pose;
  integer got_time;
  integer expected_sensor_x;
  integer expected_world_x;
  integer expected_pose;
  integer expected_polarity;
  reg [5:0] seen;
  reg monitor_main_events;

  aer_tx128_region_pose_affine2d_dual #(
    .POSE_W(POSE_W), .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W),
    .TIMESTAMP_W(TIMESTAMP_W), .FIFO_DEPTH(8),
    .X_MIN(0), .X_MAX(255), .Y_MIN(0), .Y_MAX(255)
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
    .cfg_busy(cfg_busy),
    .cfg_awaiting_publish(cfg_awaiting_publish),
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

  task automatic fail;
    input [8*112-1:0] message;
    begin
      errors = errors + 1;
      $display("CHECK_FAIL %0s", message);
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

  task automatic drive_cfg;
    input [1:0] op_in;
    input region_in;
    input [POSE_W-1:0] pose_in;
    input integer tx_cells;
    begin
      cfg_op = op_in;
      cfg_region_x = region_in;
      cfg_region_y = 1'b0;
      cfg_pose_version = pose_in;
      cfg_m00 = Q14_ONE;
      cfg_m01 = 0;
      cfg_m10 = 0;
      cfg_m11 = Q14_ONE;
      cfg_tx = tx_cells * Q14_ONE;
      cfg_ty = 0;
      cfg_valid = 1'b1;
    end
  endtask

  task automatic send_cfg;
    input [1:0] op_in;
    input region_in;
    input [POSE_W-1:0] pose_in;
    input integer tx_cells;
    begin
      @(negedge clk);
      drive_cfg(op_in, region_in, pose_in, tx_cells);
      #1;
      while (cfg_ready !== 1'b1)
        @(negedge clk);
      @(posedge clk);
      #1;
      cfg_valid = 1'b0;
    end
  endtask

  task automatic load_epoch;
    input [POSE_W-1:0] pose_in;
    input integer region0_tx;
    input integer region1_tx;
    begin
      send_cfg(CFG_BEGIN, 1'b0, pose_in, 0);
      send_cfg(CFG_WRITE, 1'b0, pose_in, region0_tx);
      send_cfg(CFG_WRITE, 1'b1, pose_in, region1_tx);
      check_condition(cfg_awaiting_publish,
                      "two writes must wait for explicit publish");
    end
  endtask

  task automatic pulse_pair;
    input integer source;
    input integer timestamp_in;
    input region0_polarity;
    input region1_polarity;
    begin
      @(negedge clk);
      arrival = 0;
      polarity_in = 0;
      arrival[source] = 1'b1;
      arrival[64+source] = 1'b1;
      polarity_in[source] = region0_polarity;
      polarity_in[64+source] = region1_polarity;
      occurrence_timestamp = timestamp_in;
      #1;
      check_condition(sensor_ready, "published sensor must be ready");
      @(posedge clk);
      #1;
      arrival = 0;
      polarity_in = 0;
    end
  endtask

  task automatic pulse_region1;
    input integer source;
    input integer timestamp_in;
    begin
      @(negedge clk);
      arrival = 0;
      polarity_in = 0;
      arrival[64+source] = 1'b1;
      polarity_in[64+source] = 1'b1;
      occurrence_timestamp = timestamp_in;
      #1;
      check_condition(sensor_ready, "region1 guard event must be admitted");
      @(posedge clk);
      #1;
      arrival = 0;
      polarity_in = 0;
    end
  endtask

  always @(posedge clk) begin
    if (!rst && monitor_main_events) begin
      for (region = 0; region < 2; region = region + 1) begin
        if (world_valid[region] && world_ready[region]) begin
          got_sensor_x = sensor_x_flat[region*SENSOR_W +: SENSOR_W];
          got_sensor_y = sensor_y_flat[region*SENSOR_W +: SENSOR_W];
          got_world_x = $signed(
            world_x_flat[region*RESULT_W +: RESULT_W]);
          got_world_y = $signed(
            world_y_flat[region*RESULT_W +: RESULT_W]);
          got_pose = pose_version_flat[region*POSE_W +: POSE_W];
          got_time = timestamp_flat[region*TIMESTAMP_W +: TIMESTAMP_W];
          case (got_time)
            10: begin
              record_index = region;
              expected_sensor_x = region*8 + 3;
              expected_world_x = (region == 0) ? 3 : 43;
              expected_pose = 0;
              expected_polarity = (region == 0);
            end
            20: begin
              record_index = 2 + region;
              expected_sensor_x = region*8;
              expected_world_x = (region == 0) ? 0 : 40;
              expected_pose = 0;
              expected_polarity = (region == 1);
            end
            30: begin
              record_index = 4 + region;
              expected_sensor_x = region*8 + 1;
              expected_world_x = (region == 0) ? 65 : 105;
              expected_pose = 1;
              expected_polarity = 1;
            end
            default: begin
              record_index = 0;
              expected_sensor_x = -1;
              expected_world_x = -1;
              expected_pose = -1;
              expected_polarity = -1;
              fail("unexpected or blocked timestamp reached world output");
            end
          endcase
          if (seen[record_index])
            fail("duplicate world event");
          else
            seen[record_index] = 1'b1;
          check_condition(mapped_valid[region], "world event must map");
          check_condition(got_sensor_x == expected_sensor_x &&
                          got_sensor_y == 0,
                          "sensor coordinate mismatch");
          check_condition(got_world_x == expected_world_x &&
                          got_world_y == 0,
                          "region-local affine mismatch");
          check_condition(got_pose == expected_pose,
                          "publication-edge pose mismatch");
          check_condition(polarity[region] == expected_polarity,
                          "polarity mismatch");
        end
      end
    end
  end

  initial begin
    errors = 0;
    seen = 0;
    monitor_main_events = 1'b1;
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
    base_sensor_origin_x = 0;
    base_sensor_origin_y = 0;
    world_ready = 2'b11;

    repeat (3) @(posedge clk);
    #1;
    check_condition(!sensor_ready, "sensor ready must stay low in reset");
    @(negedge clk);
    rst = 1'b0;

    // An arrival before any complete epoch is explicit and is not admitted.
    arrival[2] = 1'b1;
    arrival[66] = 1'b1;
    occurrence_timestamp = 1;
    #1;
    check_condition(!sensor_ready && arrival_blocked[2] &&
                    arrival_blocked[66],
                    "pre-publication arrival must be reported blocked");
    @(posedge clk);
    #1;
    arrival = 0;

    // Pose 0 uses a distinct X offset in each physical 8x8 region.
    load_epoch(1'b0, 0, 32);
    send_cfg(CFG_PUBLISH, 1'b0, 1'b0, 0);
    check_condition(active_pose_valid && active_pose_version == 0,
                    "first epoch publication failed");
    pulse_pair(3, 10, 1'b1, 1'b0);

    // Prepare pose 1, then accept events on and after its publication edge.
    load_epoch(1'b1, 64, 96);
    @(negedge clk);
    drive_cfg(CFG_PUBLISH, 1'b0, 1'b1, 0);
    arrival[0] = 1'b1;
    arrival[64] = 1'b1;
    polarity_in[0] = 1'b0;
    polarity_in[64] = 1'b1;
    occurrence_timestamp = 20;
    #1;
    check_condition(cfg_ready && sensor_ready,
                    "publish-edge command/event must both be accepted");
    @(posedge clk);
    #1;
    cfg_valid = 1'b0;
    arrival = 0;
    polarity_in = 0;
    check_condition(cfg_publish_pulse && active_pose_version == 1,
                    "second epoch publication failed");
    pulse_pair(1, 30, 1'b1, 1'b1);

    cycles = 0;
    while (seen != 6'b111111 && cycles < 1000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    #1;
    check_condition(seen == 6'b111111,
                    "six expected region events did not drain");

    // Exercise the real response mux with region 1's old pose still busy.
    // Region 0 must accept its rewrite independently; region 1 waits until
    // its final old-pose record reaches the transform, then commits one edge
    // after the guard count becomes zero.
    monitor_main_events = 1'b0;
    world_ready[1] = 1'b0;
    pulse_region1(4, 40);
    pulse_region1(5, 41);
    cycles = 0;
    while (!(world_valid[1] && !dut.local_wr_ready[1]) &&
           cycles < 1000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    check_condition(world_valid[1] && !dut.local_wr_ready[1],
                    "region1 old pose never became busy behind stall");

    load_epoch(1'b0, 128, 160);
    send_cfg(CFG_PUBLISH, 1'b0, 1'b0, 0);
    check_condition(active_pose_version == 0,
                    "intermediate pose0 publication failed");
    send_cfg(CFG_BEGIN, 1'b0, 1'b1, 0);
    send_cfg(CFG_WRITE, 1'b0, 1'b1, 192);
    @(negedge clk);
    drive_cfg(CFG_WRITE, 1'b1, 1'b1, 224);
    #1;
    check_condition(!cfg_ready && !dut.local_wr_req[1],
                    "only selected busy region must stall rewrite");
    repeat (2) begin
      @(posedge clk);
      #1;
      check_condition(!cfg_ready && active_pose_version == 0,
                      "busy old slot changed active pose or advanced");
    end

    @(negedge clk);
    world_ready[1] = 1'b1;
    #1;
    check_condition(!cfg_ready,
                    "rewrite committed before old event retire edge");
    cycles = 0;
    while (cfg_ready !== 1'b1 && cycles < 100) begin
      @(posedge clk);
      #1;
      cycles = cycles + 1;
    end
    check_condition(cfg_ready && dut.local_wr_req[1] &&
                    dut.local_wr_commit[1],
                    "region1 rewrite did not become committable after retire");
    @(posedge clk);
    #1;
    cfg_valid = 1'b0;
    check_condition(cfg_awaiting_publish,
                    "region1 rewrite did not commit exactly once");
    send_cfg(CFG_PUBLISH, 1'b0, 1'b1, 0);
    check_condition(active_pose_version == 1,
                    "reloaded old slot did not publish");

    cycles = 0;
    while (world_valid != 0 && cycles < 1000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    check_condition(aer_overrun == 0 && region_fifo_overflow == 0,
                    "unexpected AER/FIFO loss");
    check_condition(pose_wr_rejected == 0 &&
                    pose_accounting_error == 0,
                    "pose write/guard error");
    check_condition(!cfg_protocol_error && !cfg_busy,
                    "configuration did not finish cleanly");

    if (errors == 0) begin
      $display("AER_TX128_REGION_POSE_AFFINE2D_DUAL_PASS events=6");
      $finish;
    end else begin
      $fatal(1, "AER_TX128_REGION_POSE_AFFINE2D_DUAL_FAIL errors=%0d",
             errors);
    end
  end

  initial begin
    #200000;
    $fatal(1, "AER_TX128_REGION_POSE_AFFINE2D_DUAL_TIMEOUT");
  end
endmodule
