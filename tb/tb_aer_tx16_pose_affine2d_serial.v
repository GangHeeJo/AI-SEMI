`timescale 1ns/1ps

module tb_aer_tx16_pose_affine2d_serial;
  localparam integer POSE_W = 3;
  localparam integer SENSOR_W = 6;
  localparam integer RESULT_W = 16;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer FRAC_W = 14;
  localparam integer TIMESTAMP_W = 16;
  localparam integer FIFO_DEPTH = 16;
  localparam integer GUARD_COUNT_W = 8;
  localparam integer POSE_IDS = (1 << POSE_W);
  localparam integer MAX_RECORDS = 4000;
  localparam integer Q = (1 << FRAC_W);
  localparam integer HALF = (1 << (FRAC_W-1));
  localparam integer BASE_X = 3;
  localparam integer BASE_Y = 5;

  reg clk = 1'b0;
  reg rst;
  reg [15:0] arrival;
  reg [15:0] polarity_in;
  reg [POSE_W-1:0] occurrence_pose_version;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp;
  wire [15:0] aer_overrun;
  wire [7:0] fifo_overflow;

  reg pose_wr_req;
  reg [POSE_W-1:0] pose_wr_id;
  reg signed [MATRIX_W-1:0] pose_wr_m00;
  reg signed [MATRIX_W-1:0] pose_wr_m01;
  reg signed [MATRIX_W-1:0] pose_wr_m10;
  reg signed [MATRIX_W-1:0] pose_wr_m11;
  reg signed [OFFSET_W-1:0] pose_wr_tx;
  reg signed [OFFSET_W-1:0] pose_wr_ty;
  wire pose_wr_ready;
  wire pose_wr_commit;
  wire pose_wr_rejected;
  wire pose_accounting_error;

  reg [SENSOR_W-1:0] tile_origin_x;
  reg [SENSOR_W-1:0] tile_origin_y;
  wire world_valid;
  reg world_ready;
  wire mapped_valid;
  wire pose_found;
  wire in_range;
  wire [SENSOR_W-1:0] sensor_x;
  wire [SENSOR_W-1:0] sensor_y;
  wire polarity;
  wire [POSE_W-1:0] pose_version;
  wire [TIMESTAMP_W-1:0] occurrence_timestamp_out;
  wire signed [RESULT_W-1:0] world_x;
  wire signed [RESULT_W-1:0] world_y;

  aer_tx16_pose_affine2d_serial #(
    .POSE_W(POSE_W), .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .TIMESTAMP_W(TIMESTAMP_W), .FIFO_DEPTH(FIFO_DEPTH),
    .GUARD_COUNT_W(GUARD_COUNT_W),
    .X_MIN(0), .X_MAX(63), .Y_MIN(0), .Y_MAX(63)
  ) dut (
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in),
    .occurrence_pose_version(occurrence_pose_version),
    .occurrence_timestamp(occurrence_timestamp),
    .aer_overrun(aer_overrun), .fifo_overflow(fifo_overflow),
    .pose_wr_req(pose_wr_req), .pose_wr_id(pose_wr_id),
    .pose_wr_m00(pose_wr_m00), .pose_wr_m01(pose_wr_m01),
    .pose_wr_m10(pose_wr_m10), .pose_wr_m11(pose_wr_m11),
    .pose_wr_tx(pose_wr_tx), .pose_wr_ty(pose_wr_ty),
    .pose_wr_ready(pose_wr_ready), .pose_wr_commit(pose_wr_commit),
    .pose_wr_rejected(pose_wr_rejected),
    .pose_accounting_error(pose_accounting_error),
    .tile_origin_x(tile_origin_x), .tile_origin_y(tile_origin_y),
    .world_valid(world_valid), .world_ready(world_ready),
    .mapped_valid(mapped_valid), .pose_found(pose_found),
    .in_range(in_range), .sensor_x(sensor_x), .sensor_y(sensor_y),
    .polarity(polarity), .pose_version(pose_version),
    .occurrence_timestamp_out(occurrence_timestamp_out),
    .world_x(world_x), .world_y(world_y)
  );

  always #5 clk = ~clk;

  // Record states: 1=in AER/FIFO, 2=in transform/output, 3=FIFO drop,
  // 4=world-stream delivery. AER overruns never enter this table.
  integer rec_state [0:MAX_RECORDS-1];
  integer rec_sx [0:MAX_RECORDS-1];
  integer rec_sy [0:MAX_RECORDS-1];
  integer rec_pol [0:MAX_RECORDS-1];
  integer rec_pose [0:MAX_RECORDS-1];
  integer rec_time [0:MAX_RECORDS-1];
  integer rec_found [0:MAX_RECORDS-1];
  integer rec_range [0:MAX_RECORDS-1];
  integer rec_mapped [0:MAX_RECORDS-1];
  integer rec_wx [0:MAX_RECORDS-1];
  integer rec_wy [0:MAX_RECORDS-1];

  integer model_pose_valid [0:POSE_IDS-1];
  integer model_m00 [0:POSE_IDS-1];
  integer model_m01 [0:POSE_IDS-1];
  integer model_m10 [0:POSE_IDS-1];
  integer model_m11 [0:POSE_IDS-1];
  integer model_tx [0:POSE_IDS-1];
  integer model_ty [0:POSE_IDS-1];
  integer guard_model [0:POSE_IDS-1];
  integer guard_next [0:POSE_IDS-1];

  integer record_count;
  integer cycle_count;
  integer timestamp_counter;
  integer generated_count;
  integer aer_accepted_count;
  integer aer_drop_count;
  integer fifo_drop_count;
  integer transform_retire_count;
  integer delivered_count;
  integer error_count;
  integer stall_checks;
  integer busy_reject_seen;
  integer post_retire_commit_seen;
  integer missing_pose_seen;
  integer occurrence_case_time;
  integer occurrence_case_seen;
  integer mixed_pose_bitmap_seen;
  integer mixed_time_bitmap_seen;
  integer coordinate_phase;
  integer coordinate_hits [0:15];

  reg held_valid;
  reg held_mapped;
  reg held_found;
  reg held_range;
  reg [SENSOR_W-1:0] held_sx;
  reg [SENSOR_W-1:0] held_sy;
  reg held_pol;
  reg [POSE_W-1:0] held_pose;
  reg [TIMESTAMP_W-1:0] held_time;
  reg signed [RESULT_W-1:0] held_wx;
  reg signed [RESULT_W-1:0] held_wy;
  integer commit_expected;

  integer i;
  integer source;
  integer timeout_count;
  integer baseline_delivered;
  integer baseline_aer_drop;
  integer baseline_fifo_drop;

  function integer round_q14_away_from_zero;
    input integer value;
    integer magnitude;
    begin
      magnitude = (value < 0) ? -value : value;
      round_q14_away_from_zero = (magnitude + HALF) >>> FRAC_W;
      if (value < 0)
        round_q14_away_from_zero = -round_q14_away_from_zero;
    end
  endfunction

  function integer find_record;
    input integer wanted_state;
    input integer wanted_sx;
    input integer wanted_sy;
    input integer wanted_pol;
    input integer wanted_pose;
    input integer wanted_time;
    integer scan;
    begin
      find_record = -1;
      for (scan = 0; scan < record_count; scan = scan + 1) begin
        if (find_record == -1 && rec_state[scan] == wanted_state
            && rec_sx[scan] == wanted_sx && rec_sy[scan] == wanted_sy
            && rec_pol[scan] == wanted_pol && rec_pose[scan] == wanted_pose
            && rec_time[scan] == wanted_time)
          find_record = scan;
      end
    end
  endfunction

  function integer unresolved_records;
    integer scan;
    begin
      unresolved_records = 0;
      for (scan = 0; scan < record_count; scan = scan + 1)
        if (rec_state[scan] == 1 || rec_state[scan] == 2)
          unresolved_records = unresolved_records + 1;
    end
  endfunction

  function integer guard_total;
    integer scan;
    begin
      guard_total = 0;
      for (scan = 0; scan < POSE_IDS; scan = scan + 1)
        guard_total = guard_total + guard_model[scan];
    end
  endfunction

  task automatic fail;
    input [1023:0] message;
    begin
      error_count = error_count + 1;
      $display("FAIL cycle=%0d: %0s", cycle_count, message);
    end
  endtask

  task automatic model_transform;
    input integer pose_id_in;
    input integer sx_in;
    input integer sy_in;
    output integer found_out;
    output integer range_out;
    output integer mapped_out;
    output integer wx_out;
    output integer wy_out;
    integer acc_x;
    integer acc_y;
    begin
      if (!model_pose_valid[pose_id_in]) begin
        found_out = 0;
        range_out = 0;
        mapped_out = 0;
        wx_out = 0;
        wy_out = 0;
      end else begin
        found_out = 1;
        acc_x = model_m00[pose_id_in] * sx_in
              + model_m01[pose_id_in] * sy_in + model_tx[pose_id_in];
        acc_y = model_m10[pose_id_in] * sx_in
              + model_m11[pose_id_in] * sy_in + model_ty[pose_id_in];
        wx_out = round_q14_away_from_zero(acc_x);
        wy_out = round_q14_away_from_zero(acc_y);
        range_out = (wx_out >= 0) && (wx_out <= 63)
                 && (wy_out >= 0) && (wy_out <= 63);
        mapped_out = range_out;
      end
    end
  endtask

  task automatic check_held_output;
    begin
      if (held_valid) begin
        stall_checks = stall_checks + 1;
        if (world_valid !== 1'b1 || mapped_valid !== held_mapped
            || pose_found !== held_found || in_range !== held_range
            || sensor_x !== held_sx || sensor_y !== held_sy
            || polarity !== held_pol || pose_version !== held_pose
            || occurrence_timestamp_out !== held_time
            || world_x !== held_wx || world_y !== held_wy)
          fail("world output or sideband changed while stalled");
      end
    end
  endtask

  task automatic check_world_record;
    integer idx;
    integer coord_index;
    begin
      if (world_valid) begin
        idx = find_record(2, sensor_x, sensor_y, polarity,
                          pose_version, occurrence_timestamp_out);
        if (idx < 0) begin
          fail("world output has no matching transform-stage record");
        end else begin
          if (pose_found !== rec_found[idx][0]
              || in_range !== rec_range[idx][0]
              || mapped_valid !== rec_mapped[idx][0]
              || $signed(world_x) != rec_wx[idx]
              || $signed(world_y) != rec_wy[idx])
            fail("world transform result or validity metadata mismatch");

          if (world_ready) begin
            rec_state[idx] = 4;
            delivered_count = delivered_count + 1;
            if (!pose_found)
              missing_pose_seen = missing_pose_seen + 1;
            if (rec_time[idx] == occurrence_case_time) begin
              occurrence_case_seen = occurrence_case_seen + 1;
              if (rec_pose[idx] != 1 || rec_pol[idx] != 1)
                fail("directed occurrence metadata changed before output");
            end
            if (coordinate_phase) begin
              coord_index = (rec_sy[idx] - BASE_Y) * 4
                          + (rec_sx[idx] - BASE_X);
              if (coord_index < 0 || coord_index >= 16)
                fail("4x4 coordinate round-trip produced an invalid coordinate");
              else
                coordinate_hits[coord_index] = coordinate_hits[coord_index] + 1;
            end
          end
        end
      end else if (mapped_valid || pose_found || in_range) begin
        fail("mapping status asserted without world_valid");
      end
    end
  endtask

  task automatic add_accepted_record;
    input integer source_in;
    begin
      if (record_count >= MAX_RECORDS)
        $fatal(1, "record table capacity exceeded");
      rec_state[record_count] = 1;
      rec_sx[record_count] = tile_origin_x + (source_in & 3);
      rec_sy[record_count] = tile_origin_y + (source_in >> 2);
      rec_pol[record_count] = polarity_in[source_in];
      rec_pose[record_count] = occurrence_pose_version;
      rec_time[record_count] = occurrence_timestamp;
      rec_found[record_count] = 0;
      rec_range[record_count] = 0;
      rec_mapped[record_count] = 0;
      rec_wx[record_count] = 0;
      rec_wy[record_count] = 0;
      record_count = record_count + 1;
    end
  endtask

  task automatic sample_before_edge;
    integer lane;
    integer pose_id;
    integer idx;
    integer lane_sx;
    integer lane_sy;
    integer lane_pol;
    integer lane_pose;
    integer lane_time;
    integer found_value;
    integer range_value;
    integer mapped_value;
    integer wx_value;
    integer wy_value;
    integer fifo_free;
    integer accepted_lanes;
    integer active_lanes;
    integer first_pose;
    integer first_time;
    integer poses_differ;
    integer times_differ;
    reg [7:0] expected_fifo_overflow;
    begin
      check_held_output;
      check_world_record;

      if ((aer_overrun & ~arrival) != 0)
        fail("AER overrun asserted without an arrival");
      if ((fifo_overflow & ~dut.batch_valid) != 0)
        fail("FIFO overflow asserted for an inactive expanded lane");

      // Independently reproduce the FIFO's lowest-lane-first admission rule.
      expected_fifo_overflow = 8'd0;
      accepted_lanes = 0;
      fifo_free = FIFO_DEPTH - dut.u_fifo.occupancy
                + (dut.transform_accept ? 1 : 0);
      for (lane = 0; lane < 8; lane = lane + 1) begin
        if (dut.batch_valid[lane]) begin
          if (accepted_lanes < fifo_free)
            accepted_lanes = accepted_lanes + 1;
          else
            expected_fifo_overflow[lane] = 1'b1;
        end
      end
      if (fifo_overflow !== expected_fifo_overflow)
        fail("FIFO overflow mask differs from free-slot accounting");

      active_lanes = 0;
      first_pose = 0;
      first_time = 0;
      poses_differ = 0;
      times_differ = 0;
      for (lane = 0; lane < 8; lane = lane + 1) begin
        if (dut.batch_valid[lane]) begin
          lane_pose = dut.batch_pose_flat[lane*POSE_W +: POSE_W];
          lane_time = dut.batch_time_flat[lane*TIMESTAMP_W +: TIMESTAMP_W];
          if (active_lanes == 0) begin
            first_pose = lane_pose;
            first_time = lane_time;
          end else begin
            if (lane_pose != first_pose)
              poses_differ = 1;
            if (lane_time != first_time)
              times_differ = 1;
          end
          active_lanes = active_lanes + 1;
        end
      end
      if (active_lanes >= 2 && poses_differ)
        mixed_pose_bitmap_seen = mixed_pose_bitmap_seen + 1;
      if (active_lanes >= 2 && times_differ)
        mixed_time_bitmap_seen = mixed_time_bitmap_seen + 1;

      commit_expected = pose_wr_req && (guard_model[pose_wr_id] == 0);
      if (pose_wr_ready !== (guard_model[pose_wr_id] == 0)
          || pose_wr_commit !== commit_expected[0]
          || pose_wr_rejected !== (pose_wr_req && !commit_expected))
        fail("pose write ready/commit/reject decision mismatch");
      if (pose_wr_rejected)
        busy_reject_seen = busy_reject_seen + 1;
      if (pose_wr_commit && world_valid && !world_ready)
        post_retire_commit_seen = post_retire_commit_seen + 1;

      for (pose_id = 0; pose_id < POSE_IDS; pose_id = pose_id + 1)
        guard_next[pose_id] = guard_model[pose_id];

      // Transform capture is a terminal guard retirement even if the output
      // register will remain stalled for many cycles.
      if (dut.transform_accept) begin
        idx = find_record(1, dut.fifo_sensor_x, dut.fifo_sensor_y,
                          dut.fifo_polarity, dut.fifo_pose, dut.fifo_time);
        if (idx < 0) begin
          fail("transform handshake has no matching accepted event");
        end else begin
          rec_state[idx] = 2;
          model_transform(rec_pose[idx], rec_sx[idx], rec_sy[idx],
                          found_value, range_value, mapped_value,
                          wx_value, wy_value);
          rec_found[idx] = found_value;
          rec_range[idx] = range_value;
          rec_mapped[idx] = mapped_value;
          rec_wx[idx] = wx_value;
          rec_wy[idx] = wy_value;
        end
        transform_retire_count = transform_retire_count + 1;
        if (guard_next[dut.fifo_pose] == 0)
          fail("pose guard underflow at transform-input retirement");
        else
          guard_next[dut.fifo_pose] = guard_next[dut.fifo_pose] - 1;
      end

      for (lane = 0; lane < 8; lane = lane + 1) begin
        if (fifo_overflow[lane]) begin
          lane_sx = dut.batch_x_flat[lane*SENSOR_W +: SENSOR_W];
          lane_sy = dut.batch_y_flat[lane*SENSOR_W +: SENSOR_W];
          lane_pol = dut.batch_polarity[lane];
          lane_pose = dut.batch_pose_flat[lane*POSE_W +: POSE_W];
          lane_time = dut.batch_time_flat[lane*TIMESTAMP_W +: TIMESTAMP_W];
          idx = find_record(1, lane_sx, lane_sy, lane_pol,
                            lane_pose, lane_time);
          if (idx < 0)
            fail("FIFO overflow has no matching accepted event");
          else
            rec_state[idx] = 3;
          fifo_drop_count = fifo_drop_count + 1;
          if (guard_next[lane_pose] == 0)
            fail("pose guard underflow at FIFO-drop retirement");
          else
            guard_next[lane_pose] = guard_next[lane_pose] - 1;
        end
      end

      for (source = 0; source < 16; source = source + 1) begin
        if (arrival[source]) begin
          generated_count = generated_count + 1;
          if (aer_overrun[source]) begin
            aer_drop_count = aer_drop_count + 1;
          end else begin
            aer_accepted_count = aer_accepted_count + 1;
            add_accepted_record(source);
            guard_next[occurrence_pose_version] =
              guard_next[occurrence_pose_version] + 1;
          end
        end
      end

      held_valid = world_valid && !world_ready;
      held_mapped = mapped_valid;
      held_found = pose_found;
      held_range = in_range;
      held_sx = sensor_x;
      held_sy = sensor_y;
      held_pol = polarity;
      held_pose = pose_version;
      held_time = occurrence_timestamp_out;
      held_wx = world_x;
      held_wy = world_y;
    end
  endtask

  task automatic update_after_edge;
    integer pose_id;
    begin
      if (commit_expected) begin
        model_pose_valid[pose_wr_id] = 1;
        model_m00[pose_wr_id] = $signed(pose_wr_m00);
        model_m01[pose_wr_id] = $signed(pose_wr_m01);
        model_m10[pose_wr_id] = $signed(pose_wr_m10);
        model_m11[pose_wr_id] = $signed(pose_wr_m11);
        model_tx[pose_wr_id] = $signed(pose_wr_tx);
        model_ty[pose_wr_id] = $signed(pose_wr_ty);
      end
      for (pose_id = 0; pose_id < POSE_IDS; pose_id = pose_id + 1) begin
        guard_model[pose_id] = guard_next[pose_id];
        if (dut.u_pose_guard.outstanding[pose_id]
            !== guard_model[pose_id][GUARD_COUNT_W-1:0])
          fail("pose guard outstanding count mismatch");
      end
      if (pose_accounting_error)
        fail("pose guard accounting_error asserted");
    end
  endtask

  task automatic step;
    input [15:0] arrivals_in;
    input [15:0] polarities_in;
    input integer pose_in;
    input integer ready_in;
    input integer write_req_in;
    begin
      @(negedge clk);
      arrival = arrivals_in;
      polarity_in = polarities_in;
      occurrence_pose_version = pose_in;
      occurrence_timestamp = timestamp_counter;
      timestamp_counter = timestamp_counter + 1;
      world_ready = ready_in[0];
      pose_wr_req = write_req_in[0];
      #1;
      sample_before_edge;
      @(posedge clk);
      #1;
      update_after_edge;
      cycle_count = cycle_count + 1;
    end
  endtask

  task automatic set_pose_write;
    input integer id;
    input integer m00;
    input integer m01;
    input integer m10;
    input integer m11;
    input integer tx;
    input integer ty;
    begin
      pose_wr_id = id;
      pose_wr_m00 = m00;
      pose_wr_m01 = m01;
      pose_wr_m10 = m10;
      pose_wr_m11 = m11;
      pose_wr_tx = tx;
      pose_wr_ty = ty;
    end
  endtask

  task automatic load_pose;
    input integer id;
    input integer m00;
    input integer m01;
    input integer m10;
    input integer m11;
    input integer tx;
    input integer ty;
    begin
      set_pose_write(id, m00, m01, m10, m11, tx, ty);
      step(16'd0, 16'd0, 0, 1, 1);
      if (!model_pose_valid[id])
        fail("idle pose-table load did not commit");
    end
  endtask

  task automatic drain_to_delivery_count;
    input integer target;
    begin
      timeout_count = 0;
      while (delivered_count < target && timeout_count < 3000) begin
        step(16'd0, 16'd0, 0, 1, 0);
        timeout_count = timeout_count + 1;
      end
      if (delivered_count != target)
        fail("timed out waiting for target delivery count");
    end
  endtask

  task automatic drain_all;
    begin
      timeout_count = 0;
      while (unresolved_records() != 0 && timeout_count < 5000) begin
        step(16'd0, 16'd0, 0, 1, 0);
        timeout_count = timeout_count + 1;
      end
      if (unresolved_records() != 0)
        fail("timed out draining accepted records");
      repeat (3)
        step(16'd0, 16'd0, 0, 1, 0);
    end
  endtask

  initial begin
    rst = 1'b1;
    arrival = 0;
    polarity_in = 0;
    occurrence_pose_version = 0;
    occurrence_timestamp = 0;
    pose_wr_req = 0;
    pose_wr_id = 0;
    pose_wr_m00 = 0;
    pose_wr_m01 = 0;
    pose_wr_m10 = 0;
    pose_wr_m11 = 0;
    pose_wr_tx = 0;
    pose_wr_ty = 0;
    tile_origin_x = BASE_X;
    tile_origin_y = BASE_Y;
    world_ready = 0;
    record_count = 0;
    cycle_count = 0;
    timestamp_counter = 16'h0100;
    generated_count = 0;
    aer_accepted_count = 0;
    aer_drop_count = 0;
    fifo_drop_count = 0;
    transform_retire_count = 0;
    delivered_count = 0;
    error_count = 0;
    stall_checks = 0;
    busy_reject_seen = 0;
    post_retire_commit_seen = 0;
    missing_pose_seen = 0;
    occurrence_case_time = -1;
    occurrence_case_seen = 0;
    mixed_pose_bitmap_seen = 0;
    mixed_time_bitmap_seen = 0;
    coordinate_phase = 0;
    held_valid = 0;
    commit_expected = 0;
    for (i = 0; i < MAX_RECORDS; i = i + 1)
      rec_state[i] = 0;
    for (i = 0; i < POSE_IDS; i = i + 1) begin
      model_pose_valid[i] = 0;
      model_m00[i] = 0;
      model_m01[i] = 0;
      model_m10[i] = 0;
      model_m11[i] = 0;
      model_tx[i] = 0;
      model_ty[i] = 0;
      guard_model[i] = 0;
      guard_next[i] = 0;
    end
    for (i = 0; i < 16; i = i + 1)
      coordinate_hits[i] = 0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    // Identity and translation are present; pose 2 deliberately stays absent.
    load_pose(0, Q, 0, 0, Q, 0, 0);
    load_pose(1, Q, 0, 0, Q, 2*Q, 3*Q);

    // Delayed center-row service forms one bitmap with column-specific pose
    // and timestamp values, proving that serialization keeps each source tag.
    baseline_delivered = delivered_count;
    step((16'h1 << 0) | (16'h1 << 4) | (16'h1 << 8),
         16'h0110, 0, 1, 0);
    step((16'h1 << 9), 16'h0200, 1, 1, 0);
    drain_to_delivery_count(baseline_delivered + 4);
    if (mixed_pose_bitmap_seen == 0 || mixed_time_bitmap_seen == 0)
      fail("column-specific mixed pose/timestamp bitmap was not observed");

    // A complete isolated 4x4 frame must reach the K=1 stream exactly once
    // per source, with identity coordinates and no drop at either admission.
    baseline_delivered = delivered_count;
    baseline_aer_drop = aer_drop_count;
    baseline_fifo_drop = fifo_drop_count;
    coordinate_phase = 1;
    step(16'hffff, 16'ha55a, 0, 1, 0);
    drain_to_delivery_count(baseline_delivered + 16);
    coordinate_phase = 0;
    if (aer_drop_count != baseline_aer_drop
        || fifo_drop_count != baseline_fifo_drop)
      fail("isolated 4x4 round-trip unexpectedly dropped an event");
    for (i = 0; i < 16; i = i + 1)
      if (coordinate_hits[i] != 1)
        fail("4x4 round-trip did not visit every sensor coordinate once");

    // The tag is captured at occurrence. Rewrite while it is in flight must
    // reject; after transform capture it may commit while the old result is
    // still stalled, without changing that held result.
    occurrence_case_time = timestamp_counter;
    step(16'h8000, 16'h8000, 1, 0, 0);
    set_pose_write(1, Q, 0, 0, Q, 0, 0);
    step(16'd0, 16'd0, 0, 0, 1);
    if (busy_reject_seen == 0)
      fail("busy pose rewrite was not rejected");
    timeout_count = 0;
    while (!world_valid && timeout_count < 100) begin
      step(16'd0, 16'd0, 0, 0, 0);
      timeout_count = timeout_count + 1;
    end
    if (!world_valid)
      fail("directed occurrence event never reached the stalled output");
    step(16'd0, 16'd0, 0, 0, 1);
    repeat (2)
      step(16'd0, 16'd0, 0, 0, 0);
    if (post_retire_commit_seen == 0)
      fail("pose rewrite did not commit after transform-input retirement");
    baseline_delivered = delivered_count;
    drain_to_delivery_count(baseline_delivered + 1);
    if (occurrence_case_seen != 1)
      fail("occurrence pose/timestamp case was not delivered exactly once");

    // Missing pose remains a visible event with invalid mapping status.
    baseline_delivered = delivered_count;
    step(16'h0002, 16'h0002, 2, 1, 0);
    drain_to_delivery_count(baseline_delivered + 1);
    if (missing_pose_seen == 0)
      fail("missing-pose output case was not observed");

    // A blocked one-event output plus sustained sensor traffic must exercise
    // both source depth-2 overrun and the explicit eight-bit FIFO-drop mask.
    baseline_aer_drop = aer_drop_count;
    baseline_fifo_drop = fifo_drop_count;
    for (i = 0; i < 24; i = i + 1)
      step(16'hffff, i[0] ? 16'haaaa : 16'h5555, 0, 0, 0);
    repeat (8)
      step(16'd0, 16'd0, 0, 0, 0);
    if (aer_drop_count == baseline_aer_drop)
      fail("stress phase did not produce an AER overrun");
    if (fifo_drop_count == baseline_fifo_drop)
      fail("stress phase did not produce a FIFO overflow");

    drain_all;

    // All three terminal paths must balance, leaving every pose reusable.
    set_pose_write(0, Q, 0, 0, Q, 0, 0);
    step(16'd0, 16'd0, 0, 1, 1);
    if (!commit_expected)
      fail("pose write remained busy after complete drain");

    if (generated_count != aer_accepted_count + aer_drop_count)
      fail("generated != AER-accepted + AER-dropped");
    if (aer_accepted_count != fifo_drop_count + transform_retire_count)
      fail("AER-accepted != FIFO-dropped + transform-retired");
    if (transform_retire_count != delivered_count)
      fail("transform-retired != world delivered after drain");
    if (unresolved_records() != 0)
      fail("record oracle is not empty after drain");
    if (guard_total() != 0)
      fail("pose guard model is not empty after drain");
    if (dut.u_fifo.occupancy != 0)
      fail("event FIFO is not empty after drain");
    if (stall_checks == 0)
      fail("no stalled-output stability check was exercised");

    $display("TX16_SERIAL_COUNTS generated=%0d aer_accepted=%0d aer_drop=%0d fifo_drop=%0d transform_retired=%0d delivered=%0d",
             generated_count, aer_accepted_count, aer_drop_count,
             fifo_drop_count, transform_retire_count, delivered_count);
    $display("TX16_SERIAL_COVERAGE stall_checks=%0d busy_reject=%0d post_retire_commit=%0d missing_pose=%0d mixed_pose=%0d mixed_time=%0d",
             stall_checks, busy_reject_seen, post_retire_commit_seen,
             missing_pose_seen, mixed_pose_bitmap_seen, mixed_time_bitmap_seen);
    if (error_count == 0) begin
      $display("AER_TX16_POSE_AFFINE2D_SERIAL_PASS");
      $finish;
    end else begin
      $fatal(1, "AER_TX16_POSE_AFFINE2D_SERIAL_FAIL errors=%0d", error_count);
    end
  end
endmodule
