`timescale 1ns/1ps

module tb_aer_tx16_pose_affine2d_banked_backpressure #(
  parameter integer K = 2
);
  localparam integer POSE_W = 3;
  localparam integer SENSOR_W = 6;
  localparam integer RESULT_W = 16;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer FRAC_W = 14;
  localparam integer TIMESTAMP_W = 24;
  localparam integer FIFO_DEPTH = 8;
  localparam integer GUARD_COUNT_W = 9;
  localparam integer RANDOM_CYCLES = 4000;
  localparam integer MAX_RECORDS = 50000;
  localparam integer MAX_PER_SOURCE = RANDOM_CYCLES + 64;
  localparam integer MAX_PER_BANK = RANDOM_CYCLES * 4 + 256;
  localparam integer Q = (1 << FRAC_W);
  localparam integer ORIGIN_X = 10;
  localparam integer ORIGIN_Y = 20;
  localparam integer EVENT_W = 2*SENSOR_W + 1 + POSE_W + TIMESTAMP_W;
  localparam integer OCC_W = $clog2(FIFO_DEPTH + 1);

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
  wire [K-1:0] world_valid;
  reg [K-1:0] world_ready;
  wire [K-1:0] mapped_valid;
  wire [K-1:0] pose_found;
  wire [K-1:0] in_range;
  wire [K*SENSOR_W-1:0] sensor_x_out_flat;
  wire [K*SENSOR_W-1:0] sensor_y_out_flat;
  wire [K-1:0] polarity_out;
  wire [K*POSE_W-1:0] pose_version_out_flat;
  wire [K*TIMESTAMP_W-1:0] occurrence_timestamp_out_flat;
  wire [K*RESULT_W-1:0] world_x_out_flat;
  wire [K*RESULT_W-1:0] world_y_out_flat;

  aer_tx16_pose_affine2d_banked #(
    .K(K), .POSE_W(POSE_W), .SENSOR_W(SENSOR_W),
    .RESULT_W(RESULT_W), .MATRIX_W(MATRIX_W),
    .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
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
    .in_range(in_range), .sensor_x_out_flat(sensor_x_out_flat),
    .sensor_y_out_flat(sensor_y_out_flat),
    .polarity_out(polarity_out),
    .pose_version_out_flat(pose_version_out_flat),
    .occurrence_timestamp_out_flat(occurrence_timestamp_out_flat),
    .world_x_out_flat(world_x_out_flat),
    .world_y_out_flat(world_y_out_flat)
  );

  always #5 clk = ~clk;

  // Record states: 1=AER, 2=bank FIFO, 3=transform output,
  // 4=FIFO terminal drop, 5=delivered.
  integer rec_state [0:MAX_RECORDS-1];
  integer rec_source [0:MAX_RECORDS-1];
  integer rec_sx [0:MAX_RECORDS-1];
  integer rec_sy [0:MAX_RECORDS-1];
  integer rec_polarity [0:MAX_RECORDS-1];
  integer rec_pose [0:MAX_RECORDS-1];
  reg [TIMESTAMP_W-1:0] rec_time [0:MAX_RECORDS-1];
  integer rec_adapter_lane [0:MAX_RECORDS-1];
  integer rec_bank [0:MAX_RECORDS-1];

  integer source_queue [0:(16*MAX_PER_SOURCE)-1];
  integer source_head [0:15];
  integer source_tail [0:15];
  integer bank_queue [0:(K*MAX_PER_BANK)-1];
  integer bank_head [0:K-1];
  integer bank_tail [0:K-1];
  integer output_record [0:K-1];
  integer next_output_record [0:K-1];
  integer guard_model [0:(1<<POSE_W)-1];
  integer guard_next [0:(1<<POSE_W)-1];

  integer record_count;
  integer pending_count;
  integer generated_count;
  integer accepted_count;
  integer aer_drop_count;
  integer fifo_drop_count;
  integer transform_capture_count;
  integer delivered_count;
  integer error_count;
  integer cycle_count;
  integer random_cycle_count;
  integer drain_cycle_count;
  integer rng_seed;
  integer timestamp_increment;
  integer sparse_cycles;
  integer burst_cycles;
  integer polarity0_count;
  integer polarity1_count;
  integer pose0_delivered;
  integer pose1_delivered;
  integer expansion_by_lane [0:7];
  integer delivery_by_bank [0:K-1];
  integer stall_by_bank [0:K-1];

  integer i;
  integer random_iter;
  integer source;
  integer lane;
  integer bank;
  integer pose_scan;
  integer draw;
  integer sparse_events;
  integer source_pick;

  reg held_valid [0:K-1];
  reg held_mapped [0:K-1];
  reg held_found [0:K-1];
  reg held_range [0:K-1];
  reg [SENSOR_W-1:0] held_sx [0:K-1];
  reg [SENSOR_W-1:0] held_sy [0:K-1];
  reg held_polarity [0:K-1];
  reg [POSE_W-1:0] held_pose [0:K-1];
  reg [TIMESTAMP_W-1:0] held_time [0:K-1];
  reg signed [RESULT_W-1:0] held_wx [0:K-1];
  reg signed [RESULT_W-1:0] held_wy [0:K-1];

  function integer source_from_coordinate;
    input integer sx;
    input integer sy;
    integer local_x;
    integer local_y;
    begin
      local_x = sx - ORIGIN_X;
      local_y = sy - ORIGIN_Y;
      if (local_x < 0 || local_x > 3 || local_y < 0 || local_y > 3)
        source_from_coordinate = -1;
      else
        source_from_coordinate = local_y*4 + local_x;
    end
  endfunction

  task automatic fail;
    input [1023:0] message;
    begin
      error_count = error_count + 1;
      if (error_count <= 30)
        $display("FAIL K=%0d cycle=%0d random_cycle=%0d: %0s",
                 K, cycle_count, random_cycle_count, message);
    end
  endtask

  task automatic check_stalled_outputs;
    begin
      for (bank = 0; bank < K; bank = bank + 1) begin
        if (held_valid[bank]) begin
          if (!world_valid[bank] ||
              mapped_valid[bank] !== held_mapped[bank] ||
              pose_found[bank] !== held_found[bank] ||
              in_range[bank] !== held_range[bank] ||
              sensor_x_out_flat[bank*SENSOR_W +: SENSOR_W]
                !== held_sx[bank] ||
              sensor_y_out_flat[bank*SENSOR_W +: SENSOR_W]
                !== held_sy[bank] ||
              polarity_out[bank] !== held_polarity[bank] ||
              pose_version_out_flat[bank*POSE_W +: POSE_W]
                !== held_pose[bank] ||
              occurrence_timestamp_out_flat[
                bank*TIMESTAMP_W +: TIMESTAMP_W] !== held_time[bank] ||
              world_x_out_flat[bank*RESULT_W +: RESULT_W]
                !== held_wx[bank] ||
              world_y_out_flat[bank*RESULT_W +: RESULT_W]
                !== held_wy[bank])
            fail("one output lane changed valid/payload/status while stalled");
        end
      end
    end
  endtask

  task automatic check_and_consume_outputs;
    integer out_idx;
    integer want_wx;
    integer want_wy;
    begin
      for (bank = 0; bank < K; bank = bank + 1) begin
        next_output_record[bank] = output_record[bank];
        if (output_record[bank] < 0) begin
          if (world_valid[bank])
            fail("phantom output event without a transform record");
          if (mapped_valid[bank])
            fail("mapped_valid asserted without world_valid");
        end else begin
          out_idx = output_record[bank];
          want_wx = rec_sx[out_idx] + ((rec_pose[out_idx] == 1) ? 2 : 0);
          want_wy = rec_sy[out_idx] - ((rec_pose[out_idx] == 1) ? 1 : 0);
          if (rec_state[out_idx] != 3)
            fail("output record is not in transform state");
          if (!world_valid[bank])
            fail("expected transform record is absent from output lane");
          if (rec_bank[out_idx] != bank ||
              sensor_x_out_flat[bank*SENSOR_W +: SENSOR_W]
                !== rec_sx[out_idx] ||
              sensor_y_out_flat[bank*SENSOR_W +: SENSOR_W]
                !== rec_sy[out_idx] ||
              polarity_out[bank] !== rec_polarity[out_idx][0] ||
              pose_version_out_flat[bank*POSE_W +: POSE_W]
                !== rec_pose[out_idx] ||
              occurrence_timestamp_out_flat[
                bank*TIMESTAMP_W +: TIMESTAMP_W] !== rec_time[out_idx])
            fail("output bank routing or event metadata mismatch");
          if (!pose_found[bank] || !in_range[bank] || !mapped_valid[bank] ||
              $signed(world_x_out_flat[
                bank*RESULT_W +: RESULT_W]) != want_wx ||
              $signed(world_y_out_flat[
                bank*RESULT_W +: RESULT_W]) != want_wy)
            fail("affine world coordinate or validity status mismatch");

          if (world_valid[bank] && world_ready[bank]) begin
            rec_state[out_idx] = 5;
            next_output_record[bank] = -1;
            delivered_count = delivered_count + 1;
            delivery_by_bank[bank] = delivery_by_bank[bank] + 1;
            pending_count = pending_count - 1;
            if (rec_pose[out_idx] == 0)
              pose0_delivered = pose0_delivered + 1;
            else if (rec_pose[out_idx] == 1)
              pose1_delivered = pose1_delivered + 1;
          end
        end
      end
    end
  endtask

  task automatic process_transform_captures;
    integer capture_idx;
    begin
      for (bank = 0; bank < K; bank = bank + 1) begin
        if (dut.transform_capture[bank]) begin
          if (bank_head[bank] >= bank_tail[bank]) begin
            fail("phantom or duplicate bank FIFO dequeue");
          end else begin
            capture_idx = bank_queue[
              bank*MAX_PER_BANK + bank_head[bank]];
            bank_head[bank] = bank_head[bank] + 1;
            if (rec_state[capture_idx] != 2 ||
                rec_bank[capture_idx] != bank)
              fail("transform captured a record outside its assigned bank");
            if (dut.fifo_sensor_x_flat[bank*SENSOR_W +: SENSOR_W]
                  !== rec_sx[capture_idx] ||
                dut.fifo_sensor_y_flat[bank*SENSOR_W +: SENSOR_W]
                  !== rec_sy[capture_idx] ||
                dut.fifo_polarity[bank]
                  !== rec_polarity[capture_idx][0] ||
                dut.fifo_pose_flat[bank*POSE_W +: POSE_W]
                  !== rec_pose[capture_idx] ||
                dut.fifo_time_flat[bank*TIMESTAMP_W +: TIMESTAMP_W]
                  !== rec_time[capture_idx])
              fail("bank FIFO order or metadata changed before transform");
            if (next_output_record[bank] >= 0)
              fail("transform overwrote an independently stalled output");
            rec_state[capture_idx] = 3;
            next_output_record[bank] = capture_idx;
            transform_capture_count = transform_capture_count + 1;
            if (guard_next[rec_pose[capture_idx]] == 0)
              fail("pose guard oracle underflow at transform capture");
            else
              guard_next[rec_pose[capture_idx]] =
                guard_next[rec_pose[capture_idx]] - 1;
          end
        end
      end
    end
  endtask

  task automatic process_expansion_batch;
    integer expanded_source;
    integer expanded_idx;
    integer expanded_sx;
    integer expanded_sy;
    integer expected_bank;
    integer expected_overflow;
    integer actual_overflow;
    integer occupancy;
    begin
      if ((fifo_overflow & ~dut.batch_valid) != 0)
        fail("FIFO overflow asserted on an inactive adapter lane");

      for (lane = 0; lane < 8; lane = lane + 1) begin
        if (dut.batch_valid[lane]) begin
          expansion_by_lane[lane] = expansion_by_lane[lane] + 1;
          expanded_sx = dut.batch_x_flat[lane*SENSOR_W +: SENSOR_W];
          expanded_sy = dut.batch_y_flat[lane*SENSOR_W +: SENSOR_W];
          expanded_source = source_from_coordinate(expanded_sx, expanded_sy);
          if (expanded_source < 0) begin
            fail("adapter produced an invalid local sensor coordinate");
          end else if (source_head[expanded_source] >=
                       source_tail[expanded_source]) begin
            fail("phantom or duplicate AER expansion");
          end else begin
            expanded_idx = source_queue[
              expanded_source*MAX_PER_SOURCE +
              source_head[expanded_source]];
            source_head[expanded_source] =
              source_head[expanded_source] + 1;
            if (rec_state[expanded_idx] != 1 ||
                rec_source[expanded_idx] != expanded_source ||
                rec_sx[expanded_idx] != expanded_sx ||
                rec_sy[expanded_idx] != expanded_sy ||
                rec_polarity[expanded_idx] != dut.batch_polarity[lane] ||
                rec_pose[expanded_idx] !=
                  dut.batch_pose_flat[lane*POSE_W +: POSE_W] ||
                rec_time[expanded_idx] !==
                  dut.batch_time_flat[lane*TIMESTAMP_W +: TIMESTAMP_W])
              fail("AER expansion changed metadata or per-source order");

            expected_bank = lane % K;
            occupancy = bank_tail[expected_bank] - bank_head[expected_bank];
            expected_overflow = (occupancy >= FIFO_DEPTH);
            actual_overflow = fifo_overflow[lane];
            if (actual_overflow != expected_overflow)
              fail("FIFO overflow differs from same-cycle-pop space oracle");
            rec_adapter_lane[expanded_idx] = lane;
            rec_bank[expanded_idx] = expected_bank;
            if (actual_overflow) begin
              rec_state[expanded_idx] = 4;
              fifo_drop_count = fifo_drop_count + 1;
              pending_count = pending_count - 1;
              if (guard_next[rec_pose[expanded_idx]] == 0)
                fail("pose guard oracle underflow at FIFO terminal drop");
              else
                guard_next[rec_pose[expanded_idx]] =
                  guard_next[rec_pose[expanded_idx]] - 1;
            end else begin
              if (bank_tail[expected_bank] >= MAX_PER_BANK)
                $fatal(1, "bank queue capacity exceeded");
              rec_state[expanded_idx] = 2;
              bank_queue[expected_bank*MAX_PER_BANK +
                         bank_tail[expected_bank]] = expanded_idx;
              bank_tail[expected_bank] = bank_tail[expected_bank] + 1;
            end
          end
        end
      end
    end
  endtask

  task automatic process_arrivals;
    integer depth;
    integer expected_overrun;
    integer new_idx;
    begin
      if ((aer_overrun & ~arrival) != 0)
        fail("AER overrun asserted without a matching arrival");
      for (source = 0; source < 16; source = source + 1) begin
        depth = source_tail[source] - source_head[source];
        if (depth < 0 || depth > 2)
          fail("software source depth left the hardware 0..2 range");
        expected_overrun = arrival[source] && (depth == 2);
        if (aer_overrun[source] !== expected_overrun[0])
          fail("AER overrun differs from pre-edge source depth");

        if (arrival[source]) begin
          generated_count = generated_count + 1;
          if (polarity_in[source])
            polarity1_count = polarity1_count + 1;
          else
            polarity0_count = polarity0_count + 1;
          if (aer_overrun[source]) begin
            aer_drop_count = aer_drop_count + 1;
          end else begin
            if (record_count >= MAX_RECORDS)
              $fatal(1, "record table capacity exceeded");
            if (source_tail[source] >= MAX_PER_SOURCE)
              $fatal(1, "source queue capacity exceeded");
            new_idx = record_count;
            record_count = record_count + 1;
            rec_state[new_idx] = 1;
            rec_source[new_idx] = source;
            rec_sx[new_idx] = ORIGIN_X + (source & 3);
            rec_sy[new_idx] = ORIGIN_Y + (source >> 2);
            rec_polarity[new_idx] = polarity_in[source];
            rec_pose[new_idx] = occurrence_pose_version;
            rec_time[new_idx] = occurrence_timestamp;
            rec_adapter_lane[new_idx] = -1;
            rec_bank[new_idx] = -1;
            source_queue[source*MAX_PER_SOURCE + source_tail[source]] =
              new_idx;
            source_tail[source] = source_tail[source] + 1;
            accepted_count = accepted_count + 1;
            pending_count = pending_count + 1;
            guard_next[occurrence_pose_version] =
              guard_next[occurrence_pose_version] + 1;
          end
        end
      end
    end
  endtask

  task automatic sample_before_edge;
    integer conservation_total;
    begin
      check_stalled_outputs;
      check_and_consume_outputs;
      for (pose_scan = 0; pose_scan < (1 << POSE_W);
           pose_scan = pose_scan + 1)
        guard_next[pose_scan] = guard_model[pose_scan];

      // Pop/capture is processed before the incoming batch because the FIFO
      // explicitly makes same-cycle pop space available to new lanes.
      process_transform_captures;
      process_expansion_batch;
      // Registered expansions leave the source model before current arrivals
      // are tested against the depth-2 admission rule.
      process_arrivals;

      conservation_total = aer_drop_count + fifo_drop_count +
                           delivered_count + pending_count;
      if (generated_count != conservation_total)
        fail("generated != AERdrop + FIFOdrop + delivered + pending");
      if (pending_count < 0)
        fail("pending event count became negative");

      for (bank = 0; bank < K; bank = bank + 1) begin
        if (world_valid[bank] && !world_ready[bank])
          stall_by_bank[bank] = stall_by_bank[bank] + 1;
        held_valid[bank] = world_valid[bank] && !world_ready[bank];
        held_mapped[bank] = mapped_valid[bank];
        held_found[bank] = pose_found[bank];
        held_range[bank] = in_range[bank];
        held_sx[bank] =
          sensor_x_out_flat[bank*SENSOR_W +: SENSOR_W];
        held_sy[bank] =
          sensor_y_out_flat[bank*SENSOR_W +: SENSOR_W];
        held_polarity[bank] = polarity_out[bank];
        held_pose[bank] =
          pose_version_out_flat[bank*POSE_W +: POSE_W];
        held_time[bank] = occurrence_timestamp_out_flat[
          bank*TIMESTAMP_W +: TIMESTAMP_W];
        held_wx[bank] = world_x_out_flat[
          bank*RESULT_W +: RESULT_W];
        held_wy[bank] = world_y_out_flat[
          bank*RESULT_W +: RESULT_W];
      end
    end
  endtask

  task automatic update_after_edge;
    integer model_occupancy;
    begin
      #1;
      for (bank = 0; bank < K; bank = bank + 1) begin
        output_record[bank] = next_output_record[bank];
        model_occupancy = bank_tail[bank] - bank_head[bank];
        if (dut.fifo_occupancy_flat[bank*OCC_W +: OCC_W]
            !== model_occupancy[OCC_W-1:0])
          fail("bank FIFO occupancy differs from queue oracle");
      end
      for (pose_scan = 0; pose_scan < (1 << POSE_W);
           pose_scan = pose_scan + 1) begin
        guard_model[pose_scan] = guard_next[pose_scan];
        if (dut.u_pose_guard.outstanding[pose_scan]
            !== guard_model[pose_scan][GUARD_COUNT_W-1:0])
          fail("pose guard outstanding count mismatch");
      end
      if (pose_accounting_error)
        fail("pose guard accounting_error asserted");
      cycle_count = cycle_count + 1;
    end
  endtask

  task automatic randomize_cycle_inputs;
    reg [15:0] random_a;
    reg [15:0] random_b;
    integer pick_i;
    begin
      random_a = $random(rng_seed);
      random_b = $random(rng_seed);
      polarity_in = $random(rng_seed);
      draw = (($random(rng_seed) % 100) + 100) % 100;
      arrival = 0;
      if (draw < 65) begin
        sparse_cycles = sparse_cycles + 1;
        sparse_events = (($random(rng_seed) % 4) + 4) % 4;
        for (pick_i = 0; pick_i < sparse_events; pick_i = pick_i + 1) begin
          source_pick = (($random(rng_seed) % 16) + 16) % 16;
          arrival[source_pick] = 1'b1;
        end
      end else if (draw < 85) begin
        arrival = random_a & random_b;
      end else begin
        burst_cycles = burst_cycles + 1;
        case (draw & 3)
          0: arrival = 16'hffff;
          1: arrival = random_a | random_b;
          2: arrival = 16'haaaa;
          default: arrival = 16'h5555;
        endcase
      end

      occurrence_pose_version = $random(rng_seed) & 1;
      timestamp_increment = 1 + ($random(rng_seed) & 8'hff);
      occurrence_timestamp = occurrence_timestamp + timestamp_increment;
      for (bank = 0; bank < K; bank = bank + 1) begin
        draw = (($random(rng_seed) % 100) + 100) % 100;
        world_ready[bank] = (draw < 53);
      end
    end
  endtask

  task automatic run_random_cycle;
    begin
      @(negedge clk);
      randomize_cycle_inputs;
      #1;
      sample_before_edge;
      @(posedge clk);
      update_after_edge;
      random_cycle_count = random_cycle_count + 1;
    end
  endtask

  task automatic run_drain_cycle;
    begin
      @(negedge clk);
      arrival = 0;
      polarity_in = 0;
      occurrence_pose_version = 0;
      occurrence_timestamp = occurrence_timestamp + 1;
      world_ready = {K{1'b1}};
      #1;
      sample_before_edge;
      @(posedge clk);
      update_after_edge;
      drain_cycle_count = drain_cycle_count + 1;
    end
  endtask

  task automatic load_pose;
    input integer pose_id;
    input integer tx;
    input integer ty;
    begin
      @(negedge clk);
      pose_wr_id = pose_id;
      pose_wr_m00 = Q;
      pose_wr_m01 = 0;
      pose_wr_m10 = 0;
      pose_wr_m11 = Q;
      pose_wr_tx = tx;
      pose_wr_ty = ty;
      pose_wr_req = 1;
      #1;
      if (!pose_wr_ready || !pose_wr_commit || pose_wr_rejected)
        fail("idle pose preload was not accepted");
      @(posedge clk);
      #1;
      pose_wr_req = 0;
    end
  endtask

  initial begin
    rst = 1;
    arrival = 0;
    polarity_in = 0;
    occurrence_pose_version = 0;
    occurrence_timestamp = 24'h100000;
    pose_wr_req = 0;
    pose_wr_id = 0;
    pose_wr_m00 = 0;
    pose_wr_m01 = 0;
    pose_wr_m10 = 0;
    pose_wr_m11 = 0;
    pose_wr_tx = 0;
    pose_wr_ty = 0;
    tile_origin_x = ORIGIN_X;
    tile_origin_y = ORIGIN_Y;
    world_ready = 0;
    record_count = 0;
    pending_count = 0;
    generated_count = 0;
    accepted_count = 0;
    aer_drop_count = 0;
    fifo_drop_count = 0;
    transform_capture_count = 0;
    delivered_count = 0;
    error_count = 0;
    cycle_count = 0;
    random_cycle_count = 0;
    drain_cycle_count = 0;
    rng_seed = 32'h62b4d971;
    sparse_cycles = 0;
    burst_cycles = 0;
    polarity0_count = 0;
    polarity1_count = 0;
    pose0_delivered = 0;
    pose1_delivered = 0;
    for (i = 0; i < 16; i = i + 1) begin
      source_head[i] = 0;
      source_tail[i] = 0;
    end
    for (i = 0; i < K; i = i + 1) begin
      bank_head[i] = 0;
      bank_tail[i] = 0;
      output_record[i] = -1;
      next_output_record[i] = -1;
      delivery_by_bank[i] = 0;
      stall_by_bank[i] = 0;
      held_valid[i] = 0;
    end
    for (i = 0; i < (1 << POSE_W); i = i + 1) begin
      guard_model[i] = 0;
      guard_next[i] = 0;
    end
    for (i = 0; i < 8; i = i + 1)
      expansion_by_lane[i] = 0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 0;
    // Pose 0 is identity. Pose 1 translates (+2, -1).
    load_pose(0, 0, 0);
    load_pose(1, 2*Q, -Q);

    for (random_iter = 0; random_iter < RANDOM_CYCLES;
         random_iter = random_iter + 1)
      run_random_cycle;

    while (pending_count != 0 && drain_cycle_count < 2000)
      run_drain_cycle;
    repeat (4)
      run_drain_cycle;

    if (pending_count != 0)
      fail("event scoreboard did not fully drain");
    for (i = 0; i < 16; i = i + 1)
      if (source_head[i] != source_tail[i])
        fail("one source queue retained an event after drain");
    for (i = 0; i < K; i = i + 1) begin
      if (bank_head[i] != bank_tail[i] || output_record[i] >= 0)
        fail("one bank retained a FIFO/output event after drain");
      if (delivery_by_bank[i] == 0 || stall_by_bank[i] == 0)
        fail("one bank missed delivery or independent-stall coverage");
    end
    for (i = 0; i < record_count; i = i + 1)
      if (rec_state[i] != 4 && rec_state[i] != 5)
        fail("accepted event did not reach exactly one terminal state");
    for (i = 0; i < 8; i = i + 1)
      if (expansion_by_lane[i] == 0)
        fail("one adapter lane never exercised lane-mod-K routing");
    for (i = 0; i < (1 << POSE_W); i = i + 1)
      if (guard_model[i] != 0 || dut.u_pose_guard.outstanding[i] !== 0)
        fail("pose guard reference leaked after drain");

    if (generated_count != aer_drop_count + fifo_drop_count +
                           delivered_count)
      fail("final generated-event conservation identity failed");
    if (generated_count != accepted_count + aer_drop_count)
      fail("generated != accepted + AERdrop");
    if (accepted_count != fifo_drop_count + transform_capture_count)
      fail("accepted != FIFOdrop + transform capture");
    if (transform_capture_count != delivered_count)
      fail("transform capture != delivered after drain");
    if (aer_drop_count == 0 || fifo_drop_count == 0 ||
        sparse_cycles == 0 || burst_cycles == 0 ||
        polarity0_count == 0 || polarity1_count == 0 ||
        pose0_delivered == 0 || pose1_delivered == 0 ||
        pose_accounting_error)
      fail("required mixed-pose/saturation coverage was not reached");

    // A same-ID rewrite must become legal once every capture/drop has retired.
    @(negedge clk);
    pose_wr_id = 1;
    pose_wr_req = 1;
    pose_wr_m00 = Q;
    pose_wr_m01 = 0;
    pose_wr_m10 = 0;
    pose_wr_m11 = Q;
    pose_wr_tx = 0;
    pose_wr_ty = 0;
    #1;
    if (!pose_wr_ready || !pose_wr_commit || pose_wr_rejected)
      fail("pose rewrite remained blocked after complete drain");
    @(posedge clk);
    #1;
    if (pose_accounting_error)
      fail("final pose rewrite caused an accounting error");
    pose_wr_req = 0;

    $display("BANKED_BACKPRESSURE_COUNTS K=%0d cycles=%0d generated=%0d accepted=%0d aer_drop=%0d fifo_drop=%0d delivered=%0d pending=%0d",
             K, random_cycle_count, generated_count, accepted_count,
             aer_drop_count, fifo_drop_count, delivered_count, pending_count);
    $display("BANKED_BACKPRESSURE_COVERAGE K=%0d sparse=%0d burst=%0d pose0=%0d pose1=%0d drain=%0d",
             K, sparse_cycles, burst_cycles,
             pose0_delivered, pose1_delivered, drain_cycle_count);
    for (i = 0; i < K; i = i + 1)
      $display("BANKED_BACKPRESSURE_LANE K=%0d bank=%0d delivered=%0d stalled=%0d",
               K, i, delivery_by_bank[i], stall_by_bank[i]);
    if (error_count == 0) begin
      $display("AER_TX16_POSE_AFFINE2D_BANKED_BACKPRESSURE_PASS K=%0d", K);
      $finish;
    end else begin
      $fatal(1, "AER_TX16_POSE_AFFINE2D_BANKED_BACKPRESSURE_FAIL K=%0d errors=%0d",
             K, error_count);
    end
  end
endmodule
