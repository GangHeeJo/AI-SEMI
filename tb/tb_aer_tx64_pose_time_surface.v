`timescale 1ns/1ps

module tb_aer_tx64_pose_time_surface;
  localparam integer POSE_W = 4;
  localparam integer SENSOR_W = 5;
  localparam integer COORD_W = 16;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer FRAC_W = 14;
  localparam integer TIMESTAMP_W = 16;
  localparam integer FIFO_DEPTH = 32;
  localparam integer GUARD_COUNT_W = 10;
  localparam integer GRID_W = 16;
  localparam integer GRID_H = 16;
  localparam integer CELLS = GRID_W * GRID_H;
  localparam integer POSE_IDS = (1 << POSE_W);
  localparam integer MAX_RECORDS = 12000;
  localparam integer Q = (1 << FRAC_W);
  localparam integer HALF = (1 << (FRAC_W-1));

  reg clk = 1'b0;
  reg rst;
  reg [63:0] arrival;
  reg [63:0] polarity_in;
  reg [POSE_W-1:0] occurrence_pose_version;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp;
  wire [63:0] aer_overrun;
  wire [31:0] tile_fifo_overflow;

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

  reg [SENSOR_W-1:0] base_sensor_origin_x;
  reg [SENSOR_W-1:0] base_sensor_origin_y;
  wire world_event_valid;
  wire world_event_ready;
  wire world_mapped_valid;
  wire world_pose_found;
  wire world_in_range;
  wire [SENSOR_W-1:0] world_sensor_x;
  wire [SENSOR_W-1:0] world_sensor_y;
  wire [1:0] world_tile_id;
  wire world_polarity;
  wire [POSE_W-1:0] world_pose_version;
  wire [TIMESTAMP_W-1:0] world_occurrence_timestamp;
  wire signed [COORD_W-1:0] world_x;
  wire signed [COORD_W-1:0] world_y;

  wire surface_update_applied;
  wire surface_equal_time_merged;
  wire surface_stale_ignored;
  wire surface_range_error;
  reg [$clog2(GRID_W)-1:0] read_x;
  reg [$clog2(GRID_H)-1:0] read_y;
  wire read_valid;
  wire [TIMESTAMP_W-1:0] read_timestamp;
  wire [1:0] read_polarity_seen;

  aer_tx64_pose_time_surface #(
    .POSE_W(POSE_W), .SENSOR_W(SENSOR_W), .COORD_W(COORD_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .TIMESTAMP_W(TIMESTAMP_W), .FIFO_DEPTH(FIFO_DEPTH),
    .GUARD_COUNT_W(GUARD_COUNT_W), .GRID_W(GRID_W), .GRID_H(GRID_H)
  ) dut (
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in),
    .occurrence_pose_version(occurrence_pose_version),
    .occurrence_timestamp(occurrence_timestamp),
    .aer_overrun(aer_overrun),
    .tile_fifo_overflow(tile_fifo_overflow),
    .pose_wr_req(pose_wr_req), .pose_wr_id(pose_wr_id),
    .pose_wr_m00(pose_wr_m00), .pose_wr_m01(pose_wr_m01),
    .pose_wr_m10(pose_wr_m10), .pose_wr_m11(pose_wr_m11),
    .pose_wr_tx(pose_wr_tx), .pose_wr_ty(pose_wr_ty),
    .pose_wr_ready(pose_wr_ready), .pose_wr_commit(pose_wr_commit),
    .pose_wr_rejected(pose_wr_rejected),
    .pose_accounting_error(pose_accounting_error),
    .base_sensor_origin_x(base_sensor_origin_x),
    .base_sensor_origin_y(base_sensor_origin_y),
    .world_event_valid(world_event_valid),
    .world_event_ready(world_event_ready),
    .world_mapped_valid(world_mapped_valid),
    .world_pose_found(world_pose_found),
    .world_in_range(world_in_range),
    .world_sensor_x(world_sensor_x), .world_sensor_y(world_sensor_y),
    .world_tile_id(world_tile_id), .world_polarity(world_polarity),
    .world_pose_version(world_pose_version),
    .world_occurrence_timestamp(world_occurrence_timestamp),
    .world_x(world_x), .world_y(world_y),
    .surface_update_applied(surface_update_applied),
    .surface_equal_time_merged(surface_equal_time_merged),
    .surface_stale_ignored(surface_stale_ignored),
    .surface_range_error(surface_range_error),
    .read_x(read_x), .read_y(read_y), .read_valid(read_valid),
    .read_timestamp(read_timestamp),
    .read_polarity_seen(read_polarity_seen)
  );

  always #5 clk = ~clk;

  // Accepted-event oracle. State 1 waits in AER/FIFO, state 2 has crossed
  // RR->transform, state 3 was dropped by a tile FIFO, state 4 was consumed.
  integer rec_state [0:MAX_RECORDS-1];
  integer rec_tile [0:MAX_RECORDS-1];
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

  integer surface_valid_model [0:CELLS-1];
  integer surface_time_model [0:CELLS-1];
  integer surface_pol_model [0:CELLS-1];

  integer record_count;
  integer cycle_count;
  integer generated_count;
  integer aer_accepted_count;
  integer aer_drop_count;
  integer fifo_drop_count;
  integer rr_retire_count;
  integer delivered_count;
  integer mapped_output_count;
  integer nonmapped_output_count;
  integer surface_update_count;
  integer surface_equal_count;
  integer surface_stale_count;
  integer surface_range_count;
  integer missing_output_count;
  integer out_of_range_output_count;
  integer busy_reject_count;
  integer final_commit_count;
  integer error_count;
  integer aer_drop_by_tile [0:3];
  integer fifo_drop_by_tile [0:3];

  integer expected_surface_update;
  integer expected_surface_equal;
  integer expected_surface_stale;
  integer expected_surface_range;
  integer commit_expected;

  integer newer_target_seen;
  integer older_target_seen;
  integer equal_a_first_pol;
  integer equal_a_count;
  integer equal_b_first_pol;
  integer equal_b_count;

  integer i;
  integer x_scan;
  integer y_scan;
  integer source;
  integer timeout_count;
  integer baseline_delivered;
  integer baseline_update_count;
  integer baseline_equal_count;
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
    input integer wanted_tile;
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
            && rec_tile[scan] == wanted_tile
            && rec_sx[scan] == wanted_sx
            && rec_sy[scan] == wanted_sy
            && rec_pol[scan] == wanted_pol
            && rec_pose[scan] == wanted_pose
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
        range_out = (wx_out >= 0) && (wx_out < GRID_W)
                 && (wy_out >= 0) && (wy_out < GRID_H);
        mapped_out = range_out;
      end
    end
  endtask

  task automatic add_accepted_record;
    input integer source_in;
    integer tile_in;
    integer local_in;
    begin
      if (record_count >= MAX_RECORDS)
        $fatal(1, "record table capacity exceeded");
      tile_in = source_in / 16;
      local_in = source_in % 16;
      rec_state[record_count] = 1;
      rec_tile[record_count] = tile_in;
      rec_sx[record_count] = base_sensor_origin_x
                           + ((tile_in & 1) * 4) + (local_in & 3);
      rec_sy[record_count] = base_sensor_origin_y
                           + (((tile_in >> 1) & 1) * 4) + (local_in >> 2);
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

  task automatic model_surface_accept;
    integer addr;
    integer incoming_pol;
    begin
      expected_surface_update = 0;
      expected_surface_equal = 0;
      expected_surface_stale = 0;
      expected_surface_range = 0;
      if (world_event_valid && world_mapped_valid) begin
        if ($signed(world_x) < 0 || $signed(world_x) >= GRID_W
            || $signed(world_y) < 0 || $signed(world_y) >= GRID_H) begin
          expected_surface_range = 1;
        end else begin
          addr = $signed(world_y) * GRID_W + $signed(world_x);
          incoming_pol = world_polarity ? 2'b10 : 2'b01;
          if (!surface_valid_model[addr]
              || world_occurrence_timestamp > surface_time_model[addr]) begin
            surface_valid_model[addr] = 1;
            surface_time_model[addr] = world_occurrence_timestamp;
            surface_pol_model[addr] = incoming_pol;
            expected_surface_update = 1;
          end else if (world_occurrence_timestamp
                       == surface_time_model[addr]) begin
            surface_pol_model[addr] = surface_pol_model[addr] | incoming_pol;
            expected_surface_update = 1;
            expected_surface_equal = 1;
          end else begin
            expected_surface_stale = 1;
          end
        end
      end
    end
  endtask

  task automatic check_world_output;
    integer idx;
    begin
      model_surface_accept;
      if (world_event_valid) begin
        if (world_event_ready !== 1'b1)
          fail("time surface did not remain ready outside reset");
        idx = find_record(2, world_tile_id, world_sensor_x, world_sensor_y,
                          world_polarity, world_pose_version,
                          world_occurrence_timestamp);
        if (idx < 0) begin
          fail("world stream has no matching RR-retired event");
        end else begin
          if (world_pose_found !== rec_found[idx][0]
              || world_in_range !== rec_range[idx][0]
              || world_mapped_valid !== rec_mapped[idx][0]
              || $signed(world_x) != rec_wx[idx]
              || $signed(world_y) != rec_wy[idx])
            fail("world-stream transform or validity mismatch");
          rec_state[idx] = 4;
          delivered_count = delivered_count + 1;
          if (world_mapped_valid)
            mapped_output_count = mapped_output_count + 1;
          else
            nonmapped_output_count = nonmapped_output_count + 1;
          if (!world_pose_found)
            missing_output_count = missing_output_count + 1;
          else if (!world_in_range)
            out_of_range_output_count = out_of_range_output_count + 1;

          if ($signed(world_x) == 6 && $signed(world_y) == 6) begin
            if (world_occurrence_timestamp == 200) begin
              if (older_target_seen)
                fail("newer target event retired after the older event");
              newer_target_seen = 1;
            end else if (world_occurrence_timestamp == 100) begin
              if (!newer_target_seen)
                fail("older target event retired before the newer event");
              older_target_seen = 1;
              if (!expected_surface_stale)
                fail("late older target event was not classified stale");
            end
          end

          if ($signed(world_x) == 7 && $signed(world_y) == 7
              && world_occurrence_timestamp == 300) begin
            if (equal_a_count == 0)
              equal_a_first_pol = world_polarity;
            equal_a_count = equal_a_count + 1;
          end
          if ($signed(world_x) == 8 && $signed(world_y) == 8
              && world_occurrence_timestamp == 301) begin
            if (equal_b_count == 0)
              equal_b_first_pol = world_polarity;
            equal_b_count = equal_b_count + 1;
          end
        end
      end else if (world_mapped_valid) begin
        fail("mapped_valid asserted without a world event");
      end
    end
  endtask

  task automatic process_rr_retire;
    integer idx;
    integer found_value;
    integer range_value;
    integer mapped_value;
    integer wx_value;
    integer wy_value;
    begin
      if (dut.u_serial.rr_handshake) begin
        idx = find_record(1, dut.u_serial.rr_source,
                          dut.u_serial.rr_sensor_x,
                          dut.u_serial.rr_sensor_y,
                          dut.u_serial.rr_polarity,
                          dut.u_serial.rr_pose,
                          dut.u_serial.rr_time);
        if (idx < 0) begin
          fail("RR handshake has no matching accepted record");
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
        rr_retire_count = rr_retire_count + 1;
        if (guard_next[dut.u_serial.rr_pose] == 0)
          fail("pose guard underflow on RR retirement");
        else
          guard_next[dut.u_serial.rr_pose] =
            guard_next[dut.u_serial.rr_pose] - 1;
      end
    end
  endtask

  task automatic process_fifo_drops;
    integer lane;
    integer drop_tile;
    integer lane_sx;
    integer lane_sy;
    integer lane_pol;
    integer lane_pose;
    integer lane_time;
    integer idx;
    begin
      if ((tile_fifo_overflow & ~dut.u_serial.expanded_valid) != 0)
        fail("FIFO overflow asserted for an inactive expanded lane");
      for (lane = 0; lane < 32; lane = lane + 1) begin
        if (tile_fifo_overflow[lane]) begin
          drop_tile = lane / 8;
          lane_sx = dut.u_serial.expanded_x_flat[lane*SENSOR_W +: SENSOR_W];
          lane_sy = dut.u_serial.expanded_y_flat[lane*SENSOR_W +: SENSOR_W];
          lane_pol = dut.u_serial.expanded_polarity[lane];
          lane_pose = dut.u_serial.expanded_pose_flat[lane*POSE_W +: POSE_W];
          lane_time = dut.u_serial.expanded_time_flat[
            lane*TIMESTAMP_W +: TIMESTAMP_W];
          idx = find_record(1, drop_tile, lane_sx, lane_sy, lane_pol,
                            lane_pose, lane_time);
          if (idx < 0)
            fail("FIFO overflow has no matching accepted record");
          else
            rec_state[idx] = 3;
          fifo_drop_count = fifo_drop_count + 1;
          fifo_drop_by_tile[drop_tile] = fifo_drop_by_tile[drop_tile] + 1;
          if (guard_next[lane_pose] == 0)
            fail("pose guard underflow on FIFO-drop retirement");
          else
            guard_next[lane_pose] = guard_next[lane_pose] - 1;
        end
      end
    end
  endtask

  task automatic process_arrivals;
    begin
      if ((aer_overrun & ~arrival) != 0)
        fail("AER overrun asserted without an arrival");
      for (source = 0; source < 64; source = source + 1) begin
        if (arrival[source]) begin
          generated_count = generated_count + 1;
          if (aer_overrun[source]) begin
            aer_drop_count = aer_drop_count + 1;
            aer_drop_by_tile[source/16] = aer_drop_by_tile[source/16] + 1;
          end else begin
            aer_accepted_count = aer_accepted_count + 1;
            add_accepted_record(source);
            guard_next[occurrence_pose_version] =
              guard_next[occurrence_pose_version] + 1;
          end
        end
      end
    end
  endtask

  task automatic sample_before_edge;
    integer pose_id;
    begin
      if (world_event_ready !== 1'b1)
        fail("closed time-surface consumer is not ready");

      commit_expected = pose_wr_req && (guard_model[pose_wr_id] == 0);
      if (pose_wr_ready !== (guard_model[pose_wr_id] == 0)
          || pose_wr_commit !== commit_expected[0]
          || pose_wr_rejected !== (pose_wr_req && !commit_expected))
        fail("pose write guard decision mismatch");
      if (pose_wr_rejected)
        busy_reject_count = busy_reject_count + 1;

      for (pose_id = 0; pose_id < POSE_IDS; pose_id = pose_id + 1)
        guard_next[pose_id] = guard_model[pose_id];

      check_world_output;
      process_rr_retire;
      process_fifo_drops;
      process_arrivals;
    end
  endtask

  task automatic update_after_edge;
    integer pose_id;
    begin
      if (surface_update_applied !== expected_surface_update[0]
          || surface_equal_time_merged !== expected_surface_equal[0]
          || surface_stale_ignored !== expected_surface_stale[0]
          || surface_range_error !== expected_surface_range[0])
        fail("time-surface update/equal/stale/range status mismatch");
      if (surface_update_applied)
        surface_update_count = surface_update_count + 1;
      if (surface_equal_time_merged)
        surface_equal_count = surface_equal_count + 1;
      if (surface_stale_ignored)
        surface_stale_count = surface_stale_count + 1;
      if (surface_range_error)
        surface_range_count = surface_range_count + 1;

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
        if (dut.u_serial.u_pose_guard.outstanding[pose_id]
            !== guard_model[pose_id][GUARD_COUNT_W-1:0])
          fail("pose guard outstanding count mismatch");
      end
      if (pose_accounting_error)
        fail("pose guard accounting_error asserted");
    end
  endtask

  task automatic step;
    input [63:0] arrivals_in;
    input [63:0] polarities_in;
    input integer pose_in;
    input integer timestamp_in;
    input integer write_req_in;
    begin
      @(negedge clk);
      arrival = arrivals_in;
      polarity_in = polarities_in;
      occurrence_pose_version = pose_in;
      occurrence_timestamp = timestamp_in;
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
      step(64'd0, 64'd0, 0, 0, 1);
      if (!model_pose_valid[id])
        fail("idle pose write did not commit");
    end
  endtask

  task automatic drain_to_delivery_count;
    input integer target;
    begin
      timeout_count = 0;
      while (delivered_count < target && timeout_count < 10000) begin
        step(64'd0, 64'd0, 0, 0, 0);
        timeout_count = timeout_count + 1;
      end
      if (delivered_count != target)
        fail("timed out waiting for a delivery target");
    end
  endtask

  task automatic drain_all;
    begin
      timeout_count = 0;
      while (unresolved_records() != 0 && timeout_count < 15000) begin
        step(64'd0, 64'd0, 0, 0, 0);
        timeout_count = timeout_count + 1;
      end
      if (unresolved_records() != 0)
        fail("timed out draining accepted records");
      repeat (3)
        step(64'd0, 64'd0, 0, 0, 0);
    end
  endtask

  task automatic check_cell;
    input integer x;
    input integer y;
    integer addr;
    begin
      addr = y * GRID_W + x;
      read_x = x;
      read_y = y;
      #1;
      if (read_valid !== surface_valid_model[addr][0]
          || read_timestamp !== (surface_valid_model[addr]
                                ? surface_time_model[addr] : 0)
          || read_polarity_seen !== (surface_valid_model[addr]
                                   ? surface_pol_model[addr] : 0))
        fail("external time-surface readback mismatch");
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
    base_sensor_origin_x = 0;
    base_sensor_origin_y = 0;
    read_x = 0;
    read_y = 0;
    record_count = 0;
    cycle_count = 0;
    generated_count = 0;
    aer_accepted_count = 0;
    aer_drop_count = 0;
    fifo_drop_count = 0;
    rr_retire_count = 0;
    delivered_count = 0;
    mapped_output_count = 0;
    nonmapped_output_count = 0;
    surface_update_count = 0;
    surface_equal_count = 0;
    surface_stale_count = 0;
    surface_range_count = 0;
    missing_output_count = 0;
    out_of_range_output_count = 0;
    busy_reject_count = 0;
    final_commit_count = 0;
    error_count = 0;
    expected_surface_update = 0;
    expected_surface_equal = 0;
    expected_surface_stale = 0;
    expected_surface_range = 0;
    newer_target_seen = 0;
    older_target_seen = 0;
    equal_a_first_pol = -1;
    equal_a_count = 0;
    equal_b_first_pol = -1;
    equal_b_count = 0;
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
    for (i = 0; i < CELLS; i = i + 1) begin
      surface_valid_model[i] = 0;
      surface_time_model[i] = 0;
      surface_pol_model[i] = 0;
    end
    for (i = 0; i < 4; i = i + 1) begin
      aer_drop_by_tile[i] = 0;
      fifo_drop_by_tile[i] = 0;
    end

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    // Identity, two transforms to (6,6), two transforms to (7,7), two to
    // (8,8), and one deliberately out-of-grid transform. Pose 15 is missing.
    load_pose(0, Q, 0, 0, Q, 0, 0);
    load_pose(1, Q, 0, 0, Q, 3*Q, 3*Q);  // tile0 (3,3) -> (6,6)
    load_pose(2, Q, 0, 0, Q, 2*Q, 6*Q);  // tile1 (4,0) -> (6,6)
    load_pose(3, Q, 0, 0, Q, 7*Q, 7*Q);  // tile0 (0,0) -> (7,7)
    load_pose(4, Q, 0, 0, Q, 7*Q, 3*Q);  // tile2 (0,4) -> (7,7)
    load_pose(5, Q, 0, 0, Q, 4*Q, 8*Q);  // tile1 (4,0) -> (8,8)
    load_pose(6, Q, 0, 0, Q, 4*Q, 4*Q);  // tile3 (4,4) -> (8,8)
    load_pose(7, Q, 0, 0, Q, 20*Q, 20*Q);

    // Put the older target event behind a tile0 FIFO backlog. The newer tile1
    // event then reaches the shared transform first despite occurring later.
    step(64'h0000_0000_0000_ffff, 64'h0000_0000_0000_5aa5,
         0, 10, 0);
    repeat (4)
      step(64'd0, 64'd0, 0, 0, 0);
    step(64'h0000_0000_0000_8000, 64'd0, 1, 100, 0);
    step(64'h0000_0000_0001_0000,
         64'h0000_0000_0001_0000, 2, 200, 0);
    drain_all;
    if (!newer_target_seen || !older_target_seen)
      fail("did not observe newer-before-older target retirement");
    check_cell(6, 6);
    if (!read_valid || read_timestamp != 200 || read_polarity_seen != 2'b10)
      fail("stale older event rolled target cell backward");

    // Exercise equal-time OR merge in both polarity arrival orders.
    baseline_equal_count = surface_equal_count;
    baseline_delivered = delivered_count;
    step(64'h0000_0000_0000_0001, 64'd0, 3, 300, 0);
    drain_to_delivery_count(baseline_delivered + 1);
    baseline_delivered = delivered_count;
    step(64'h0000_0001_0000_0000,
         64'h0000_0001_0000_0000, 4, 300, 0);
    drain_to_delivery_count(baseline_delivered + 1);
    check_cell(7, 7);
    if (!read_valid || read_timestamp != 300 || read_polarity_seen != 2'b11)
      fail("OFF-then-ON equal-time merge did not preserve both polarities");

    baseline_delivered = delivered_count;
    step(64'h0000_0000_0001_0000,
         64'h0000_0000_0001_0000, 5, 301, 0);
    drain_to_delivery_count(baseline_delivered + 1);
    baseline_delivered = delivered_count;
    step(64'h0001_0000_0000_0000, 64'd0, 6, 301, 0);
    drain_to_delivery_count(baseline_delivered + 1);
    check_cell(8, 8);
    if (!read_valid || read_timestamp != 301 || read_polarity_seen != 2'b11)
      fail("ON-then-OFF equal-time merge did not preserve both polarities");
    if (surface_equal_count - baseline_equal_count != 2
        || equal_a_count != 2 || equal_a_first_pol != 0
        || equal_b_count != 2 || equal_b_first_pol != 1)
      fail("equal-time merge coverage/order mismatch");

    // Missing and out-of-range transforms still retire, but neither may touch
    // the memory or emit a time-surface status pulse.
    baseline_update_count = surface_update_count;
    baseline_delivered = delivered_count;
    step(64'h8000_0000_0000_0000,
         64'h8000_0000_0000_0000, 15, 400, 0);
    step(64'h0000_0000_0001_0000,
         64'h0000_0000_0001_0000, 7, 401, 0);
    drain_to_delivery_count(baseline_delivered + 2);
    if (surface_update_count != baseline_update_count)
      fail("missing/out-of-range event changed the time surface");
    if (missing_output_count == 0 || out_of_range_output_count == 0)
      fail("missing/out-of-range output coverage was not reached");
    for (y_scan = 0; y_scan < GRID_H; y_scan = y_scan + 1)
      for (x_scan = 0; x_scan < GRID_W; x_scan = x_scan + 1)
        check_cell(x_scan, y_scan);

    // Sustained full-frame traffic forces both drop points. A pose rewrite on
    // the second cycle must be rejected while accepted pose-0 events remain.
    baseline_aer_drop = aer_drop_count;
    baseline_fifo_drop = fifo_drop_count;
    step(64'hffff_ffff_ffff_ffff,
         64'h5555_5555_5555_5555, 0, 1000, 0);
    set_pose_write(0, Q, 0, 0, Q, 0, 0);
    step(64'hffff_ffff_ffff_ffff,
         64'haaaa_aaaa_aaaa_aaaa, 0, 1001, 1);
    for (i = 2; i < 24; i = i + 1)
      step(64'hffff_ffff_ffff_ffff,
           i[0] ? 64'haaaa_aaaa_aaaa_aaaa : 64'h5555_5555_5555_5555,
           0, 1000+i, 0);
    if (busy_reject_count == 0)
      fail("busy pose write was not rejected");
    if (aer_drop_count == baseline_aer_drop)
      fail("stress phase did not produce AER drops");
    if (fifo_drop_count == baseline_fifo_drop)
      fail("stress phase did not produce FIFO drops");
    for (i = 0; i < 4; i = i + 1) begin
      if (aer_drop_by_tile[i] == 0)
        fail("one tile never exercised AER drop accounting");
      if (fifo_drop_by_tile[i] == 0)
        fail("one tile never exercised FIFO drop accounting");
    end

    drain_all;
    set_pose_write(0, Q, 0, 0, Q, 0, 0);
    step(64'd0, 64'd0, 0, 0, 1);
    if (!commit_expected)
      fail("pose write remained blocked after complete guard drain");
    else
      final_commit_count = final_commit_count + 1;

    for (y_scan = 0; y_scan < GRID_H; y_scan = y_scan + 1)
      for (x_scan = 0; x_scan < GRID_W; x_scan = x_scan + 1)
        check_cell(x_scan, y_scan);

    if (generated_count != aer_accepted_count + aer_drop_count)
      fail("generated != AER-accepted + AER-dropped");
    if (aer_accepted_count != fifo_drop_count + rr_retire_count)
      fail("AER-accepted != FIFO-dropped + RR-retired");
    if (rr_retire_count != delivered_count)
      fail("RR-retired != time-surface-consumed after drain");
    if (delivered_count != mapped_output_count + nonmapped_output_count)
      fail("world output validity accounting mismatch");
    if (mapped_output_count != surface_update_count
                               + surface_stale_count
                               + surface_range_count)
      fail("mapped output != update + stale + surface-range outcomes");
    if (surface_range_count != 0)
      fail("matched transform/grid bounds still produced a surface range error");
    if (unresolved_records() != 0 || guard_total() != 0)
      fail("event oracle or pose guard did not fully drain");
    if (final_commit_count != 1)
      fail("final post-drain pose write did not commit exactly once");

    $display("TX64_SURFACE_COUNTS generated=%0d aer_accepted=%0d aer_drop=%0d fifo_drop=%0d rr=%0d delivered=%0d mapped=%0d nonmapped=%0d",
             generated_count, aer_accepted_count, aer_drop_count,
             fifo_drop_count, rr_retire_count, delivered_count,
             mapped_output_count, nonmapped_output_count);
    $display("TX64_SURFACE_STATUS update=%0d equal=%0d stale=%0d range=%0d missing=%0d out_of_range=%0d busy_reject=%0d",
             surface_update_count, surface_equal_count,
             surface_stale_count, surface_range_count,
             missing_output_count, out_of_range_output_count,
             busy_reject_count);
    if (error_count == 0) begin
      $display("AER_TX64_POSE_TIME_SURFACE_PASS");
      $finish;
    end else begin
      $fatal(1, "AER_TX64_POSE_TIME_SURFACE_FAIL errors=%0d", error_count);
    end
  end
endmodule
