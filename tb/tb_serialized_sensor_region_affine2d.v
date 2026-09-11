`timescale 1ns/1ps
module tb_serialized_sensor_region_affine2d;
  localparam integer SENSOR_W = 8;
  localparam integer REGION_COLS = 30;
  localparam integer REGION_ROWS = 23;
  localparam integer REGION_COUNT = REGION_COLS * REGION_ROWS;
  localparam integer REGION_ID_W = 10;
  localparam integer RESULT_W = 16;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer FRAC_W = 4;
  localparam integer TIMESTAMP_W = 35;
  localparam integer Q_ONE = 1 << FRAC_W;
  localparam [1:0] CFG_BEGIN = 2'd0;
  localparam [1:0] CFG_WRITE = 2'd1;
  localparam [1:0] CFG_PUBLISH = 2'd2;

  reg clk;
  reg rst;
  reg cfg_valid;
  wire cfg_ready;
  reg [1:0] cfg_op;
  reg [4:0] cfg_region_x;
  reg [4:0] cfg_region_y;
  reg cfg_pose_version;
  reg signed [MATRIX_W-1:0] cfg_m00;
  reg signed [MATRIX_W-1:0] cfg_m01;
  reg signed [MATRIX_W-1:0] cfg_m10;
  reg signed [MATRIX_W-1:0] cfg_m11;
  reg signed [OFFSET_W-1:0] cfg_tx;
  reg signed [OFFSET_W-1:0] cfg_ty;
  wire active_pose_valid;
  wire active_pose_version;
  wire cfg_busy;
  wire cfg_awaiting_publish;
  wire cfg_publish_pulse;
  wire cfg_protocol_error;

  reg event_valid_in;
  wire event_ready_in;
  reg [SENSOR_W-1:0] sensor_x_in;
  reg [SENSOR_W-1:0] sensor_y_in;
  reg polarity_in;
  reg occurrence_pose_version_in;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp_in;

  wire world_valid;
  reg world_ready;
  wire mapped_valid;
  wire pose_found;
  wire in_range;
  wire [REGION_ID_W-1:0] region_id_out;
  wire [SENSOR_W-1:0] sensor_x_out;
  wire [SENSOR_W-1:0] sensor_y_out;
  wire polarity_out;
  wire pose_version_out;
  wire [TIMESTAMP_W-1:0] occurrence_timestamp_out;
  wire signed [RESULT_W-1:0] world_x_out;
  wire signed [RESULT_W-1:0] world_y_out;
  wire [1:0] pose_outstanding0;
  wire [1:0] pose_outstanding1;
  wire [1:0] pose_overwrite_ready;
  wire pose_accounting_error;

  integer errors;
  integer expected_count;
  integer accepted_count;
  integer retired_count;
  integer output_count;
  integer write_commit_count;
  integer publish_count;
  integer wait_cycles;
  integer region_index;
  integer quiet_output_count;

  reg [REGION_ID_W-1:0] exp_region [0:31];
  reg [SENSOR_W-1:0] exp_sensor_x [0:31];
  reg [SENSOR_W-1:0] exp_sensor_y [0:31];
  reg exp_polarity [0:31];
  reg exp_pose [0:31];
  reg [TIMESTAMP_W-1:0] exp_timestamp [0:31];
  reg exp_found [0:31];
  reg exp_range [0:31];
  integer exp_world_x [0:31];
  integer exp_world_y [0:31];

  reg [REGION_ID_W-1:0] stall_region;
  reg [SENSOR_W-1:0] stall_sensor_x;
  reg [SENSOR_W-1:0] stall_sensor_y;
  reg stall_polarity;
  reg stall_pose;
  reg [TIMESTAMP_W-1:0] stall_timestamp;
  reg stall_found;
  reg stall_range;
  reg signed [RESULT_W-1:0] stall_world_x;
  reg signed [RESULT_W-1:0] stall_world_y;

  wire event_fire = event_valid_in && event_ready_in;

  serialized_sensor_region_affine2d #(
    .SENSOR_COLS(240), .SENSOR_ROWS(180), .SENSOR_W(SENSOR_W),
    .REGION_COLS(REGION_COLS), .REGION_ROWS(REGION_ROWS),
    .REGION_X_W(5), .REGION_Y_W(5), .REGION_ID_W(REGION_ID_W),
    .RESULT_W(RESULT_W), .MATRIX_W(MATRIX_W),
    .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .POSE_W(1), .TIMESTAMP_W(TIMESTAMP_W), .GUARD_COUNT_W(2),
    .X_MIN(0), .X_MAX(511), .Y_MIN(0), .Y_MAX(511)
  ) dut (
    .clk(clk), .rst(rst),
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
    .event_valid_in(event_valid_in), .event_ready_in(event_ready_in),
    .sensor_x_in(sensor_x_in), .sensor_y_in(sensor_y_in),
    .polarity_in(polarity_in),
    .occurrence_pose_version_in(occurrence_pose_version_in),
    .occurrence_timestamp_in(occurrence_timestamp_in),
    .world_valid(world_valid), .world_ready(world_ready),
    .mapped_valid(mapped_valid), .pose_found(pose_found),
    .in_range(in_range), .region_id_out(region_id_out),
    .sensor_x_out(sensor_x_out), .sensor_y_out(sensor_y_out),
    .polarity_out(polarity_out), .pose_version_out(pose_version_out),
    .occurrence_timestamp_out(occurrence_timestamp_out),
    .world_x_out(world_x_out), .world_y_out(world_y_out),
    .pose_outstanding0(pose_outstanding0),
    .pose_outstanding1(pose_outstanding1),
    .pose_overwrite_ready(pose_overwrite_ready),
    .pose_accounting_error(pose_accounting_error)
  );

  always #5 clk = ~clk;

  task fail;
    input [8*112-1:0] message;
    begin
      errors = errors + 1;
      $display("CHECK_FAIL %0s", message);
    end
  endtask

  task check_condition;
    input condition;
    input [8*112-1:0] message;
    begin
      if (condition !== 1'b1)
        fail(message);
    end
  endtask

  task drive_cfg;
    input [1:0] op_in;
    input integer x_in;
    input integer y_in;
    input integer pose_in;
    input integer base_x;
    input integer base_y;
    begin
      cfg_op = op_in;
      cfg_region_x = x_in;
      cfg_region_y = y_in;
      cfg_pose_version = pose_in;
      cfg_m00 = Q_ONE;
      cfg_m01 = 0;
      cfg_m10 = 0;
      cfg_m11 = Q_ONE;
      cfg_tx = (base_x + x_in) * Q_ONE;
      cfg_ty = (base_y + y_in) * Q_ONE;
      cfg_valid = 1'b1;
    end
  endtask

  task send_cfg;
    input [1:0] op_in;
    input integer x_in;
    input integer y_in;
    input integer pose_in;
    input integer base_x;
    input integer base_y;
    begin
      @(negedge clk);
      drive_cfg(op_in, x_in, y_in, pose_in, base_x, base_y);
      #1;
      while (cfg_ready !== 1'b1)
        @(negedge clk);
      @(posedge clk);
      #1;
      cfg_valid = 1'b0;
    end
  endtask

  task write_epoch_range;
    input integer pose_in;
    input integer base_x;
    input integer base_y;
    input integer first_region;
    integer write_x;
    integer write_y;
    begin
      for (region_index = first_region; region_index < REGION_COUNT;
           region_index = region_index + 1) begin
        write_x = region_index % REGION_COLS;
        write_y = region_index / REGION_COLS;
        send_cfg(CFG_WRITE, write_x, write_y,
                 pose_in, base_x, base_y);
      end
    end
  endtask

  task queue_expected;
    input integer region_in;
    input integer x_in;
    input integer y_in;
    input integer polarity_value;
    input integer pose_in;
    input integer timestamp_in;
    input integer found_in;
    input integer range_in;
    input integer world_x_in;
    input integer world_y_in;
    begin
      exp_region[expected_count] = region_in;
      exp_sensor_x[expected_count] = x_in;
      exp_sensor_y[expected_count] = y_in;
      exp_polarity[expected_count] = polarity_value;
      exp_pose[expected_count] = pose_in;
      exp_timestamp[expected_count] = timestamp_in;
      exp_found[expected_count] = found_in;
      exp_range[expected_count] = range_in;
      exp_world_x[expected_count] = world_x_in;
      exp_world_y[expected_count] = world_y_in;
      expected_count = expected_count + 1;
    end
  endtask

  task queue_valid;
    input integer x_in;
    input integer y_in;
    input integer polarity_value;
    input integer pose_in;
    input integer timestamp_in;
    input integer base_x;
    input integer base_y;
    integer region_x;
    integer region_y;
    begin
      region_x = x_in >> 3;
      region_y = y_in >> 3;
      queue_expected(region_y*REGION_COLS+region_x,
                     x_in, y_in, polarity_value, pose_in, timestamp_in,
                     1, 1, x_in+base_x+region_x,
                     y_in+base_y+region_y);
    end
  endtask

  task drive_event;
    input integer x_in;
    input integer y_in;
    input integer polarity_value;
    input integer pose_in;
    input integer timestamp_in;
    begin
      sensor_x_in = x_in;
      sensor_y_in = y_in;
      polarity_in = polarity_value;
      occurrence_pose_version_in = pose_in;
      occurrence_timestamp_in = timestamp_in;
      event_valid_in = 1'b1;
    end
  endtask

  task send_valid_event;
    input integer x_in;
    input integer y_in;
    input integer polarity_value;
    input integer pose_in;
    input integer timestamp_in;
    input integer base_x;
    input integer base_y;
    begin
      queue_valid(x_in, y_in, polarity_value, pose_in, timestamp_in,
                  base_x, base_y);
      @(negedge clk);
      drive_event(x_in, y_in, polarity_value, pose_in, timestamp_in);
      #1;
      while (event_ready_in !== 1'b1)
        @(negedge clk);
      @(posedge clk);
      #1;
      event_valid_in = 1'b0;
    end
  endtask

  task send_invalid_event;
    input integer x_in;
    input integer y_in;
    input integer polarity_value;
    input integer pose_in;
    input integer timestamp_in;
    begin
      queue_expected(REGION_COUNT, x_in, y_in, polarity_value,
                     pose_in, timestamp_in, 0, 0, 0, 0);
      @(negedge clk);
      drive_event(x_in, y_in, polarity_value, pose_in, timestamp_in);
      #1;
      while (event_ready_in !== 1'b1)
        @(negedge clk);
      @(posedge clk);
      #1;
      event_valid_in = 1'b0;
    end
  endtask

  task send_cfg_with_valid_event;
    input [1:0] op_in;
    input integer cfg_x;
    input integer cfg_y;
    input integer cfg_pose;
    input integer cfg_base_x;
    input integer cfg_base_y;
    input integer event_x;
    input integer event_y;
    input integer event_polarity;
    input integer event_pose;
    input integer event_timestamp;
    input integer event_base_x;
    input integer event_base_y;
    begin
      queue_valid(event_x, event_y, event_polarity,
                  event_pose, event_timestamp,
                  event_base_x, event_base_y);
      @(negedge clk);
      drive_cfg(op_in, cfg_x, cfg_y, cfg_pose,
                cfg_base_x, cfg_base_y);
      drive_event(event_x, event_y, event_polarity,
                  event_pose, event_timestamp);
      #1;
      check_condition(cfg_ready && event_ready_in,
                      "config and event were not concurrently ready");
      @(posedge clk);
      #1;
      cfg_valid = 1'b0;
      event_valid_in = 1'b0;
    end
  endtask

  task wait_for_all_outputs;
    begin
      wait_cycles = 0;
      while ((output_count != expected_count || world_valid) &&
             wait_cycles < 300) begin
        @(posedge clk);
        #1;
        wait_cycles = wait_cycles + 1;
      end
      check_condition(output_count == expected_count && !world_valid,
                      "expected output events did not drain");
    end
  endtask

  always @(posedge clk) begin
    if (!rst && event_fire)
      accepted_count = accepted_count + 1;
    if (!rst && dut.terminal_retire)
      retired_count = retired_count + 1;
    if (!rst && dut.region_wr_commit)
      write_commit_count = write_commit_count + 1;
    if (!rst && cfg_publish_pulse)
      publish_count = publish_count + 1;

    if (!rst && world_valid && world_ready) begin
      if (output_count >= expected_count) begin
        fail("phantom output event");
      end else begin
        check_condition(region_id_out == exp_region[output_count],
                        "region id mismatch");
        check_condition(sensor_x_out == exp_sensor_x[output_count] &&
                        sensor_y_out == exp_sensor_y[output_count],
                        "sensor coordinate metadata mismatch");
        check_condition(polarity_out == exp_polarity[output_count],
                        "polarity mismatch");
        check_condition(pose_version_out == exp_pose[output_count],
                        "occurrence pose tag mismatch");
        check_condition(occurrence_timestamp_out ==
                        exp_timestamp[output_count],
                        "occurrence timestamp mismatch");
        check_condition(pose_found == exp_found[output_count],
                        "coefficient found mismatch");
        check_condition(in_range == exp_range[output_count],
                        "range result mismatch");
        check_condition(mapped_valid ==
                        (exp_found[output_count] &&
                         exp_range[output_count]),
                        "mapped-valid mismatch");
        check_condition($signed(world_x_out) ==
                        exp_world_x[output_count] &&
                        $signed(world_y_out) ==
                        exp_world_y[output_count],
                        "world coordinate mismatch");
      end
      output_count = output_count + 1;
    end
  end

  initial begin
    clk = 1'b0;
    rst = 1'b1;
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
    event_valid_in = 1'b0;
    sensor_x_in = 0;
    sensor_y_in = 0;
    polarity_in = 0;
    occurrence_pose_version_in = 0;
    occurrence_timestamp_in = 0;
    world_ready = 1'b1;
    errors = 0;
    expected_count = 0;
    accepted_count = 0;
    retired_count = 0;
    output_count = 0;
    write_commit_count = 0;
    publish_count = 0;

    repeat (3) @(posedge clk);
    #1;
    check_condition(!event_ready_in && !active_pose_valid,
                    "input must be blocked in reset");
    @(negedge clk);
    rst = 1'b0;

    // BEGIN can proceed while the first sensor event remains backpressured.
    @(negedge clk);
    drive_cfg(CFG_BEGIN, 0, 0, 0, 0, 0);
    drive_event(7, 7, 1, 0, 1);
    #1;
    check_condition(cfg_ready && !event_ready_in,
                    "pre-publication event was not backpressured");
    @(posedge clk);
    #1;
    cfg_valid = 1'b0;
    event_valid_in = 1'b0;
    check_condition(accepted_count == 0,
                    "pre-publication event was incorrectly accepted");

    // Load all 690 records, including the final 8x4 physical edge region.
    write_epoch_range(0, 0, 0, 0);
    check_condition(cfg_awaiting_publish &&
                    write_commit_count == REGION_COUNT,
                    "pose0 did not load all 30x23 records");
    send_cfg(CFG_PUBLISH, 0, 0, 0, 0, 0);
    check_condition(active_pose_valid && active_pose_version == 0,
                    "first publication failed");
    send_valid_event(239, 179, 1, 0, 10, 0, 0);
    wait_for_all_outputs;
    check_condition(exp_region[0] == 689,
                    "edge 8x4 region id expectation is wrong");

    // A pose1 table write and pose0 event lookup share the same edge.
    send_cfg(CFG_BEGIN, 0, 0, 1, 0, 0);
    send_cfg_with_valid_event(CFG_WRITE, 0, 0, 1, 100, 50,
                              16, 16, 0, 0, 20, 0, 0);
    write_epoch_range(1, 100, 50, 1);
    check_condition(cfg_awaiting_publish &&
                    write_commit_count == 2*REGION_COUNT,
                    "pose1 did not load all 30x23 records");

    // The PUBLISH handshake changes active_pose only after this edge.  The
    // concurrent occurrence therefore carries the explicit old pose0 tag;
    // the following event carries pose1.
    send_cfg_with_valid_event(CFG_PUBLISH, 0, 0, 1, 0, 0,
                              9, 9, 1, 0, 21, 0, 0);
    check_condition(cfg_publish_pulse && active_pose_version == 1,
                    "pose1 publish-edge state transition failed");
    send_valid_event(9, 9, 0, 1, 22, 100, 50);
    wait_for_all_outputs;

    // The final sensor row maps to region row 22, whose physical height is
    // four pixels.  Hold its output and require every field to remain stable.
    world_ready = 1'b0;
    send_valid_event(239, 179, 1, 1, 30, 100, 50);
    wait_cycles = 0;
    while (!world_valid && wait_cycles < 30) begin
      @(posedge clk);
      #1;
      wait_cycles = wait_cycles + 1;
    end
    check_condition(world_valid && region_id_out == 689 &&
                    pose_outstanding1 == 0,
                    "edge-region event did not retire into stalled output");
    stall_region = region_id_out;
    stall_sensor_x = sensor_x_out;
    stall_sensor_y = sensor_y_out;
    stall_polarity = polarity_out;
    stall_pose = pose_version_out;
    stall_timestamp = occurrence_timestamp_out;
    stall_found = pose_found;
    stall_range = in_range;
    stall_world_x = world_x_out;
    stall_world_y = world_y_out;
    repeat (3) begin
      @(posedge clk);
      #1;
      check_condition(world_valid && region_id_out == stall_region &&
                      sensor_x_out == stall_sensor_x &&
                      sensor_y_out == stall_sensor_y &&
                      polarity_out == stall_polarity &&
                      pose_version_out == stall_pose &&
                      occurrence_timestamp_out == stall_timestamp &&
                      pose_found == stall_found &&
                      in_range == stall_range &&
                      world_x_out == stall_world_x &&
                      world_y_out == stall_world_y,
                      "world output changed while stalled");
    end
    @(negedge clk);
    world_ready = 1'b1;
    wait_for_all_outputs;

    // Invalid X and invalid Y both use sentinel 690; neither aliases a valid
    // region even though x>>3 or y>>3 alone could form an in-table address.
    send_invalid_event(240, 0, 0, 1, 40);
    send_invalid_event(0, 180, 1, 1, 41);
    send_invalid_event(240, 180, 1, 0, 42);
    wait_for_all_outputs;

    // Fill the affine output with pose1, then leave one old pose0 lookup
    // outstanding behind it.  Reload of pose0 must wait for lookup capture.
    world_ready = 1'b0;
    send_valid_event(1, 2, 1, 1, 50, 100, 50);
    wait_cycles = 0;
    while (!world_valid && wait_cycles < 30) begin
      @(posedge clk);
      #1;
      wait_cycles = wait_cycles + 1;
    end
    check_condition(world_valid, "old-slot blocker did not reach output");
    send_valid_event(15, 9, 0, 0, 51, 0, 0);
    check_condition(dut.lookup_rsp_valid &&
                    !dut.lookup_rsp_ready && pose_outstanding0 == 1,
                    "old pose event did not remain before affine capture");

    send_cfg(CFG_BEGIN, 0, 0, 0, 0, 0);
    @(negedge clk);
    drive_cfg(CFG_WRITE, 0, 0, 0, 200, 100);
    #1;
    check_condition(!cfg_ready && !dut.region_wr_req &&
                    !pose_overwrite_ready[0],
                    "old slot rewrite escaped outstanding-event guard");
    repeat (2) begin
      @(posedge clk);
      #1;
      check_condition(!cfg_ready && pose_outstanding0 == 1 &&
                      !dut.terminal_retire,
                      "old slot advanced before coefficient capture");
    end

    @(negedge clk);
    world_ready = 1'b1;
    #1;
    check_condition(dut.terminal_retire &&
                    !dut.terminal_retire_pose_version &&
                    !cfg_ready && !pose_overwrite_ready[0],
                    "old slot became writable on last-retire edge");
    @(posedge clk);
    #1;
    check_condition(pose_outstanding0 == 0 &&
                    pose_overwrite_ready[0] && cfg_ready &&
                    dut.region_wr_req && dut.region_wr_commit,
                    "old slot did not become writable next cycle");
    @(posedge clk);
    #1;
    cfg_valid = 1'b0;
    check_condition(dut.u_loader.expected_region_x == 1 &&
                    dut.u_loader.expected_region_y == 0,
                    "released old-slot write did not commit once");

    write_epoch_range(0, 200, 100, 1);
    check_condition(cfg_awaiting_publish &&
                    write_commit_count == 3*REGION_COUNT,
                    "reloaded pose0 did not contain all 30x23 records");
    send_cfg(CFG_PUBLISH, 0, 0, 0, 0, 0);
    check_condition(active_pose_version == 0,
                    "reloaded pose0 publication failed");
    wait_for_all_outputs;
    send_valid_event(239, 179, 0, 0, 60, 200, 100);
    wait_for_all_outputs;

    quiet_output_count = output_count;
    repeat (8) begin
      @(posedge clk);
      #1;
      check_condition(!world_valid && !dut.terminal_retire,
                      "phantom event appeared after drain");
    end
    check_condition(output_count == quiet_output_count,
                    "output count changed after drain");
    check_condition(expected_count == accepted_count &&
                    accepted_count == retired_count &&
                    retired_count == output_count,
                    "event conservation mismatch");
    check_condition(write_commit_count == 3*REGION_COUNT &&
                    publish_count == 3,
                    "coefficient load conservation mismatch");
    check_condition(pose_outstanding0 == 0 &&
                    pose_outstanding1 == 0,
                    "pose references did not drain");
    check_condition(!pose_accounting_error &&
                    !cfg_protocol_error && !cfg_busy,
                    "configuration or pose accounting error");

    if (errors == 0) begin
      $display("SERIALIZED_SENSOR_REGION_AFFINE2D_PASS events=%0d writes=%0d",
               output_count, write_commit_count);
      $finish;
    end else begin
      $fatal(1, "SERIALIZED_SENSOR_REGION_AFFINE2D_FAIL errors=%0d",
             errors);
    end
  end

  initial begin
    #1000000;
    $fatal(1, "SERIALIZED_SENSOR_REGION_AFFINE2D_TIMEOUT");
  end
endmodule
