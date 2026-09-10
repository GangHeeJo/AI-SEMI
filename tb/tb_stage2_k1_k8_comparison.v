`timescale 1ns/1ps

// Same-input comparison of the M5 K=8 parallel endpoint and K=1 serialized
// endpoint. K=8 has an implicit always-ready output; only K=1 can be stalled.
module tb_stage2_k1_k8_comparison;
  localparam integer POSE_W = 3;
  localparam integer SENSOR_W = 4;
  localparam integer RESULT_W = 16;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer FRAC_W = 14;
  localparam integer TIMESTAMP_W = 16;
  localparam integer FIFO_DEPTH = 16;
  localparam integer COUNT_W = 10;
  localparam integer POSE_IDS = (1 << POSE_W);
  localparam integer MAX_RECORDS = 5000;
  localparam integer Q = (1 << FRAC_W);
  localparam integer HALF = (1 << (FRAC_W-1));
  localparam integer PROFILE_LIGHT = 0;
  localparam integer PROFILE_BURST = 1;

  reg clk = 1'b0;
  reg rst;
  reg [15:0] arrival;
  reg [15:0] polarity_in;
  reg [POSE_W-1:0] occurrence_pose_version;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp;

  reg pose_wr_req;
  reg [POSE_W-1:0] pose_wr_id;
  reg signed [MATRIX_W-1:0] pose_wr_m00;
  reg signed [MATRIX_W-1:0] pose_wr_m01;
  reg signed [MATRIX_W-1:0] pose_wr_m10;
  reg signed [MATRIX_W-1:0] pose_wr_m11;
  reg signed [OFFSET_W-1:0] pose_wr_tx;
  reg signed [OFFSET_W-1:0] pose_wr_ty;
  reg [SENSOR_W-1:0] tile_origin_x;
  reg [SENSOR_W-1:0] tile_origin_y;

  wire [15:0] k8_aer_overrun;
  wire k8_pose_wr_ready;
  wire k8_pose_wr_rejected;
  wire k8_pose_accounting_error;
  wire [7:0] k8_valid;
  wire [7:0] k8_mapped;
  wire [7:0] k8_found;
  wire [7:0] k8_range;
  wire [7:0] k8_polarity;
  wire [8*POSE_W-1:0] k8_pose_flat;
  wire [8*TIMESTAMP_W-1:0] k8_time_flat;
  wire [8*RESULT_W-1:0] k8_x_flat;
  wire [8*RESULT_W-1:0] k8_y_flat;

  aer_tx16_pose_affine2d #(
    .POSE_W(POSE_W), .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .TIMESTAMP_W(TIMESTAMP_W), .POSE_COUNT_W(COUNT_W),
    .X_MIN(0), .X_MAX(31), .Y_MIN(0), .Y_MAX(31)
  ) dut_k8 (
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in),
    .occurrence_pose_version(occurrence_pose_version),
    .occurrence_timestamp(occurrence_timestamp), .overrun(k8_aer_overrun),
    .pose_wr_en(pose_wr_req), .pose_wr_id(pose_wr_id),
    .pose_wr_m00(pose_wr_m00), .pose_wr_m01(pose_wr_m01),
    .pose_wr_m10(pose_wr_m10), .pose_wr_m11(pose_wr_m11),
    .pose_wr_tx(pose_wr_tx), .pose_wr_ty(pose_wr_ty),
    .pose_wr_ready(k8_pose_wr_ready),
    .pose_wr_rejected(k8_pose_wr_rejected),
    .pose_accounting_error(k8_pose_accounting_error),
    .tile_origin_x(tile_origin_x), .tile_origin_y(tile_origin_y),
    .event_valid_out(k8_valid), .mapped_valid_out(k8_mapped),
    .pose_found_out(k8_found), .in_range_out(k8_range),
    .polarity_out(k8_polarity), .pose_version_out_flat(k8_pose_flat),
    .occurrence_timestamp_out_flat(k8_time_flat),
    .world_x_out_flat(k8_x_flat), .world_y_out_flat(k8_y_flat)
  );

  wire [15:0] k1_aer_overrun;
  wire [7:0] k1_fifo_overflow;
  wire k1_pose_wr_ready;
  wire k1_pose_wr_commit;
  wire k1_pose_wr_rejected;
  wire k1_pose_accounting_error;
  wire k1_world_valid;
  reg k1_world_ready;
  wire k1_mapped;
  wire k1_found;
  wire k1_range;
  wire [SENSOR_W-1:0] k1_sensor_x;
  wire [SENSOR_W-1:0] k1_sensor_y;
  wire k1_polarity;
  wire [POSE_W-1:0] k1_pose;
  wire [TIMESTAMP_W-1:0] k1_time;
  wire signed [RESULT_W-1:0] k1_world_x;
  wire signed [RESULT_W-1:0] k1_world_y;

  aer_tx16_pose_affine2d_serial #(
    .POSE_W(POSE_W), .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .TIMESTAMP_W(TIMESTAMP_W), .FIFO_DEPTH(FIFO_DEPTH),
    .GUARD_COUNT_W(COUNT_W),
    .X_MIN(0), .X_MAX(31), .Y_MIN(0), .Y_MAX(31)
  ) dut_k1 (
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in),
    .occurrence_pose_version(occurrence_pose_version),
    .occurrence_timestamp(occurrence_timestamp),
    .aer_overrun(k1_aer_overrun), .fifo_overflow(k1_fifo_overflow),
    .pose_wr_req(pose_wr_req), .pose_wr_id(pose_wr_id),
    .pose_wr_m00(pose_wr_m00), .pose_wr_m01(pose_wr_m01),
    .pose_wr_m10(pose_wr_m10), .pose_wr_m11(pose_wr_m11),
    .pose_wr_tx(pose_wr_tx), .pose_wr_ty(pose_wr_ty),
    .pose_wr_ready(k1_pose_wr_ready), .pose_wr_commit(k1_pose_wr_commit),
    .pose_wr_rejected(k1_pose_wr_rejected),
    .pose_accounting_error(k1_pose_accounting_error),
    .tile_origin_x(tile_origin_x), .tile_origin_y(tile_origin_y),
    .world_valid(k1_world_valid), .world_ready(k1_world_ready),
    .mapped_valid(k1_mapped), .pose_found(k1_found),
    .in_range(k1_range), .sensor_x(k1_sensor_x), .sensor_y(k1_sensor_y),
    .polarity(k1_polarity), .pose_version(k1_pose),
    .occurrence_timestamp_out(k1_time),
    .world_x(k1_world_x), .world_y(k1_world_y)
  );

  always #5 clk = ~clk;

  // One accepted input record is tracked independently through each endpoint.
  // State 1=pending, 3=K1 FIFO terminal drop, 4=delivered.
  integer rec_k8_state [0:MAX_RECORDS-1];
  integer rec_k1_state [0:MAX_RECORDS-1];
  integer rec_profile [0:MAX_RECORDS-1];
  integer rec_sx [0:MAX_RECORDS-1];
  integer rec_sy [0:MAX_RECORDS-1];
  integer rec_pol [0:MAX_RECORDS-1];
  integer rec_pose [0:MAX_RECORDS-1];
  integer rec_time [0:MAX_RECORDS-1];
  integer rec_wx [0:MAX_RECORDS-1];
  integer rec_wy [0:MAX_RECORDS-1];

  integer model_pose_valid [0:POSE_IDS-1];
  integer model_m00 [0:POSE_IDS-1];
  integer model_m01 [0:POSE_IDS-1];
  integer model_m10 [0:POSE_IDS-1];
  integer model_m11 [0:POSE_IDS-1];
  integer model_tx [0:POSE_IDS-1];
  integer model_ty [0:POSE_IDS-1];

  integer k8_light_latency [0:MAX_RECORDS-1];
  integer k1_light_latency [0:MAX_RECORDS-1];
  integer k8_burst_latency [0:MAX_RECORDS-1];
  integer k1_burst_latency [0:MAX_RECORDS-1];
  integer k8_light_latency_count;
  integer k1_light_latency_count;
  integer k8_burst_latency_count;
  integer k1_burst_latency_count;
  integer k8_light_latency_total;
  integer k1_light_latency_total;
  integer k8_burst_latency_total;
  integer k1_burst_latency_total;
  integer k8_light_latency_max;
  integer k1_light_latency_max;
  integer k8_burst_latency_max;
  integer k1_burst_latency_max;
  integer k8_light_p50;
  integer k8_light_p99;
  integer k1_light_p50;
  integer k1_light_p99;
  integer k8_burst_p50;
  integer k8_burst_p99;
  integer k1_burst_p50;
  integer k1_burst_p99;

  integer current_profile;
  integer record_count;
  integer cycle_count;
  integer error_count;
  integer generated [0:1];
  integer k8_aer_accepted [0:1];
  integer k1_aer_accepted [0:1];
  integer k8_aer_drop [0:1];
  integer k1_aer_drop [0:1];
  integer k8_fifo_drop [0:1];
  integer k1_fifo_drop [0:1];
  integer k8_delivered [0:1];
  integer k1_delivered [0:1];
  integer k1_stall_checks;
  integer pose_commits;

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

  integer i;
  integer lane;
  integer source;
  integer timeout_count;
  integer latency_value;
  integer temp_value;
  integer sort_i;
  integer sort_j;

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

  function integer find_k8_record;
    input integer wanted_time;
    input integer wanted_pose;
    input integer wanted_pol;
    input integer wanted_x;
    input integer wanted_y;
    integer scan;
    begin
      find_k8_record = -1;
      for (scan = 0; scan < record_count; scan = scan + 1)
        if (find_k8_record == -1 && rec_k8_state[scan] == 1
            && rec_time[scan] == wanted_time
            && rec_pose[scan] == wanted_pose
            && rec_pol[scan] == wanted_pol
            && rec_wx[scan] == wanted_x
            && rec_wy[scan] == wanted_y)
          find_k8_record = scan;
    end
  endfunction

  function integer find_k1_record;
    input integer wanted_time;
    input integer wanted_pose;
    input integer wanted_pol;
    input integer wanted_sx;
    input integer wanted_sy;
    integer scan;
    begin
      find_k1_record = -1;
      for (scan = 0; scan < record_count; scan = scan + 1)
        if (find_k1_record == -1 && rec_k1_state[scan] == 1
            && rec_time[scan] == wanted_time
            && rec_pose[scan] == wanted_pose
            && rec_pol[scan] == wanted_pol
            && rec_sx[scan] == wanted_sx
            && rec_sy[scan] == wanted_sy)
          find_k1_record = scan;
    end
  endfunction

  function integer pending_k8;
    integer scan;
    begin
      pending_k8 = 0;
      for (scan = 0; scan < record_count; scan = scan + 1)
        if (rec_k8_state[scan] == 1)
          pending_k8 = pending_k8 + 1;
    end
  endfunction

  function integer pending_k1;
    integer scan;
    begin
      pending_k1 = 0;
      for (scan = 0; scan < record_count; scan = scan + 1)
        if (rec_k1_state[scan] == 1)
          pending_k1 = pending_k1 + 1;
    end
  endfunction

  task automatic fail;
    input [1023:0] message;
    begin
      error_count = error_count + 1;
      $display("FAIL cycle=%0d profile=%0d: %0s",
               cycle_count, current_profile, message);
    end
  endtask

  task automatic calculate_world;
    input integer pose_id_in;
    input integer sx_in;
    input integer sy_in;
    output integer wx_out;
    output integer wy_out;
    integer acc_x;
    integer acc_y;
    begin
      if (!model_pose_valid[pose_id_in]) begin
        wx_out = 0;
        wy_out = 0;
      end else begin
        acc_x = model_m00[pose_id_in] * sx_in
              + model_m01[pose_id_in] * sy_in + model_tx[pose_id_in];
        acc_y = model_m10[pose_id_in] * sx_in
              + model_m11[pose_id_in] * sy_in + model_ty[pose_id_in];
        wx_out = round_q14_away_from_zero(acc_x);
        wy_out = round_q14_away_from_zero(acc_y);
      end
    end
  endtask

  task automatic add_record;
    input integer source_in;
    integer wx_value;
    integer wy_value;
    begin
      if (record_count >= MAX_RECORDS)
        $fatal(1, "comparison record table capacity exceeded");
      rec_k8_state[record_count] = 1;
      rec_k1_state[record_count] = 1;
      rec_profile[record_count] = current_profile;
      rec_sx[record_count] = tile_origin_x + (source_in & 3);
      rec_sy[record_count] = tile_origin_y + (source_in >> 2);
      rec_pol[record_count] = polarity_in[source_in];
      rec_pose[record_count] = occurrence_pose_version;
      rec_time[record_count] = occurrence_timestamp;
      calculate_world(rec_pose[record_count], rec_sx[record_count],
                      rec_sy[record_count], wx_value, wy_value);
      rec_wx[record_count] = wx_value;
      rec_wy[record_count] = wy_value;
      record_count = record_count + 1;
    end
  endtask

  task automatic record_k8_latency;
    input integer profile_in;
    input integer latency_in;
    begin
      if (profile_in == PROFILE_LIGHT) begin
        k8_light_latency[k8_light_latency_count] = latency_in;
        k8_light_latency_count = k8_light_latency_count + 1;
        k8_light_latency_total = k8_light_latency_total + latency_in;
        if (latency_in > k8_light_latency_max)
          k8_light_latency_max = latency_in;
      end else begin
        k8_burst_latency[k8_burst_latency_count] = latency_in;
        k8_burst_latency_count = k8_burst_latency_count + 1;
        k8_burst_latency_total = k8_burst_latency_total + latency_in;
        if (latency_in > k8_burst_latency_max)
          k8_burst_latency_max = latency_in;
      end
    end
  endtask

  task automatic record_k1_latency;
    input integer profile_in;
    input integer latency_in;
    begin
      if (profile_in == PROFILE_LIGHT) begin
        k1_light_latency[k1_light_latency_count] = latency_in;
        k1_light_latency_count = k1_light_latency_count + 1;
        k1_light_latency_total = k1_light_latency_total + latency_in;
        if (latency_in > k1_light_latency_max)
          k1_light_latency_max = latency_in;
      end else begin
        k1_burst_latency[k1_burst_latency_count] = latency_in;
        k1_burst_latency_count = k1_burst_latency_count + 1;
        k1_burst_latency_total = k1_burst_latency_total + latency_in;
        if (latency_in > k1_burst_latency_max)
          k1_burst_latency_max = latency_in;
      end
    end
  endtask

  task automatic check_k1_stability;
    begin
      if (held_valid) begin
        k1_stall_checks = k1_stall_checks + 1;
        if (k1_world_valid !== 1'b1 || k1_mapped !== held_mapped
            || k1_found !== held_found || k1_range !== held_range
            || k1_sensor_x !== held_sx || k1_sensor_y !== held_sy
            || k1_polarity !== held_pol || k1_pose !== held_pose
            || k1_time !== held_time
            || k1_world_x !== held_wx || k1_world_y !== held_wy)
          fail("K1 output/sideband changed while backpressured");
      end
    end
  endtask

  task automatic check_k8_outputs;
    integer idx;
    integer got_time;
    integer got_pose;
    integer got_pol;
    integer got_x;
    integer got_y;
    begin
      for (lane = 0; lane < 8; lane = lane + 1) begin
        if (k8_valid[lane]) begin
          got_time = k8_time_flat[lane*TIMESTAMP_W +: TIMESTAMP_W];
          got_pose = k8_pose_flat[lane*POSE_W +: POSE_W];
          got_pol = k8_polarity[lane];
          got_x = $signed(k8_x_flat[lane*RESULT_W +: RESULT_W]);
          got_y = $signed(k8_y_flat[lane*RESULT_W +: RESULT_W]);
          idx = find_k8_record(got_time, got_pose, got_pol, got_x, got_y);
          if (idx < 0) begin
            fail("K8 emitted an unknown or duplicate event");
          end else begin
            if (!k8_found[lane] || !k8_range[lane] || !k8_mapped[lane]
                || got_x != rec_wx[idx] || got_y != rec_wy[idx])
              fail("K8 transform validity/coordinate mismatch");
            rec_k8_state[idx] = 4;
            k8_delivered[rec_profile[idx]] =
              k8_delivered[rec_profile[idx]] + 1;
            latency_value = cycle_count - rec_time[idx];
            if (latency_value < 0)
              fail("K8 produced a negative timestamp-derived latency");
            else
              record_k8_latency(rec_profile[idx], latency_value);
          end
        end else if (k8_mapped[lane] || k8_found[lane] || k8_range[lane]) begin
          fail("K8 inactive lane asserted validity metadata");
        end
      end
    end
  endtask

  task automatic check_k1_output;
    integer idx;
    begin
      if (k1_world_valid) begin
        idx = find_k1_record(k1_time, k1_pose, k1_polarity,
                             k1_sensor_x, k1_sensor_y);
        if (idx < 0) begin
          fail("K1 emitted an unknown or duplicate event");
        end else begin
          if (!k1_found || !k1_range || !k1_mapped
              || $signed(k1_world_x) != rec_wx[idx]
              || $signed(k1_world_y) != rec_wy[idx])
            fail("K1 transform validity/coordinate mismatch");
          if (k1_world_ready) begin
            rec_k1_state[idx] = 4;
            k1_delivered[rec_profile[idx]] =
              k1_delivered[rec_profile[idx]] + 1;
            latency_value = cycle_count - rec_time[idx];
            if (latency_value < 0)
              fail("K1 produced a negative timestamp-derived latency");
            else
              record_k1_latency(rec_profile[idx], latency_value);
          end
        end
      end else if (k1_mapped || k1_found || k1_range) begin
        fail("K1 invalid output asserted validity metadata");
      end
    end
  endtask

  task automatic process_k1_fifo_drops;
    integer idx;
    integer lane_sx;
    integer lane_sy;
    integer lane_pol;
    integer lane_pose;
    integer lane_time;
    begin
      if ((k1_fifo_overflow & ~dut_k1.batch_valid) != 0)
        fail("K1 FIFO overflow asserted for an inactive batch lane");
      for (lane = 0; lane < 8; lane = lane + 1) begin
        if (k1_fifo_overflow[lane]) begin
          lane_sx = dut_k1.batch_x_flat[lane*SENSOR_W +: SENSOR_W];
          lane_sy = dut_k1.batch_y_flat[lane*SENSOR_W +: SENSOR_W];
          lane_pol = dut_k1.batch_polarity[lane];
          lane_pose = dut_k1.batch_pose_flat[lane*POSE_W +: POSE_W];
          lane_time = dut_k1.batch_time_flat[lane*TIMESTAMP_W +: TIMESTAMP_W];
          idx = find_k1_record(lane_time, lane_pose, lane_pol,
                               lane_sx, lane_sy);
          if (idx < 0) begin
            fail("K1 FIFO drop has no matching AER-accepted event");
          end else begin
            rec_k1_state[idx] = 3;
            k1_fifo_drop[rec_profile[idx]] =
              k1_fifo_drop[rec_profile[idx]] + 1;
          end
        end
      end
    end
  endtask

  task automatic process_inputs;
    begin
      if (k8_aer_overrun !== k1_aer_overrun)
        fail("identical AER leaves produced different overrun masks");
      if ((k8_aer_overrun & ~arrival) != 0
          || (k1_aer_overrun & ~arrival) != 0)
        fail("AER overrun asserted without an arrival");
      for (source = 0; source < 16; source = source + 1) begin
        if (arrival[source]) begin
          generated[current_profile] = generated[current_profile] + 1;
          if (k8_aer_overrun[source])
            k8_aer_drop[current_profile] =
              k8_aer_drop[current_profile] + 1;
          else
            k8_aer_accepted[current_profile] =
              k8_aer_accepted[current_profile] + 1;
          if (k1_aer_overrun[source])
            k1_aer_drop[current_profile] =
              k1_aer_drop[current_profile] + 1;
          else
            k1_aer_accepted[current_profile] =
              k1_aer_accepted[current_profile] + 1;
          if (!k8_aer_overrun[source] && !k1_aer_overrun[source])
            add_record(source);
        end
      end
    end
  endtask

  task automatic sample_before_edge;
    begin
      check_k1_stability;
      check_k8_outputs;
      check_k1_output;
      process_k1_fifo_drops;
      process_inputs;

      held_valid = k1_world_valid && !k1_world_ready;
      held_mapped = k1_mapped;
      held_found = k1_found;
      held_range = k1_range;
      held_sx = k1_sensor_x;
      held_sy = k1_sensor_y;
      held_pol = k1_polarity;
      held_pose = k1_pose;
      held_time = k1_time;
      held_wx = k1_world_x;
      held_wy = k1_world_y;
    end
  endtask

  task automatic step;
    input [15:0] arrivals_in;
    input [15:0] polarities_in;
    input integer pose_in;
    input integer k1_ready_in;
    input integer write_req_in;
    begin
      @(negedge clk);
      arrival = arrivals_in;
      polarity_in = polarities_in;
      occurrence_pose_version = pose_in;
      // This TB deliberately encodes the acceptance-cycle index in the
      // occurrence timestamp, making reported latency an end-to-end cycle count.
      occurrence_timestamp = cycle_count;
      k1_world_ready = k1_ready_in[0];
      pose_wr_req = write_req_in[0];
      #1;
      if (pose_wr_req) begin
        if (!k8_pose_wr_ready || !k1_pose_wr_ready
            || k8_pose_wr_rejected || k1_pose_wr_rejected
            || !k1_pose_wr_commit)
          fail("common idle pose write did not commit in both endpoints");
      end
      sample_before_edge;
      @(posedge clk);
      #1;
      if (k8_pose_accounting_error || k1_pose_accounting_error)
        fail("pose guard accounting_error asserted");
      if (pose_wr_req) begin
        model_pose_valid[pose_wr_id] = 1;
        model_m00[pose_wr_id] = $signed(pose_wr_m00);
        model_m01[pose_wr_id] = $signed(pose_wr_m01);
        model_m10[pose_wr_id] = $signed(pose_wr_m10);
        model_m11[pose_wr_id] = $signed(pose_wr_m11);
        model_tx[pose_wr_id] = $signed(pose_wr_tx);
        model_ty[pose_wr_id] = $signed(pose_wr_ty);
        pose_commits = pose_commits + 1;
      end
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
    end
  endtask

  task automatic drain_both;
    begin
      timeout_count = 0;
      while ((pending_k8() != 0 || pending_k1() != 0)
             && timeout_count < 10000) begin
        step(16'd0, 16'd0, 0, 1, 0);
        timeout_count = timeout_count + 1;
      end
      if (pending_k8() != 0 || pending_k1() != 0)
        fail("timed out draining K1/K8 records");
      repeat (3)
        step(16'd0, 16'd0, 0, 1, 0);
    end
  endtask

  task automatic sort_latencies;
    begin
      for (sort_i = 1; sort_i < k8_light_latency_count; sort_i = sort_i + 1) begin
        temp_value = k8_light_latency[sort_i];
        sort_j = sort_i - 1;
        while (sort_j >= 0 && k8_light_latency[sort_j] > temp_value) begin
          k8_light_latency[sort_j+1] = k8_light_latency[sort_j];
          sort_j = sort_j - 1;
        end
        k8_light_latency[sort_j+1] = temp_value;
      end
      for (sort_i = 1; sort_i < k1_light_latency_count; sort_i = sort_i + 1) begin
        temp_value = k1_light_latency[sort_i];
        sort_j = sort_i - 1;
        while (sort_j >= 0 && k1_light_latency[sort_j] > temp_value) begin
          k1_light_latency[sort_j+1] = k1_light_latency[sort_j];
          sort_j = sort_j - 1;
        end
        k1_light_latency[sort_j+1] = temp_value;
      end
      for (sort_i = 1; sort_i < k8_burst_latency_count; sort_i = sort_i + 1) begin
        temp_value = k8_burst_latency[sort_i];
        sort_j = sort_i - 1;
        while (sort_j >= 0 && k8_burst_latency[sort_j] > temp_value) begin
          k8_burst_latency[sort_j+1] = k8_burst_latency[sort_j];
          sort_j = sort_j - 1;
        end
        k8_burst_latency[sort_j+1] = temp_value;
      end
      for (sort_i = 1; sort_i < k1_burst_latency_count; sort_i = sort_i + 1) begin
        temp_value = k1_burst_latency[sort_i];
        sort_j = sort_i - 1;
        while (sort_j >= 0 && k1_burst_latency[sort_j] > temp_value) begin
          k1_burst_latency[sort_j+1] = k1_burst_latency[sort_j];
          sort_j = sort_j - 1;
        end
        k1_burst_latency[sort_j+1] = temp_value;
      end

      k8_light_p50 = k8_light_latency[(k8_light_latency_count-1)/2];
      k8_light_p99 = k8_light_latency[((k8_light_latency_count*99+99)/100)-1];
      k1_light_p50 = k1_light_latency[(k1_light_latency_count-1)/2];
      k1_light_p99 = k1_light_latency[((k1_light_latency_count*99+99)/100)-1];
      k8_burst_p50 = k8_burst_latency[(k8_burst_latency_count-1)/2];
      k8_burst_p99 = k8_burst_latency[((k8_burst_latency_count*99+99)/100)-1];
      k1_burst_p50 = k1_burst_latency[(k1_burst_latency_count-1)/2];
      k1_burst_p99 = k1_burst_latency[((k1_burst_latency_count*99+99)/100)-1];
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
    tile_origin_x = 0;
    tile_origin_y = 0;
    k1_world_ready = 0;
    current_profile = PROFILE_LIGHT;
    record_count = 0;
    cycle_count = 0;
    error_count = 0;
    k1_stall_checks = 0;
    pose_commits = 0;
    held_valid = 0;
    k8_light_latency_count = 0;
    k1_light_latency_count = 0;
    k8_burst_latency_count = 0;
    k1_burst_latency_count = 0;
    k8_light_latency_total = 0;
    k1_light_latency_total = 0;
    k8_burst_latency_total = 0;
    k1_burst_latency_total = 0;
    k8_light_latency_max = 0;
    k1_light_latency_max = 0;
    k8_burst_latency_max = 0;
    k1_burst_latency_max = 0;
    for (i = 0; i < MAX_RECORDS; i = i + 1) begin
      rec_k8_state[i] = 0;
      rec_k1_state[i] = 0;
    end
    for (i = 0; i < POSE_IDS; i = i + 1) begin
      model_pose_valid[i] = 0;
      model_m00[i] = 0;
      model_m01[i] = 0;
      model_m10[i] = 0;
      model_m11[i] = 0;
      model_tx[i] = 0;
      model_ty[i] = 0;
    end
    for (i = 0; i < 2; i = i + 1) begin
      generated[i] = 0;
      k8_aer_accepted[i] = 0;
      k1_aer_accepted[i] = 0;
      k8_aer_drop[i] = 0;
      k1_aer_drop[i] = 0;
      k8_fifo_drop[i] = 0;
      k1_fifo_drop[i] = 0;
      k8_delivered[i] = 0;
      k1_delivered[i] = 0;
    end

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    load_pose(0, Q, 0, 0, Q, 0, 0);
    load_pose(1, 0, -Q, Q, 0, 3*Q, 0);
    load_pose(2, Q, 0, 0, Q, 4*Q, 5*Q);

    // Light profile: sparse complete 4x4 sweeps for three poses. Both
    // architectures must be lossless and produce identical event metadata.
    current_profile = PROFILE_LIGHT;
    for (i = 0; i < 48; i = i + 1) begin
      source = i & 15;
      step(16'h0001 << source,
           i[0] ? (16'h0001 << source) : 16'd0,
           i / 16, 1, 0);
      repeat (2)
        step(16'd0, 16'd0, 0, 1, 0);
    end
    drain_both;
    if (k8_aer_drop[PROFILE_LIGHT] != 0
        || k1_aer_drop[PROFILE_LIGHT] != 0
        || k8_fifo_drop[PROFILE_LIGHT] != 0
        || k1_fifo_drop[PROFILE_LIGHT] != 0)
      fail("light profile was not terminal-drop free");
    if (k8_delivered[PROFILE_LIGHT] != generated[PROFILE_LIGHT]
        || k1_delivered[PROFILE_LIGHT] != generated[PROFILE_LIGHT])
      fail("light profile did not deliver every generated event");

    // Burst profile: K8 remains intrinsically always-ready. K1 is stalled for
    // the first 12 input cycles, then receives intermittent readiness.
    current_profile = PROFILE_BURST;
    for (i = 0; i < 40; i = i + 1)
      step(16'hffff,
           i[0] ? 16'haaaa : 16'h5555,
           i % 3, (i >= 12) && ((i % 4) != 0), 0);
    repeat (16)
      step(16'd0, 16'd0, 0, (cycle_count % 3) != 0, 0);
    drain_both;

    if (k8_aer_drop[PROFILE_BURST] == 0
        || k1_aer_drop[PROFILE_BURST] == 0)
      fail("burst profile did not exercise both AER overrun counters");
    if (k1_fifo_drop[PROFILE_BURST] == 0)
      fail("burst/backpressure profile did not exercise K1 FIFO drops");
    if (k1_stall_checks == 0)
      fail("K1 backpressure stability was never checked");

    for (i = 0; i < POSE_IDS; i = i + 1) begin
      if (dut_k8.u_pose_guard.outstanding[i] != 0
          || dut_k1.u_pose_guard.outstanding[i] != 0)
        fail("pose guard did not drain to zero");
    end
    if (!k8_pose_wr_ready || !k1_pose_wr_ready)
      fail("pose write did not become ready after complete drain");
    if (k8_pose_accounting_error || k1_pose_accounting_error)
      fail("pose guard accounting error remained after drain");

    for (i = 0; i < 2; i = i + 1) begin
      if (generated[i] != k8_aer_accepted[i] + k8_aer_drop[i]
          || generated[i] != k1_aer_accepted[i] + k1_aer_drop[i])
        fail("generated/AER-accepted/AER-drop conservation mismatch");
      if (k8_aer_accepted[i] != k8_delivered[i])
        fail("K8 accepted/delivered conservation mismatch");
      if (k1_aer_accepted[i]
          != k1_fifo_drop[i] + k1_delivered[i])
        fail("K1 accepted/FIFO-drop/delivered conservation mismatch");
      if (k8_aer_accepted[i] != k1_aer_accepted[i]
          || k8_aer_drop[i] != k1_aer_drop[i])
        fail("shared AER front ends did not have identical accounting");
    end

    if (k8_light_latency_count == 0 || k1_light_latency_count == 0
        || k8_burst_latency_count == 0 || k1_burst_latency_count == 0)
      fail("one latency profile has no delivered samples");
    else
      sort_latencies;

    $display("K8_LIGHT generated=%0d accepted=%0d aer_drop=%0d fifo_drop=0 delivered=%0d latency_count=%0d total=%0d p50=%0d p99=%0d max=%0d",
             generated[PROFILE_LIGHT], k8_aer_accepted[PROFILE_LIGHT],
             k8_aer_drop[PROFILE_LIGHT], k8_delivered[PROFILE_LIGHT],
             k8_light_latency_count, k8_light_latency_total,
             k8_light_p50, k8_light_p99, k8_light_latency_max);
    $display("K1_LIGHT generated=%0d accepted=%0d aer_drop=%0d fifo_drop=%0d delivered=%0d latency_count=%0d total=%0d p50=%0d p99=%0d max=%0d",
             generated[PROFILE_LIGHT], k1_aer_accepted[PROFILE_LIGHT],
             k1_aer_drop[PROFILE_LIGHT], k1_fifo_drop[PROFILE_LIGHT],
             k1_delivered[PROFILE_LIGHT], k1_light_latency_count,
             k1_light_latency_total, k1_light_p50, k1_light_p99,
             k1_light_latency_max);
    $display("K8_BURST generated=%0d accepted=%0d aer_drop=%0d fifo_drop=0 delivered=%0d latency_count=%0d total=%0d p50=%0d p99=%0d max=%0d",
             generated[PROFILE_BURST], k8_aer_accepted[PROFILE_BURST],
             k8_aer_drop[PROFILE_BURST], k8_delivered[PROFILE_BURST],
             k8_burst_latency_count, k8_burst_latency_total,
             k8_burst_p50, k8_burst_p99, k8_burst_latency_max);
    $display("K1_BURST generated=%0d accepted=%0d aer_drop=%0d fifo_drop=%0d delivered=%0d latency_count=%0d total=%0d p50=%0d p99=%0d max=%0d",
             generated[PROFILE_BURST], k1_aer_accepted[PROFILE_BURST],
             k1_aer_drop[PROFILE_BURST], k1_fifo_drop[PROFILE_BURST],
             k1_delivered[PROFILE_BURST], k1_burst_latency_count,
             k1_burst_latency_total, k1_burst_p50, k1_burst_p99,
             k1_burst_latency_max);
    $display("K1_K8_COVERAGE k1_stall_checks=%0d pose_commits=%0d",
             k1_stall_checks, pose_commits);
    if (error_count == 0) begin
      $display("STAGE2_K1_K8_COMPARISON_PASS");
      $finish;
    end else begin
      $fatal(1, "STAGE2_K1_K8_COMPARISON_FAIL errors=%0d", error_count);
    end
  end
endmodule
