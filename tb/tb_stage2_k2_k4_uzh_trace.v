`timescale 1ns/1ps

// Exact-cycle UZH trace check for the configurable banked 4x4 endpoint.
// The addrpol trace has no pose field, so pose_version is cycle modulo three.
module tb_stage2_k2_k4_uzh_trace;
  parameter integer K = 2;
  parameter integer FIFO_DEPTH = 32;
  parameter integer DRAIN_LIMIT = 20000;
  parameter integer SERIALIZE_OUTPUT = 0;
  parameter integer SERIAL_STALL_OUTPUT = 0;

  localparam integer POSE_W = 3;
  localparam integer SENSOR_W = 4;
  localparam integer RESULT_W = 16;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer FRAC_W = 14;
  localparam integer TIMESTAMP_W = 16;
  localparam integer COUNT_W = 11;
  localparam integer OCC_W = $clog2(FIFO_DEPTH + 1);
  localparam integer POSE_IDS = (1 << POSE_W);
  localparam integer Q = (1 << FRAC_W);
  localparam integer TIMESTAMP_VALUES = (1 << TIMESTAMP_W);
  localparam integer KEY_COUNT = TIMESTAMP_VALUES * 16;
  localparam integer MAX_LATENCY = 70000;
  localparam integer SERIAL_PAYLOAD_W =
    2 + 3 + 2*SENSOR_W + 1 + POSE_W + TIMESTAMP_W + 2*RESULT_W;

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
  reg serial_world_ready;
  reg [15:0] ready_lfsr;
  reg serial_stall_held;
  reg [SERIAL_PAYLOAD_W-1:0] serial_stall_payload;

  wire [15:0] aer_overrun;
  wire [7:0] fifo_overflow;
  wire pose_wr_ready;
  wire pose_wr_commit;
  wire pose_wr_rejected;
  wire pose_accounting_error;
  wire [K-1:0] world_valid;
  wire [K-1:0] world_fire;
  wire [K-1:0] mapped_valid;
  wire [K-1:0] pose_found;
  wire [K-1:0] in_range;
  wire [K*SENSOR_W-1:0] sensor_x_flat;
  wire [K*SENSOR_W-1:0] sensor_y_flat;
  wire [K-1:0] polarity_out;
  wire [K*POSE_W-1:0] pose_flat;
  wire [K*TIMESTAMP_W-1:0] timestamp_flat;
  wire [K*RESULT_W-1:0] world_x_flat;
  wire [K*RESULT_W-1:0] world_y_flat;
  wire [7:0] debug_batch_valid;
  wire [8*SENSOR_W-1:0] debug_batch_x_flat;
  wire [8*SENSOR_W-1:0] debug_batch_y_flat;
  wire [7:0] debug_batch_polarity;
  wire [8*POSE_W-1:0] debug_batch_pose_flat;
  wire [8*TIMESTAMP_W-1:0] debug_batch_time_flat;
  wire [K*OCC_W-1:0] debug_fifo_occupancy_flat;
  wire [POSE_IDS-1:0] debug_pose_busy;
  wire debug_serial_valid;
  wire debug_serial_ready;
  wire [SERIAL_PAYLOAD_W-1:0] debug_serial_payload;

  genvar parallel_pose_index;
  genvar serialized_pose_index;

  generate
    if (SERIALIZE_OUTPUT == 0) begin: parallel_dut
      aer_tx16_pose_affine2d_banked #(
        .K(K), .POSE_W(POSE_W), .SENSOR_W(SENSOR_W),
        .RESULT_W(RESULT_W), .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W),
        .FRAC_W(FRAC_W), .TIMESTAMP_W(TIMESTAMP_W),
        .FIFO_DEPTH(FIFO_DEPTH), .GUARD_COUNT_W(COUNT_W),
        .X_MIN(0), .X_MAX(31), .Y_MIN(0), .Y_MAX(31)
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
        .tile_origin_x({SENSOR_W{1'b0}}),
        .tile_origin_y({SENSOR_W{1'b0}}),
        .world_valid(world_valid), .world_ready({K{1'b1}}),
        .mapped_valid(mapped_valid), .pose_found(pose_found),
        .in_range(in_range), .sensor_x_out_flat(sensor_x_flat),
        .sensor_y_out_flat(sensor_y_flat), .polarity_out(polarity_out),
        .pose_version_out_flat(pose_flat),
        .occurrence_timestamp_out_flat(timestamp_flat),
        .world_x_out_flat(world_x_flat), .world_y_out_flat(world_y_flat)
      );

      assign debug_batch_valid = dut.batch_valid;
      assign debug_batch_x_flat = dut.batch_x_flat;
      assign debug_batch_y_flat = dut.batch_y_flat;
      assign debug_batch_polarity = dut.batch_polarity;
      assign debug_batch_pose_flat = dut.batch_pose_flat;
      assign debug_batch_time_flat = dut.batch_time_flat;
      assign debug_fifo_occupancy_flat = dut.fifo_occupancy_flat;
      assign debug_serial_valid = 1'b0;
      assign debug_serial_ready = 1'b1;
      assign debug_serial_payload = {SERIAL_PAYLOAD_W{1'b0}};
      assign world_fire = world_valid;
      for (parallel_pose_index = 0; parallel_pose_index < POSE_IDS;
           parallel_pose_index = parallel_pose_index + 1) begin: pose_busy
        assign debug_pose_busy[parallel_pose_index] =
          |dut.u_pose_guard.outstanding[parallel_pose_index];
      end
    end else begin: serialized_dut
      wire serial_valid;
      wire serial_mapped;
      wire serial_found;
      wire serial_range;
      wire [SENSOR_W-1:0] serial_sensor_x;
      wire [SENSOR_W-1:0] serial_sensor_y;
      wire [1:0] serial_bank;
      wire serial_polarity;
      wire [POSE_W-1:0] serial_pose;
      wire [TIMESTAMP_W-1:0] serial_timestamp;
      wire signed [RESULT_W-1:0] serial_world_x;
      wire signed [RESULT_W-1:0] serial_world_y;

      aer_tx16_pose_affine2d_k4_serial #(
        .FIFO_DEPTH(FIFO_DEPTH), .POSE_W(POSE_W), .SENSOR_W(SENSOR_W),
        .RESULT_W(RESULT_W), .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W),
        .FRAC_W(FRAC_W), .TIMESTAMP_W(TIMESTAMP_W),
        .GUARD_COUNT_W(COUNT_W),
        .X_MIN(0), .X_MAX(31), .Y_MIN(0), .Y_MAX(31)
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
        .tile_origin_x({SENSOR_W{1'b0}}),
        .tile_origin_y({SENSOR_W{1'b0}}),
        .world_valid(serial_valid), .world_ready(serial_world_ready),
        .mapped_valid(serial_mapped), .pose_found(serial_found),
        .in_range(serial_range), .sensor_x_out(serial_sensor_x),
        .sensor_y_out(serial_sensor_y), .bank_id_out(serial_bank),
        .polarity_out(serial_polarity), .pose_version_out(serial_pose),
        .occurrence_timestamp_out(serial_timestamp),
        .world_x_out(serial_world_x), .world_y_out(serial_world_y)
      );

      assign debug_batch_valid = dut.u_banked.batch_valid;
      assign debug_batch_x_flat = dut.u_banked.batch_x_flat;
      assign debug_batch_y_flat = dut.u_banked.batch_y_flat;
      assign debug_batch_polarity = dut.u_banked.batch_polarity;
      assign debug_batch_pose_flat = dut.u_banked.batch_pose_flat;
      assign debug_batch_time_flat = dut.u_banked.batch_time_flat;
      assign debug_fifo_occupancy_flat = dut.u_banked.fifo_occupancy_flat;
      assign debug_serial_valid = serial_valid;
      assign debug_serial_ready = serial_world_ready;
      assign debug_serial_payload = {
        serial_bank, serial_mapped, serial_found, serial_range,
        serial_sensor_x, serial_sensor_y, serial_polarity, serial_pose,
        serial_timestamp, serial_world_x, serial_world_y
      };
      for (serialized_pose_index = 0; serialized_pose_index < POSE_IDS;
           serialized_pose_index = serialized_pose_index + 1) begin: pose_busy
        assign debug_pose_busy[serialized_pose_index] =
          |dut.u_banked.u_pose_guard.outstanding[serialized_pose_index];
      end

      genvar serial_lane;
      for (serial_lane = 0; serial_lane < K;
           serial_lane = serial_lane + 1) begin: expose_selected_bank
        assign world_valid[serial_lane] =
          serial_valid && (serial_bank == serial_lane);
        assign world_fire[serial_lane] =
          serial_valid && serial_world_ready && (serial_bank == serial_lane);
        assign mapped_valid[serial_lane] =
          serial_valid && (serial_bank == serial_lane) && serial_mapped;
        assign pose_found[serial_lane] =
          serial_valid && (serial_bank == serial_lane) && serial_found;
        assign in_range[serial_lane] =
          serial_valid && (serial_bank == serial_lane) && serial_range;
        assign sensor_x_flat[serial_lane*SENSOR_W +: SENSOR_W] =
          serial_sensor_x;
        assign sensor_y_flat[serial_lane*SENSOR_W +: SENSOR_W] =
          serial_sensor_y;
        assign polarity_out[serial_lane] = serial_polarity;
        assign pose_flat[serial_lane*POSE_W +: POSE_W] = serial_pose;
        assign timestamp_flat[serial_lane*TIMESTAMP_W +: TIMESTAMP_W] =
          serial_timestamp;
        assign world_x_flat[serial_lane*RESULT_W +: RESULT_W] =
          serial_world_x;
        assign world_y_flat[serial_lane*RESULT_W +: RESULT_W] =
          serial_world_y;
      end
    end
  endgenerate

  always #5 clk = ~clk;

  // State: 1=accepted/pending, 2=delivered, 3=FIFO-dropped.
  reg [1:0] event_state [0:KEY_COUNT-1];
  reg record_polarity [0:KEY_COUNT-1];
  reg [POSE_W-1:0] record_pose [0:KEY_COUNT-1];
  integer latency_hist [0:MAX_LATENCY];

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
  integer accepted_count;
  integer aer_drop_count;
  integer fifo_drop_count;
  integer delivered_count;
  integer pending_count;
  integer latency_total;
  integer latency_max;
  integer latency_p50;
  integer latency_p99;
  integer error_count;
  integer pose_commit_count;
  integer i;
  integer lane;
  integer bank;
  integer source;
  integer key;
  integer got_source;
  integer got_key;
  integer got_time;
  integer got_pose;
  integer got_pol;
  integer got_x;
  integer got_y;
  integer expected_x;
  integer expected_y;
  integer drop_x;
  integer drop_y;
  integer drop_pose;
  integer drop_time;
  integer drop_pol;
  integer latency;
  integer cumulative;
  integer target50;
  integer target99;
  integer found50;
  integer found99;
  integer cycle_addr;
  integer cycle_pol;
  integer overlap_addr;

  task automatic fail;
    input [1023:0] message;
    begin
      error_count = error_count + 1;
      $display("FAIL cycle=%0d K=%0d depth=%0d: %0s",
               replay_cycle, K, FIFO_DEPTH, message);
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

  task automatic check_outputs;
    begin
      for (bank = 0; bank < K; bank = bank + 1) begin
        if (world_fire[bank]) begin
          got_time = timestamp_flat[bank*TIMESTAMP_W +: TIMESTAMP_W];
          got_pose = pose_flat[bank*POSE_W +: POSE_W];
          got_pol = polarity_out[bank];
          got_x = $signed(world_x_flat[bank*RESULT_W +: RESULT_W]);
          got_y = $signed(world_y_flat[bank*RESULT_W +: RESULT_W]);
          drop_x = sensor_x_flat[bank*SENSOR_W +: SENSOR_W];
          drop_y = sensor_y_flat[bank*SENSOR_W +: SENSOR_W];
          if (drop_x > 3 || drop_y > 3) begin
            fail("output source coordinate escaped the 4x4 tile");
          end else begin
            got_source = drop_y * 4 + drop_x;
            got_key = got_time * 16 + got_source;
            calculate_world(got_pose, got_source, expected_x, expected_y);
            if (event_state[got_key] !== 2'd1) begin
              fail("output is unknown, FIFO-dropped, or duplicated");
            end else begin
              if ((drop_x % K) != bank)
                fail("output arrived from the wrong static lane-mod-K bank");
              if (record_pose[got_key] != got_pose
                  || record_polarity[got_key] != got_pol
                  || got_x != expected_x || got_y != expected_y
                  || !mapped_valid[bank] || !pose_found[bank]
                  || !in_range[bank])
                fail("output occurrence metadata, coordinate, or validity mismatch");
              event_state[got_key] = 2'd2;
              pending_count = pending_count - 1;
              delivered_count = delivered_count + 1;
              latency = replay_cycle - got_time;
              if (latency < 0 || latency > MAX_LATENCY) begin
                fail("timestamp-derived latency is outside histogram range");
              end else begin
                latency_hist[latency] = latency_hist[latency] + 1;
                latency_total = latency_total + latency;
                if (latency > latency_max)
                  latency_max = latency;
              end
            end
          end
        end else if (!world_valid[bank]
                     && (mapped_valid[bank] || pose_found[bank]
                         || in_range[bank])) begin
          fail("inactive output bank asserted validity metadata");
        end
      end
    end
  endtask

  task automatic check_serial_stall;
    begin
      if (SERIALIZE_OUTPUT != 0) begin
        if (serial_stall_held) begin
          if (!debug_serial_valid)
            fail("serialized output valid dropped while stalled");
          else if (debug_serial_payload !== serial_stall_payload)
            fail("serialized output payload or bank changed while stalled");
        end
        serial_stall_held = debug_serial_valid && !debug_serial_ready;
        if (debug_serial_valid && !debug_serial_ready)
          serial_stall_payload = debug_serial_payload;
      end
    end
  endtask

  task automatic process_fifo_drops;
    begin
      if ((fifo_overflow & ~debug_batch_valid) != 0)
        fail("FIFO overflow asserted for an inactive adapter lane");
      for (lane = 0; lane < 8; lane = lane + 1) begin
        if (fifo_overflow[lane]) begin
          drop_x = debug_batch_x_flat[lane*SENSOR_W +: SENSOR_W];
          drop_y = debug_batch_y_flat[lane*SENSOR_W +: SENSOR_W];
          drop_pol = debug_batch_polarity[lane];
          drop_pose = debug_batch_pose_flat[lane*POSE_W +: POSE_W];
          drop_time = debug_batch_time_flat[lane*TIMESTAMP_W +: TIMESTAMP_W];
          got_source = drop_y * 4 + drop_x;
          got_key = drop_time * 16 + got_source;
          if (drop_x > 3 || drop_y > 3) begin
            fail("FIFO drop carried an invalid source coordinate");
          end else if ((lane % K) != (drop_x % K)) begin
            fail("FIFO drop escaped its static lane-mod-K bank");
          end else if (event_state[got_key] !== 2'd1) begin
            fail("FIFO drop is unknown or duplicated");
          end else begin
            if (record_pose[got_key] != drop_pose
                || record_polarity[got_key] != drop_pol)
              fail("FIFO drop occurrence metadata mismatch");
            event_state[got_key] = 2'd3;
            pending_count = pending_count - 1;
            fifo_drop_count = fifo_drop_count + 1;
          end
        end
      end
    end
  endtask

  task automatic process_inputs;
    begin
      if ((aer_overrun & ~arrival) != 0)
        fail("AER overrun asserted without an arrival");
      for (source = 0; source < 16; source = source + 1) begin
        if (arrival[source]) begin
          generated_count = generated_count + 1;
          if (aer_overrun[source]) begin
            aer_drop_count = aer_drop_count + 1;
          end else begin
            accepted_count = accepted_count + 1;
            key = occurrence_timestamp * 16 + source;
            if (event_state[key] === 2'd1 || event_state[key] === 2'd2
                || event_state[key] === 2'd3)
              fail("trace reused one timestamp/source key");
            event_state[key] = 2'd1;
            record_polarity[key] = polarity_in[source];
            record_pose[key] = occurrence_pose_version;
            pending_count = pending_count + 1;
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
      if (SERIALIZE_OUTPUT != 0 && SERIAL_STALL_OUTPUT != 0) begin
        ready_lfsr = {ready_lfsr[14:0],
                      ready_lfsr[15] ^ ready_lfsr[13]
                      ^ ready_lfsr[12] ^ ready_lfsr[10]};
        serial_world_ready = ready_lfsr[0] | ready_lfsr[3];
      end else begin
        serial_world_ready = 1'b1;
      end
      #1;
      check_serial_stall;
      check_outputs;
      process_fifo_drops;
      process_inputs;
      @(posedge clk);
      #1;
      if (pose_accounting_error)
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
      if (!pose_wr_ready || pose_wr_rejected || !pose_wr_commit)
        fail("initial pose write did not commit");
      @(posedge clk);
      #1;
      pose_commit_count = pose_commit_count + 1;
    end
  endtask

  task automatic calculate_percentiles;
    begin
      target50 = (delivered_count + 1) / 2;
      target99 = (delivered_count * 99 + 99) / 100;
      cumulative = 0;
      found50 = 0;
      found99 = 0;
      for (i = 0; i <= MAX_LATENCY; i = i + 1) begin
        cumulative = cumulative + latency_hist[i];
        if (!found50 && cumulative >= target50) begin
          latency_p50 = i;
          found50 = 1;
        end
        if (!found99 && cumulative >= target99) begin
          latency_p99 = i;
          found99 = 1;
        end
      end
    end
  endtask

  initial begin
    if (K != 2 && K != 4)
      $fatal(1, "trace TB supports compile-time K=2 or K=4");
    if (SERIALIZE_OUTPUT != 0 && K != 4)
      $fatal(1, "serialized trace mode requires K=4");

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
    serial_world_ready = 1'b1;
    ready_lfsr = 16'h1ace;
    serial_stall_held = 1'b0;
    serial_stall_payload = 0;
    replay_cycle = 0;
    first_trace_cycle = -1;
    last_trace_cycle = -1;
    trace_rows = 0;
    event_cycles = 0;
    idle_cycles = 0;
    drain_cycles = 0;
    generated_count = 0;
    accepted_count = 0;
    aer_drop_count = 0;
    fifo_drop_count = 0;
    delivered_count = 0;
    pending_count = 0;
    latency_total = 0;
    latency_max = 0;
    latency_p50 = 0;
    latency_p99 = 0;
    error_count = 0;
    pose_commit_count = 0;
    for (i = 0; i <= MAX_LATENCY; i = i + 1)
      latency_hist[i] = 0;

    if (!$value$plusargs("TRACE_FILE=%s", trace_file_r))
      $fatal(1, "trace path is required via +TRACE_FILE=");
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

    while (pending_count != 0 && drain_cycles < DRAIN_LIMIT) begin
      step_one_trace_cycle(16'd0, 16'd0);
      drain_cycles = drain_cycles + 1;
    end
    repeat (3) begin
      step_one_trace_cycle(16'd0, 16'd0);
      drain_cycles = drain_cycles + 1;
    end

    if (pending_count != 0)
      fail("bounded drain did not resolve every accepted event");
    if (|debug_fifo_occupancy_flat || |world_valid)
      fail("FIFO or transform remained nonempty after drain");
    for (i = 0; i < POSE_IDS; i = i + 1)
      if (debug_pose_busy[i])
        fail("pose guard leaked an outstanding reference");
    pose_wr_id = 0;
    #1;
    if (!pose_wr_ready)
      fail("pose write did not return ready after drain");
    if (pose_accounting_error)
      fail("pose guard accounting error is sticky after trace");

    if (generated_count != accepted_count + aer_drop_count)
      fail("generated/AER-accepted/AER-drop conservation mismatch");
    if (accepted_count != fifo_drop_count + delivered_count)
      fail("accepted/FIFO-drop/delivered conservation mismatch");
    if (delivered_count == 0)
      fail("latency population is empty");

    calculate_percentiles;
    $display("TRACE_TIMING_MODE=exact_cycle_field trace=%0s rows=%0d first=%0d last=%0d event_cycles=%0d idle_cycles=%0d drain_cycles=%0d",
             trace_file_r, trace_rows, first_trace_cycle, last_trace_cycle,
             event_cycles, idle_cycles, drain_cycles);
    $display("TRACE_POSE_MODE=synthetic_cycle_mod_3 (addrpol trace has no pose field)");
    $display("BANKED_TRACE K=%0d per_bank_depth=%0d total_fifo_slots=%0d generated=%0d accepted=%0d aer_overrun=%0d fifo_overflow=%0d delivered=%0d latency_total=%0d p50=%0d p99=%0d max=%0d",
             K, FIFO_DEPTH, K*FIFO_DEPTH, generated_count, accepted_count,
             aer_drop_count, fifo_drop_count, delivered_count, latency_total,
             latency_p50, latency_p99, latency_max);
    $display("TRACE_GUARD_DRAIN_PASS pose_commits=%0d", pose_commit_count);
    if (error_count == 0) begin
      $display("STAGE2_BANKED_UZH_TRACE_PASS");
      $fclose(fd);
      $finish;
    end else begin
      $fclose(fd);
      $fatal(1, "STAGE2_BANKED_UZH_TRACE_FAIL errors=%0d", error_count);
    end
  end
endmodule
