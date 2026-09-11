`timescale 1ns/1ps
module tb_region_affine_shared_lane;
  localparam integer REGION_COLS = 2;
  localparam integer REGION_ROWS = 2;
  localparam integer REGION_ID_W = 2;
  localparam integer SENSOR_W = 6;
  localparam integer RESULT_W = 16;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer FRAC_W = 4;
  localparam integer POSE_W = 1;
  localparam integer TIMESTAMP_W = 16;
  localparam integer Q_ONE = 1 << FRAC_W;
  localparam [1:0] CFG_BEGIN = 2'd0;
  localparam [1:0] CFG_WRITE = 2'd1;
  localparam [1:0] CFG_PUBLISH = 2'd2;

  reg clk;
  reg rst;

  reg cfg_valid;
  wire cfg_ready;
  reg [1:0] cfg_op;
  reg cfg_region_x;
  reg cfg_region_y;
  reg cfg_pose_version;
  reg signed [MATRIX_W-1:0] cfg_m00;
  reg signed [MATRIX_W-1:0] cfg_m01;
  reg signed [MATRIX_W-1:0] cfg_m10;
  reg signed [MATRIX_W-1:0] cfg_m11;
  reg signed [OFFSET_W-1:0] cfg_tx;
  reg signed [OFFSET_W-1:0] cfg_ty;

  wire region_wr_req;
  wire region_wr_x;
  wire region_wr_y;
  wire region_wr_pose_version;
  wire signed [MATRIX_W-1:0] region_wr_m00;
  wire signed [MATRIX_W-1:0] region_wr_m01;
  wire signed [MATRIX_W-1:0] region_wr_m10;
  wire signed [MATRIX_W-1:0] region_wr_m11;
  wire signed [OFFSET_W-1:0] region_wr_tx;
  wire signed [OFFSET_W-1:0] region_wr_ty;
  wire region_wr_ready;
  wire region_wr_commit;
  wire active_pose_valid;
  wire active_pose_version;
  wire load_busy;
  wire awaiting_publish;
  wire publish_pulse;
  wire cfg_protocol_error;

  reg event_valid_in;
  wire event_ready_in;
  reg [REGION_ID_W-1:0] region_id_in;
  reg [SENSOR_W-1:0] sensor_x_in;
  reg [SENSOR_W-1:0] sensor_y_in;
  reg polarity_in;
  reg pose_version_in;
  reg [TIMESTAMP_W-1:0] timestamp_in;

  wire lookup_valid;
  wire lookup_ready;
  wire lookup_pose_version;
  wire [REGION_ID_W-1:0] lookup_region_id;
  wire lookup_rsp_valid;
  wire lookup_rsp_ready;
  wire lookup_rsp_found;
  wire signed [MATRIX_W-1:0] lookup_rsp_m00;
  wire signed [MATRIX_W-1:0] lookup_rsp_m01;
  wire signed [MATRIX_W-1:0] lookup_rsp_m10;
  wire signed [MATRIX_W-1:0] lookup_rsp_m11;
  wire signed [OFFSET_W-1:0] lookup_rsp_tx;
  wire signed [OFFSET_W-1:0] lookup_rsp_ty;

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
  wire [TIMESTAMP_W-1:0] timestamp_out;
  wire signed [RESULT_W-1:0] world_x_out;
  wire signed [RESULT_W-1:0] world_y_out;
  wire terminal_retire;
  wire terminal_retire_pose_version;

  wire [17:0] outstanding0;
  wire [17:0] outstanding1;
  wire [1:0] pose_idle;
  wire [1:0] pose_overwrite_ready;
  wire pose_accounting_error;
  wire input_fire = event_valid_in && event_ready_in;
  wire [1:0] accept_count = input_fire ? 2'd1 : 2'd0;
  wire [1:0] retire_count0 =
    (terminal_retire && !terminal_retire_pose_version) ? 2'd1 : 2'd0;
  wire [1:0] retire_count1 =
    (terminal_retire && terminal_retire_pose_version) ? 2'd1 : 2'd0;

  integer errors;
  integer cycle_count;
  integer expected_count;
  integer accepted_count;
  integer retired_count;
  integer output_count;
  integer quiet_output_count;
  integer wait_cycles;
  integer last_accept_cycle;
  integer max_measured_ii;
  reg measure_ii;

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

  reg [REGION_ID_W-1:0] stalled_region;
  reg [SENSOR_W-1:0] stalled_sensor_x;
  reg [SENSOR_W-1:0] stalled_sensor_y;
  reg stalled_polarity;
  reg stalled_pose;
  reg [TIMESTAMP_W-1:0] stalled_timestamp;
  reg stalled_found;
  reg stalled_range;
  reg signed [RESULT_W-1:0] stalled_world_x;
  reg signed [RESULT_W-1:0] stalled_world_y;
  reg signed [MATRIX_W-1:0] stalled_lookup_m00;
  reg signed [OFFSET_W-1:0] stalled_lookup_tx;

  affine_region_pose_loader #(
    .REGION_COLS(REGION_COLS), .REGION_ROWS(REGION_ROWS),
    .REGION_X_W(1), .REGION_Y_W(1), .POSE_W(POSE_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W)
  ) u_loader (
    .clk(clk), .rst(rst),
    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_op(cfg_op),
    .cfg_region_x(cfg_region_x), .cfg_region_y(cfg_region_y),
    .cfg_pose_version(cfg_pose_version),
    .cfg_m00(cfg_m00), .cfg_m01(cfg_m01),
    .cfg_m10(cfg_m10), .cfg_m11(cfg_m11),
    .cfg_tx(cfg_tx), .cfg_ty(cfg_ty),
    .region_wr_req(region_wr_req),
    .region_wr_x(region_wr_x), .region_wr_y(region_wr_y),
    .region_wr_pose_version(region_wr_pose_version),
    .region_wr_m00(region_wr_m00), .region_wr_m01(region_wr_m01),
    .region_wr_m10(region_wr_m10), .region_wr_m11(region_wr_m11),
    .region_wr_tx(region_wr_tx), .region_wr_ty(region_wr_ty),
    .region_wr_ready(region_wr_ready),
    .region_wr_commit(region_wr_commit),
    .region_pose_accounting_error(pose_accounting_error),
    .active_pose_valid(active_pose_valid),
    .active_pose_version(active_pose_version),
    .load_busy(load_busy), .awaiting_publish(awaiting_publish),
    .expected_region_x(), .expected_region_y(), .load_pose_version(),
    .publish_pulse(publish_pulse),
    .cfg_protocol_error(cfg_protocol_error)
  );

  affine_region_coeff_table2 #(
    .REGION_COLS(REGION_COLS), .REGION_ROWS(REGION_ROWS),
    .REGION_X_W(1), .REGION_Y_W(1), .REGION_ID_W(REGION_ID_W),
    .POSE_W(POSE_W), .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W)
  ) u_table (
    .clk(clk), .rst(rst),
    .region_wr_req(region_wr_req),
    .region_wr_x(region_wr_x), .region_wr_y(region_wr_y),
    .region_wr_pose_version(region_wr_pose_version),
    .region_wr_m00(region_wr_m00), .region_wr_m01(region_wr_m01),
    .region_wr_m10(region_wr_m10), .region_wr_m11(region_wr_m11),
    .region_wr_tx(region_wr_tx), .region_wr_ty(region_wr_ty),
    .region_wr_ready(region_wr_ready),
    .region_wr_commit(region_wr_commit),
    .pose_overwrite_ready(pose_overwrite_ready),
    .publish_pulse(publish_pulse),
    .publish_pose_version(region_wr_pose_version),
    .lookup_valid(lookup_valid), .lookup_ready(lookup_ready),
    .lookup_pose_version(lookup_pose_version),
    .lookup_region_id(lookup_region_id),
    .lookup_rsp_valid(lookup_rsp_valid),
    .lookup_rsp_ready(lookup_rsp_ready),
    .lookup_rsp_found(lookup_rsp_found),
    .lookup_rsp_m00(lookup_rsp_m00), .lookup_rsp_m01(lookup_rsp_m01),
    .lookup_rsp_m10(lookup_rsp_m10), .lookup_rsp_m11(lookup_rsp_m11),
    .lookup_rsp_tx(lookup_rsp_tx), .lookup_rsp_ty(lookup_rsp_ty)
  );

  pose_epoch_count_guard2 #(
    .COUNT_W(18), .DELTA_W(2)
  ) u_guard (
    .clk(clk), .rst(rst),
    .accept_pose_id(pose_version_in), .accept_count(accept_count),
    .retire_count0(retire_count0), .retire_count1(retire_count1),
    .outstanding0(outstanding0), .outstanding1(outstanding1),
    .idle(pose_idle), .overwrite_ready(pose_overwrite_ready),
    .accounting_error(pose_accounting_error)
  );

  region_affine_shared_lane #(
    .REGION_ID_W(REGION_ID_W), .SENSOR_W(SENSOR_W),
    .RESULT_W(RESULT_W), .MATRIX_W(MATRIX_W),
    .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W),
    .X_MIN(0), .X_MAX(255), .Y_MIN(0), .Y_MAX(255)
  ) u_lane (
    .clk(clk), .rst(rst),
    .event_valid_in(event_valid_in), .event_ready_in(event_ready_in),
    .region_id_in(region_id_in),
    .sensor_x_in(sensor_x_in), .sensor_y_in(sensor_y_in),
    .polarity_in(polarity_in), .pose_version_in(pose_version_in),
    .occurrence_timestamp_in(timestamp_in),
    .lookup_valid(lookup_valid), .lookup_ready(lookup_ready),
    .lookup_pose_version(lookup_pose_version),
    .lookup_region_id(lookup_region_id),
    .lookup_rsp_valid(lookup_rsp_valid),
    .lookup_rsp_ready(lookup_rsp_ready),
    .lookup_rsp_found(lookup_rsp_found),
    .lookup_rsp_m00(lookup_rsp_m00), .lookup_rsp_m01(lookup_rsp_m01),
    .lookup_rsp_m10(lookup_rsp_m10), .lookup_rsp_m11(lookup_rsp_m11),
    .lookup_rsp_tx(lookup_rsp_tx), .lookup_rsp_ty(lookup_rsp_ty),
    .world_valid(world_valid), .world_ready(world_ready),
    .mapped_valid(mapped_valid), .pose_found(pose_found),
    .in_range(in_range), .region_id_out(region_id_out),
    .sensor_x_out(sensor_x_out), .sensor_y_out(sensor_y_out),
    .polarity_out(polarity_out), .pose_version_out(pose_version_out),
    .occurrence_timestamp_out(timestamp_out),
    .world_x_out(world_x_out), .world_y_out(world_y_out),
    .terminal_retire(terminal_retire),
    .terminal_retire_pose_version(terminal_retire_pose_version)
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
    input integer region_x;
    input integer region_y;
    input integer pose_in;
    input integer tx_cells;
    input integer ty_cells;
    begin
      cfg_op = op_in;
      cfg_region_x = region_x;
      cfg_region_y = region_y;
      cfg_pose_version = pose_in;
      cfg_m00 = Q_ONE;
      cfg_m01 = 0;
      cfg_m10 = 0;
      cfg_m11 = Q_ONE;
      cfg_tx = tx_cells * Q_ONE;
      cfg_ty = ty_cells * Q_ONE;
      cfg_valid = 1'b1;
    end
  endtask

  task send_cfg;
    input [1:0] op_in;
    input integer region_x;
    input integer region_y;
    input integer pose_in;
    input integer tx_cells;
    input integer ty_cells;
    begin
      @(negedge clk);
      drive_cfg(op_in, region_x, region_y, pose_in, tx_cells, ty_cells);
      #1;
      while (cfg_ready !== 1'b1)
        @(negedge clk);
      @(posedge clk);
      #1;
      cfg_valid = 1'b0;
    end
  endtask

  task write_region;
    input integer pose_in;
    input integer region_id;
    input integer base_x;
    input integer base_y;
    begin
      send_cfg(CFG_WRITE, region_id & 1, region_id >> 1, pose_in,
               base_x + region_id*10, base_y + region_id*2);
    end
  endtask

  task load_complete_epoch;
    input integer pose_in;
    input integer base_x;
    input integer base_y;
    integer load_region;
    begin
      send_cfg(CFG_BEGIN, 0, 0, pose_in, 0, 0);
      for (load_region = 0; load_region < 4;
           load_region = load_region + 1)
        write_region(pose_in, load_region, base_x, base_y);
      check_condition(awaiting_publish,
                      "complete epoch must wait for publish");
      send_cfg(CFG_PUBLISH, 0, 0, pose_in, 0, 0);
    end
  endtask

  task queue_event;
    input integer region_in;
    input integer sensor_x_value;
    input integer sensor_y_value;
    input integer polarity_value;
    input integer pose_in;
    input integer timestamp_value;
    input integer found_value;
    input integer range_value;
    input integer world_x_value;
    input integer world_y_value;
    begin
      exp_region[expected_count] = region_in;
      exp_sensor_x[expected_count] = sensor_x_value;
      exp_sensor_y[expected_count] = sensor_y_value;
      exp_polarity[expected_count] = polarity_value;
      exp_pose[expected_count] = pose_in;
      exp_timestamp[expected_count] = timestamp_value;
      exp_found[expected_count] = found_value;
      exp_range[expected_count] = range_value;
      exp_world_x[expected_count] = world_x_value;
      exp_world_y[expected_count] = world_y_value;
      expected_count = expected_count + 1;
    end
  endtask

  task send_event;
    input integer region_in;
    input integer sensor_x_value;
    input integer sensor_y_value;
    input integer polarity_value;
    input integer pose_in;
    input integer timestamp_value;
    input integer found_value;
    input integer range_value;
    input integer world_x_value;
    input integer world_y_value;
    begin
      queue_event(region_in, sensor_x_value, sensor_y_value,
                  polarity_value, pose_in, timestamp_value,
                  found_value, range_value, world_x_value, world_y_value);
      @(negedge clk);
      event_valid_in = 1'b1;
      region_id_in = region_in;
      sensor_x_in = sensor_x_value;
      sensor_y_in = sensor_y_value;
      polarity_in = polarity_value;
      pose_version_in = pose_in;
      timestamp_in = timestamp_value;
      #1;
      while (event_ready_in !== 1'b1)
        @(negedge clk);
      @(posedge clk);
      #1;
      event_valid_in = 1'b0;
    end
  endtask

  task wait_for_all_outputs;
    begin
      wait_cycles = 0;
      while ((output_count != expected_count || world_valid) &&
             wait_cycles < 200) begin
        @(posedge clk);
        #1;
        wait_cycles = wait_cycles + 1;
      end
      check_condition(output_count == expected_count && !world_valid,
                      "expected events did not drain");
    end
  endtask

  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    if (!rst && input_fire) begin
      accepted_count = accepted_count + 1;
      if (measure_ii) begin
        if (last_accept_cycle >= 0 &&
            cycle_count-last_accept_cycle > max_measured_ii)
          max_measured_ii = cycle_count-last_accept_cycle;
        last_accept_cycle = cycle_count;
      end
    end

    if (!rst && terminal_retire)
      retired_count = retired_count + 1;

    if (!rst && world_valid && world_ready) begin
      if (output_count >= expected_count) begin
        fail("phantom world event");
      end else begin
        check_condition(region_id_out == exp_region[output_count],
                        "region metadata mismatch");
        check_condition(sensor_x_out == exp_sensor_x[output_count] &&
                        sensor_y_out == exp_sensor_y[output_count],
                        "sensor metadata mismatch");
        check_condition(polarity_out == exp_polarity[output_count],
                        "polarity metadata mismatch");
        check_condition(pose_version_out == exp_pose[output_count],
                        "pose metadata mismatch");
        check_condition(timestamp_out == exp_timestamp[output_count],
                        "timestamp metadata mismatch");
        check_condition(pose_found == exp_found[output_count],
                        "coefficient-found mismatch");
        check_condition(in_range == exp_range[output_count],
                        "range result mismatch");
        check_condition(mapped_valid ==
                        (exp_found[output_count] && exp_range[output_count]),
                        "mapped-valid mismatch");
        check_condition($signed(world_x_out) ==
                        exp_world_x[output_count] &&
                        $signed(world_y_out) == exp_world_y[output_count],
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
    region_id_in = 0;
    sensor_x_in = 0;
    sensor_y_in = 0;
    polarity_in = 0;
    pose_version_in = 0;
    timestamp_in = 0;
    world_ready = 1'b1;
    errors = 0;
    cycle_count = 0;
    expected_count = 0;
    accepted_count = 0;
    retired_count = 0;
    output_count = 0;
    max_measured_ii = 0;
    last_accept_cycle = -1;
    measure_ii = 1'b0;

    repeat (3) @(posedge clk);
    #1;
    check_condition(!event_ready_in && !lookup_valid && !world_valid,
                    "reset must quiesce lane");
    @(negedge clk);
    rst = 1'b0;

    // A partly written bank and a complete-but-unpublished bank are both
    // deliberately invisible.  Their events still retire and emerge once.
    send_cfg(CFG_BEGIN, 0, 0, 0, 0, 0);
    write_region(0, 0, 0, 0);
    send_event(0, 3, 2, 1, 0, 10, 0, 0, 0, 0);
    wait_for_all_outputs;
    write_region(0, 1, 0, 0);
    write_region(0, 2, 0, 0);
    write_region(0, 3, 0, 0);
    check_condition(awaiting_publish,
                    "first bank must remain hidden before publish");
    send_event(2, 4, 3, 0, 0, 11, 0, 0, 0, 0);
    wait_for_all_outputs;
    send_cfg(CFG_PUBLISH, 0, 0, 0, 0, 0);
    check_condition(active_pose_valid && active_pose_version == 0,
                    "pose0 publication failed");

    // Four distinct region translations share one lane.  Acceptance spacing
    // is measured only over this unstalled group.
    last_accept_cycle = -1;
    max_measured_ii = 0;
    measure_ii = 1'b1;
    send_event(0, 2, 3, 0, 0, 12, 1, 1, 2, 3);
    send_event(1, 2, 3, 1, 0, 13, 1, 1, 12, 5);
    send_event(2, 2, 3, 0, 0, 14, 1, 1, 22, 7);
    send_event(3, 2, 3, 1, 0, 15, 1, 1, 32, 9);
    measure_ii = 1'b0;
    wait_for_all_outputs;
    check_condition(max_measured_ii <= 8,
                    "shared lane initiation interval exceeded eight cycles");

    // Fill the affine output, then accept another lookup behind it.  Both the
    // world event and synchronous table response must remain stable.
    world_ready = 1'b0;
    send_event(1, 5, 6, 1, 0, 20, 1, 1, 15, 8);
    wait_cycles = 0;
    while (!world_valid && wait_cycles < 30) begin
      @(posedge clk);
      #1;
      wait_cycles = wait_cycles + 1;
    end
    check_condition(world_valid && !world_ready,
                    "world blocker did not reach output");
    check_condition(retired_count == accepted_count,
                    "pose must retire on affine capture before world consume");
    stalled_region = region_id_out;
    stalled_sensor_x = sensor_x_out;
    stalled_sensor_y = sensor_y_out;
    stalled_polarity = polarity_out;
    stalled_pose = pose_version_out;
    stalled_timestamp = timestamp_out;
    stalled_found = pose_found;
    stalled_range = in_range;
    stalled_world_x = world_x_out;
    stalled_world_y = world_y_out;

    send_event(2, 7, 8, 0, 0, 21, 1, 1, 27, 12);
    #1;
    check_condition(lookup_rsp_valid && !lookup_rsp_ready &&
                    !event_ready_in,
                    "lookup response did not stall behind world output");
    stalled_lookup_m00 = lookup_rsp_m00;
    stalled_lookup_tx = lookup_rsp_tx;
    region_id_in = 0;
    sensor_x_in = 0;
    sensor_y_in = 0;
    pose_version_in = 1;
    repeat (3) begin
      @(posedge clk);
      #1;
      check_condition(world_valid && region_id_out == stalled_region &&
                      sensor_x_out == stalled_sensor_x &&
                      sensor_y_out == stalled_sensor_y &&
                      polarity_out == stalled_polarity &&
                      pose_version_out == stalled_pose &&
                      timestamp_out == stalled_timestamp &&
                      pose_found == stalled_found &&
                      in_range == stalled_range &&
                      world_x_out == stalled_world_x &&
                      world_y_out == stalled_world_y,
                      "world payload changed while stalled");
      check_condition(lookup_rsp_valid && !lookup_rsp_ready &&
                      lookup_rsp_m00 == stalled_lookup_m00 &&
                      lookup_rsp_tx == stalled_lookup_tx &&
                      u_lane.held_region_id == 2 &&
                      u_lane.held_sensor_x == 7 &&
                      u_lane.held_sensor_y == 8 &&
                      !terminal_retire,
                      "lookup/event payload changed while stalled");
    end
    @(negedge clk);
    world_ready = 1'b1;
    #1;
    check_condition(terminal_retire &&
                    terminal_retire_pose_version == 0,
                    "lookup release did not retire captured pose0 event");
    wait_for_all_outputs;

    // Publish the other epoch, then hold an old-pose lookup behind a pose1
    // world event.  A pose0 rewrite cannot start until lookup capture; ready
    // rises only after the guard applies that retire on the following edge.
    load_complete_epoch(1, 100, 40);
    check_condition(active_pose_version == 1,
                    "pose1 publication failed");
    world_ready = 1'b0;
    send_event(0, 1, 2, 1, 1, 30, 1, 1, 101, 42);
    wait_cycles = 0;
    while (!world_valid && wait_cycles < 30) begin
      @(posedge clk);
      #1;
      wait_cycles = wait_cycles + 1;
    end
    check_condition(world_valid, "pose1 blocker did not reach output");
    send_event(3, 4, 5, 0, 0, 31, 1, 1, 34, 11);
    check_condition(lookup_rsp_valid && !lookup_rsp_ready &&
                    outstanding0 == 1,
                    "accepted old-pose event did not remain outstanding");

    send_cfg(CFG_BEGIN, 0, 0, 0, 0, 0);
    @(negedge clk);
    drive_cfg(CFG_WRITE, 0, 0, 0, 200, 80);
    #1;
    check_condition(!cfg_ready && !region_wr_req &&
                    !pose_overwrite_ready[0],
                    "old slot rewrite was not blocked by accepted event");
    repeat (2) begin
      @(posedge clk);
      #1;
      check_condition(!cfg_ready && lookup_rsp_valid &&
                      !terminal_retire && outstanding0 == 1,
                      "blocked old-slot rewrite advanced before capture");
    end

    @(negedge clk);
    world_ready = 1'b1;
    #1;
    check_condition(terminal_retire &&
                    terminal_retire_pose_version == 0 &&
                    !cfg_ready && !pose_overwrite_ready[0],
                    "rewrite became ready on retire edge instead of next edge");
    @(posedge clk);
    #1;
    check_condition(outstanding0 == 0 && pose_overwrite_ready[0] &&
                    cfg_ready && region_wr_req && region_wr_commit,
                    "rewrite did not become ready after coefficient capture");
    @(posedge clk);
    #1;
    cfg_valid = 1'b0;
    check_condition(u_loader.expected_region_x == 1 &&
                    u_loader.expected_region_y == 0,
                    "released rewrite did not commit exactly once");

    write_region(0, 1, 200, 80);
    write_region(0, 2, 200, 80);
    write_region(0, 3, 200, 80);
    send_cfg(CFG_PUBLISH, 0, 0, 0, 0, 0);
    check_condition(active_pose_version == 0,
                    "reloaded pose0 publication failed");
    wait_for_all_outputs;

    send_event(3, 5, 6, 1, 0, 40, 1, 1, 235, 92);
    // Found but outside the configured world window: preserve diagnostics,
    // mark the event unmapped, and still conserve it.
    send_event(3, 63, 63, 0, 0, 41, 1, 0, 293, 149);
    wait_for_all_outputs;

    quiet_output_count = output_count;
    repeat (8) begin
      @(posedge clk);
      #1;
      check_condition(!world_valid && !terminal_retire,
                      "phantom event appeared after drain");
    end
    check_condition(output_count == quiet_output_count,
                    "output count changed after drain");
    check_condition(expected_count == accepted_count &&
                    accepted_count == retired_count &&
                    retired_count == output_count,
                    "accept/retire/output conservation mismatch");
    check_condition(outstanding0 == 0 && outstanding1 == 0 &&
                    pose_idle == 2'b11,
                    "pose references did not drain");
    check_condition(!pose_accounting_error && !cfg_protocol_error &&
                    !load_busy,
                    "loader or pose guard reported an error");

    if (errors == 0) begin
      $display("REGION_AFFINE_SHARED_LANE_PASS events=%0d max_ii=%0d",
               output_count, max_measured_ii);
      $finish;
    end else begin
      $fatal(1, "REGION_AFFINE_SHARED_LANE_FAIL errors=%0d", errors);
    end
  end

  initial begin
    #200000;
    $fatal(1, "REGION_AFFINE_SHARED_LANE_TIMEOUT");
  end
endmodule
