`timescale 1ns/1ps

// Trace-driven K=1/K=8 comparison.
//
// addrpol.txt supplies 1 ms-bin index, address-mask, and polarity-mask fields.
// Empty cycles between rows are replayed, not compressed. The trace has no
// pose field, so this TB explicitly assigns pose_version = trace_cycle mod 3.
module tb_stage2_k1_k8_uzh_trace;
  parameter integer FIFO_DEPTH = 32;
  parameter integer DRAIN_LIMIT = 20000;

  localparam integer POSE_W = 3;
  localparam integer SENSOR_W = 4;
  localparam integer RESULT_W = 16;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer FRAC_W = 14;
  localparam integer TIMESTAMP_W = 16;
  localparam integer COUNT_W = 10;
  localparam integer POSE_IDS = (1 << POSE_W);
  localparam integer Q = (1 << FRAC_W);
  localparam integer HALF = (1 << (FRAC_W-1));
  localparam integer TIMESTAMP_VALUES = (1 << TIMESTAMP_W);
  localparam integer KEY_COUNT = TIMESTAMP_VALUES * 16;
  localparam integer MAX_LATENCY = 70000;

  reg [1023:0] trace_file_r;
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
    .tile_origin_x({SENSOR_W{1'b0}}),
    .tile_origin_y({SENSOR_W{1'b0}}),
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
    .tile_origin_x({SENSOR_W{1'b0}}),
    .tile_origin_y({SENSOR_W{1'b0}}),
    .world_valid(k1_world_valid), .world_ready(1'b1),
    .mapped_valid(k1_mapped), .pose_found(k1_found),
    .in_range(k1_range), .sensor_x(k1_sensor_x), .sensor_y(k1_sensor_y),
    .polarity(k1_polarity), .pose_version(k1_pose),
    .occurrence_timestamp_out(k1_time),
    .world_x(k1_world_x), .world_y(k1_world_y)
  );

  always #5 clk = ~clk;

  // A key is {occurrence timestamp, source}. This trace contains at most one
  // occurrence per source per cycle, so it uniquely identifies every event.
  reg [1:0] k8_state [0:KEY_COUNT-1];
  reg [1:0] k1_state [0:KEY_COUNT-1];
  reg record_polarity [0:KEY_COUNT-1];
  reg [POSE_W-1:0] record_pose [0:KEY_COUNT-1];
  integer k8_latency_hist [0:MAX_LATENCY];
  integer k1_latency_hist [0:MAX_LATENCY];

  integer fd;
  integer scan_ret;
  integer next_cycle;
  integer next_addr;
  integer next_pol;
  integer have_next;
  integer replay_cycle;
  integer first_trace_cycle;
  integer last_trace_cycle;
  integer trace_rows;
  integer event_cycles;
  integer idle_cycles;
  integer drain_cycles;
  integer generated_count;
  integer k8_accepted_count;
  integer k1_accepted_count;
  integer k8_aer_drop_count;
  integer k1_aer_drop_count;
  integer k1_fifo_drop_count;
  integer k8_delivered_count;
  integer k1_delivered_count;
  integer k8_pending_count;
  integer k1_pending_count;
  integer k8_latency_total;
  integer k1_latency_total;
  integer k8_latency_max;
  integer k1_latency_max;
  integer k8_latency_p50;
  integer k8_latency_p99;
  integer k1_latency_p50;
  integer k1_latency_p99;
  integer error_count;
  integer pose_commit_count;

  integer i;
  integer lane;
  integer source;
  integer key;
  integer latency_value;
  integer expected_x;
  integer expected_y;
  integer source_from_world;
  integer cumulative;
  integer target50;
  integer target99;
  integer found50;
  integer found99;
  integer cycle_addr;
  integer cycle_pol;
  integer overlap_addr;

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

  task automatic fail;
    input [1023:0] message;
    begin
      error_count = error_count + 1;
      $display("FAIL replay_cycle=%0d depth=%0d: %0s",
               replay_cycle, FIFO_DEPTH, message);
    end
  endtask

  task automatic calculate_world;
    input integer pose_in;
    input integer source_in;
    output integer x_out;
    output integer y_out;
    integer sx;
    integer sy;
    begin
      sx = source_in & 3;
      sy = source_in >> 2;
      case (pose_in)
        0: begin x_out = sx; y_out = sy; end
        1: begin x_out = 3 - sy; y_out = sx; end
        2: begin x_out = sx + 4; y_out = sy + 5; end
        default: begin x_out = 0; y_out = 0; end
      endcase
    end
  endtask

  function integer find_source_for_world;
    input integer pose_in;
    input integer x_in;
    input integer y_in;
    integer scan_source;
    integer trial_x;
    integer trial_y;
    begin
      find_source_for_world = -1;
      for (scan_source = 0; scan_source < 16; scan_source = scan_source + 1) begin
        case (pose_in)
          0: begin
            trial_x = scan_source & 3;
            trial_y = scan_source >> 2;
          end
          1: begin
            trial_x = 3 - (scan_source >> 2);
            trial_y = scan_source & 3;
          end
          2: begin
            trial_x = (scan_source & 3) + 4;
            trial_y = (scan_source >> 2) + 5;
          end
          default: begin trial_x = -1; trial_y = -1; end
        endcase
        if (find_source_for_world == -1
            && trial_x == x_in && trial_y == y_in)
          find_source_for_world = scan_source;
      end
    end
  endfunction

  task automatic add_latency_k8;
    input integer value;
    begin
      if (value < 0 || value > MAX_LATENCY) begin
        fail("K8 timestamp-derived latency is outside histogram range");
      end else begin
        k8_latency_hist[value] = k8_latency_hist[value] + 1;
        k8_latency_total = k8_latency_total + value;
        if (value > k8_latency_max)
          k8_latency_max = value;
      end
    end
  endtask

  task automatic add_latency_k1;
    input integer value;
    begin
      if (value < 0 || value > MAX_LATENCY) begin
        fail("K1 timestamp-derived latency is outside histogram range");
      end else begin
        k1_latency_hist[value] = k1_latency_hist[value] + 1;
        k1_latency_total = k1_latency_total + value;
        if (value > k1_latency_max)
          k1_latency_max = value;
      end
    end
  endtask

  task automatic check_k8_outputs;
    integer got_time;
    integer got_pose;
    integer got_pol;
    integer got_x;
    integer got_y;
    integer got_source;
    integer got_key;
    begin
      for (lane = 0; lane < 8; lane = lane + 1) begin
        if (k8_valid[lane]) begin
          got_time = k8_time_flat[lane*TIMESTAMP_W +: TIMESTAMP_W];
          got_pose = k8_pose_flat[lane*POSE_W +: POSE_W];
          got_pol = k8_polarity[lane];
          got_x = $signed(k8_x_flat[lane*RESULT_W +: RESULT_W]);
          got_y = $signed(k8_y_flat[lane*RESULT_W +: RESULT_W]);
          got_source = find_source_for_world(got_pose, got_x, got_y);
          if (got_source < 0) begin
            fail("K8 output coordinate cannot be produced by its pose");
          end else begin
            got_key = got_time * 16 + got_source;
            if (k8_state[got_key] !== 2'd1) begin
              fail("K8 output is unknown or duplicated");
            end else begin
              if (record_pose[got_key] != got_pose
                  || record_polarity[got_key] != got_pol
                  || !k8_found[lane] || !k8_range[lane]
                  || !k8_mapped[lane])
                fail("K8 occurrence metadata or validity mismatch");
              k8_state[got_key] = 2'd2;
              k8_pending_count = k8_pending_count - 1;
              k8_delivered_count = k8_delivered_count + 1;
              add_latency_k8(replay_cycle - got_time);
            end
          end
        end else if (k8_mapped[lane] || k8_found[lane] || k8_range[lane]) begin
          fail("K8 inactive lane asserted validity metadata");
        end
      end
    end
  endtask

  task automatic check_k1_output;
    integer got_source;
    integer got_key;
    begin
      if (k1_world_valid) begin
        if (k1_sensor_x > 3 || k1_sensor_y > 3) begin
          fail("K1 source coordinate escaped the 4x4 tile");
        end else begin
          got_source = k1_sensor_y * 4 + k1_sensor_x;
          got_key = k1_time * 16 + got_source;
          calculate_world(k1_pose, got_source, expected_x, expected_y);
          if (k1_state[got_key] !== 2'd1) begin
            fail("K1 output is unknown, dropped, or duplicated");
          end else begin
            if (record_pose[got_key] != k1_pose
                || record_polarity[got_key] != k1_polarity
                || $signed(k1_world_x) != expected_x
                || $signed(k1_world_y) != expected_y
                || !k1_found || !k1_range || !k1_mapped)
              fail("K1 occurrence metadata, coordinate, or validity mismatch");
            k1_state[got_key] = 2'd2;
            k1_pending_count = k1_pending_count - 1;
            k1_delivered_count = k1_delivered_count + 1;
            add_latency_k1(replay_cycle - k1_time);
          end
        end
      end else if (k1_mapped || k1_found || k1_range) begin
        fail("K1 invalid output asserted validity metadata");
      end
    end
  endtask

  task automatic process_k1_fifo_drops;
    integer drop_source;
    integer drop_key;
    integer drop_time;
    integer drop_pose;
    integer drop_pol;
    integer drop_sx;
    integer drop_sy;
    begin
      if ((k1_fifo_overflow & ~dut_k1.batch_valid) != 0)
        fail("K1 FIFO overflow asserted for an inactive batch lane");
      for (lane = 0; lane < 8; lane = lane + 1) begin
        if (k1_fifo_overflow[lane]) begin
          drop_sx = dut_k1.batch_x_flat[lane*SENSOR_W +: SENSOR_W];
          drop_sy = dut_k1.batch_y_flat[lane*SENSOR_W +: SENSOR_W];
          drop_pol = dut_k1.batch_polarity[lane];
          drop_pose = dut_k1.batch_pose_flat[lane*POSE_W +: POSE_W];
          drop_time = dut_k1.batch_time_flat[lane*TIMESTAMP_W +: TIMESTAMP_W];
          drop_source = drop_sy * 4 + drop_sx;
          drop_key = drop_time * 16 + drop_source;
          if (drop_sx > 3 || drop_sy > 3) begin
            fail("K1 FIFO drop carried an invalid source coordinate");
          end else if (k1_state[drop_key] !== 2'd1) begin
            fail("K1 FIFO drop is unknown or duplicated");
          end else begin
            if (record_pose[drop_key] != drop_pose
                || record_polarity[drop_key] != drop_pol)
              fail("K1 FIFO drop occurrence metadata mismatch");
            k1_state[drop_key] = 2'd3;
            k1_pending_count = k1_pending_count - 1;
            k1_fifo_drop_count = k1_fifo_drop_count + 1;
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
          generated_count = generated_count + 1;
          if (k8_aer_overrun[source])
            k8_aer_drop_count = k8_aer_drop_count + 1;
          else
            k8_accepted_count = k8_accepted_count + 1;
          if (k1_aer_overrun[source])
            k1_aer_drop_count = k1_aer_drop_count + 1;
          else
            k1_accepted_count = k1_accepted_count + 1;

          if (!k8_aer_overrun[source] && !k1_aer_overrun[source]) begin
            key = occurrence_timestamp * 16 + source;
            if (k8_state[key] === 2'd1 || k1_state[key] === 2'd1)
              fail("trace repeated one source within the same cycle key");
            k8_state[key] = 2'd1;
            k1_state[key] = 2'd1;
            record_polarity[key] = polarity_in[source];
            record_pose[key] = occurrence_pose_version;
            k8_pending_count = k8_pending_count + 1;
            k1_pending_count = k1_pending_count + 1;
          end
        end
      end
    end
  endtask

  task automatic step_one_trace_cycle;
    input [15:0] addr_in;
    input [15:0] pol_in;
    begin
      @(negedge clk);
      arrival = addr_in;
      polarity_in = pol_in & addr_in;
      occurrence_pose_version = replay_cycle % 3;
      occurrence_timestamp = replay_cycle[TIMESTAMP_W-1:0];
      pose_wr_req = 1'b0;
      #1;
      check_k8_outputs;
      check_k1_output;
      process_k1_fifo_drops;
      process_inputs;
      @(posedge clk);
      #1;
      if (k8_pose_accounting_error || k1_pose_accounting_error)
        fail("pose guard accounting_error asserted");
      replay_cycle = replay_cycle + 1;
    end
  endtask

  task automatic program_pose;
    input integer id;
    input integer m00;
    input integer m01;
    input integer m10;
    input integer m11;
    input integer tx;
    input integer ty;
    begin
      @(negedge clk);
      arrival = 0;
      polarity_in = 0;
      occurrence_pose_version = 0;
      occurrence_timestamp = 0;
      pose_wr_id = id;
      pose_wr_m00 = m00;
      pose_wr_m01 = m01;
      pose_wr_m10 = m10;
      pose_wr_m11 = m11;
      pose_wr_tx = tx;
      pose_wr_ty = ty;
      pose_wr_req = 1'b1;
      #1;
      if (!k8_pose_wr_ready || !k1_pose_wr_ready
          || k8_pose_wr_rejected || k1_pose_wr_rejected
          || !k1_pose_wr_commit)
        fail("initial common pose write did not commit");
      @(posedge clk);
      #1;
      pose_commit_count = pose_commit_count + 1;
    end
  endtask

  task automatic calculate_percentiles;
    begin
      target50 = (k8_delivered_count + 1) / 2;
      target99 = (k8_delivered_count * 99 + 99) / 100;
      cumulative = 0;
      found50 = 0;
      found99 = 0;
      for (i = 0; i <= MAX_LATENCY; i = i + 1) begin
        cumulative = cumulative + k8_latency_hist[i];
        if (!found50 && cumulative >= target50) begin
          k8_latency_p50 = i;
          found50 = 1;
        end
        if (!found99 && cumulative >= target99) begin
          k8_latency_p99 = i;
          found99 = 1;
        end
      end

      target50 = (k1_delivered_count + 1) / 2;
      target99 = (k1_delivered_count * 99 + 99) / 100;
      cumulative = 0;
      found50 = 0;
      found99 = 0;
      for (i = 0; i <= MAX_LATENCY; i = i + 1) begin
        cumulative = cumulative + k1_latency_hist[i];
        if (!found50 && cumulative >= target50) begin
          k1_latency_p50 = i;
          found50 = 1;
        end
        if (!found99 && cumulative >= target99) begin
          k1_latency_p99 = i;
          found99 = 1;
        end
      end
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
    replay_cycle = 0;
    first_trace_cycle = -1;
    last_trace_cycle = -1;
    trace_rows = 0;
    event_cycles = 0;
    idle_cycles = 0;
    drain_cycles = 0;
    generated_count = 0;
    k8_accepted_count = 0;
    k1_accepted_count = 0;
    k8_aer_drop_count = 0;
    k1_aer_drop_count = 0;
    k1_fifo_drop_count = 0;
    k8_delivered_count = 0;
    k1_delivered_count = 0;
    k8_pending_count = 0;
    k1_pending_count = 0;
    k8_latency_total = 0;
    k1_latency_total = 0;
    k8_latency_max = 0;
    k1_latency_max = 0;
    k8_latency_p50 = 0;
    k8_latency_p99 = 0;
    k1_latency_p50 = 0;
    k1_latency_p99 = 0;
    error_count = 0;
    pose_commit_count = 0;
    for (i = 0; i <= MAX_LATENCY; i = i + 1) begin
      k8_latency_hist[i] = 0;
      k1_latency_hist[i] = 0;
    end

    if (!$value$plusargs("TRACE_FILE=%s", trace_file_r)) begin
      $display("MISSING +TRACE_FILE=");
      $fatal(1, "trace path is required");
    end
    fd = $fopen(trace_file_r, "r");
    if (fd == 0)
      $fatal(1, "cannot open trace %0s", trace_file_r);
    scan_ret = $fscanf(fd, "%d %h %h", next_cycle, next_addr, next_pol);
    have_next = (scan_ret == 3);
    if (!have_next)
      $fatal(1, "trace is empty or malformed");
    first_trace_cycle = next_cycle;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    program_pose(0, Q, 0, 0, Q, 0, 0);
    program_pose(1, 0, -Q, Q, 0, 3*Q, 0);
    program_pose(2, Q, 0, 0, Q, 4*Q, 5*Q);

    while (have_next) begin
      if (next_cycle < replay_cycle)
        fail("trace cycle order moved backward");
      if (next_cycle >= TIMESTAMP_VALUES)
        fail("trace cycle does not fit occurrence timestamp width");

      cycle_addr = 0;
      cycle_pol = 0;
      overlap_addr = 0;
      while (have_next && next_cycle == replay_cycle) begin
        overlap_addr = overlap_addr | (cycle_addr & next_addr);
        cycle_addr = cycle_addr | next_addr;
        cycle_pol = (cycle_pol & ~next_addr) | (next_pol & next_addr);
        trace_rows = trace_rows + 1;
        last_trace_cycle = next_cycle;
        scan_ret = $fscanf(fd, "%d %h %h", next_cycle, next_addr, next_pol);
        have_next = (scan_ret == 3);
      end
      if (overlap_addr != 0)
        fail("trace repeats a source in multiple rows of one cycle");
      if (cycle_addr != 0)
        event_cycles = event_cycles + 1;
      else
        idle_cycles = idle_cycles + 1;
      step_one_trace_cycle(cycle_addr[15:0], cycle_pol[15:0]);
    end

    while ((k8_pending_count != 0 || k1_pending_count != 0)
           && drain_cycles < DRAIN_LIMIT) begin
      step_one_trace_cycle(16'd0, 16'd0);
      drain_cycles = drain_cycles + 1;
    end
    repeat (3) begin
      step_one_trace_cycle(16'd0, 16'd0);
      drain_cycles = drain_cycles + 1;
    end

    if (k8_pending_count != 0 || k1_pending_count != 0)
      fail("bounded drain did not resolve every accepted event");
    if (dut_k1.fifo_occupancy != 0 || k1_world_valid || |k8_valid)
      fail("pipeline remained nonempty after drain");
    for (i = 0; i < POSE_IDS; i = i + 1)
      if (dut_k8.u_pose_guard.outstanding[i] != 0
          || dut_k1.u_pose_guard.outstanding[i] != 0)
        fail("K1 or K8 pose guard leaked an outstanding reference");
    pose_wr_id = 0;
    #1;
    if (!k8_pose_wr_ready || !k1_pose_wr_ready)
      fail("pose write did not return ready after drain");
    if (k8_pose_accounting_error || k1_pose_accounting_error)
      fail("pose guard accounting error is sticky after trace");

    if (generated_count != k8_accepted_count + k8_aer_drop_count
        || generated_count != k1_accepted_count + k1_aer_drop_count)
      fail("generated/AER-accepted/AER-drop conservation mismatch");
    if (k8_accepted_count != k8_delivered_count)
      fail("K8 AER-accepted/delivered conservation mismatch");
    if (k1_accepted_count != k1_fifo_drop_count + k1_delivered_count)
      fail("K1 accepted/FIFO-drop/delivered conservation mismatch");
    if (k8_aer_drop_count != k1_aer_drop_count
        || k8_accepted_count != k1_accepted_count)
      fail("identical AER front ends disagreed on trace admission");
    if (k8_delivered_count == 0 || k1_delivered_count == 0)
      fail("latency population is empty");

    calculate_percentiles;

    $display("TRACE_TIMING_MODE=input_cycle_field timebase=1ms_bin trace=%0s rows=%0d first=%0d last=%0d event_cycles=%0d idle_cycles=%0d drain_cycles=%0d",
             trace_file_r, trace_rows, first_trace_cycle, last_trace_cycle,
             event_cycles, idle_cycles, drain_cycles);
    $display("TRACE_POSE_MODE=synthetic_cycle_mod_3 (addrpol trace has no pose field)");
    $display("K8_TRACE depth=NA generated=%0d accepted=%0d aer_overrun=%0d fifo_overflow=0 delivered=%0d latency_total=%0d p50=%0d p99=%0d max=%0d",
             generated_count, k8_accepted_count, k8_aer_drop_count,
             k8_delivered_count, k8_latency_total,
             k8_latency_p50, k8_latency_p99, k8_latency_max);
    $display("K1_TRACE depth=%0d generated=%0d accepted=%0d aer_overrun=%0d fifo_overflow=%0d delivered=%0d latency_total=%0d p50=%0d p99=%0d max=%0d",
             FIFO_DEPTH, generated_count, k1_accepted_count,
             k1_aer_drop_count, k1_fifo_drop_count, k1_delivered_count,
             k1_latency_total, k1_latency_p50, k1_latency_p99,
             k1_latency_max);
    $display("TRACE_GUARD_DRAIN_PASS pose_commits=%0d", pose_commit_count);
    if (error_count == 0) begin
      $display("STAGE2_K1_K8_UZH_TRACE_PASS");
      $fclose(fd);
      $finish;
    end else begin
      $fclose(fd);
      $fatal(1, "STAGE2_K1_K8_UZH_TRACE_FAIL errors=%0d", error_count);
    end
  end
endmodule
