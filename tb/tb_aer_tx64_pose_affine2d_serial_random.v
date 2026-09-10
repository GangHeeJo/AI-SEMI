`timescale 1ns/1ps

module tb_aer_tx64_pose_affine2d_serial_random;
  localparam integer POSE_W = 3;
  localparam integer SENSOR_W = 6;
  localparam integer RESULT_W = 16;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer FRAC_W = 14;
  localparam integer TIMESTAMP_W = 32;
  localparam integer FIFO_DEPTH = 32;
  localparam integer GUARD_COUNT_W = 10;
  localparam integer RANDOM_CYCLES = 10000;
  localparam integer MAX_RECORDS = 100000;
  localparam integer MAX_PER_SOURCE = 2048;
  localparam integer MAX_PER_TILE = RANDOM_CYCLES + FIFO_DEPTH + 64;
  localparam integer Q = (1 << FRAC_W);
  localparam integer BASE_X = 9;
  localparam integer BASE_Y = 17;
  localparam integer POSE_ID = 3;
  localparam integer OCC_W = $clog2(FIFO_DEPTH + 1);

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
  wire world_valid;
  reg world_ready;
  wire mapped_valid;
  wire pose_found;
  wire in_range;
  wire [SENSOR_W-1:0] sensor_x;
  wire [SENSOR_W-1:0] sensor_y;
  wire [1:0] tile_id;
  wire polarity;
  wire [POSE_W-1:0] pose_version;
  wire [TIMESTAMP_W-1:0] occurrence_timestamp_out;
  wire signed [RESULT_W-1:0] world_x;
  wire signed [RESULT_W-1:0] world_y;

  aer_tx64_pose_affine2d_serial #(
    .POSE_W(POSE_W), .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .TIMESTAMP_W(TIMESTAMP_W), .FIFO_DEPTH(FIFO_DEPTH),
    .GUARD_COUNT_W(GUARD_COUNT_W),
    .X_MIN(0), .X_MAX(63), .Y_MIN(0), .Y_MAX(63)
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
    .world_valid(world_valid), .world_ready(world_ready),
    .mapped_valid(mapped_valid), .pose_found(pose_found),
    .in_range(in_range), .sensor_x(sensor_x), .sensor_y(sensor_y),
    .tile_id(tile_id), .polarity(polarity),
    .pose_version(pose_version),
    .occurrence_timestamp_out(occurrence_timestamp_out),
    .world_x(world_x), .world_y(world_y)
  );

  always #5 clk = ~clk;

  // Record states: 1=AER, 2=tile FIFO, 3=transform/output,
  // 4=FIFO drop, 5=delivered. AER drops never enter the record table.
  integer rec_state [0:MAX_RECORDS-1];
  integer rec_source [0:MAX_RECORDS-1];
  integer rec_tile [0:MAX_RECORDS-1];
  integer rec_sx [0:MAX_RECORDS-1];
  integer rec_sy [0:MAX_RECORDS-1];
  integer rec_pol [0:MAX_RECORDS-1];
  integer rec_pose [0:MAX_RECORDS-1];
  reg [TIMESTAMP_W-1:0] rec_time [0:MAX_RECORDS-1];

  // Per-source queues independently model depth-2 AER ordering. Per-tile
  // queues model the serialized FIFO ordering after bitmap expansion.
  integer source_queue [0:(64*MAX_PER_SOURCE)-1];
  integer source_head [0:63];
  integer source_tail [0:63];
  integer tile_queue [0:(4*MAX_PER_TILE)-1];
  integer tile_head [0:3];
  integer tile_tail [0:3];

  integer record_count;
  integer output_record;
  integer next_output_record;
  integer pending_count;
  integer guard_count;
  integer guard_next;
  integer cycle_count;
  integer random_cycle_count;
  integer generated_count;
  integer aer_accepted_count;
  integer aer_drop_count;
  integer fifo_drop_count;
  integer fifo_enqueue_count;
  integer rr_count;
  integer delivered_count;
  integer expanded_count;
  integer error_count;
  integer stall_checks;
  integer stall_cycles;
  integer ready_cycles;
  integer sparse_cycles;
  integer burst_cycles;
  integer polarity0_count;
  integer polarity1_count;
  integer rng_seed;
  integer timestamp_step;
  integer drain_cycles;

  integer i;
  integer random_iter;
  integer lane;
  integer source;
  integer tile;
  integer idx;
  integer occupancy_before;
  integer expected_overflow;
  integer expected_aer_overrun;
  integer draw;
  integer sparse_events;

  reg held_valid;
  reg held_mapped;
  reg held_found;
  reg held_range;
  reg [SENSOR_W-1:0] held_sx;
  reg [SENSOR_W-1:0] held_sy;
  reg [1:0] held_tile;
  reg held_polarity;
  reg [POSE_W-1:0] held_pose;
  reg [TIMESTAMP_W-1:0] held_time;
  reg signed [RESULT_W-1:0] held_wx;
  reg signed [RESULT_W-1:0] held_wy;

  function integer source_from_coordinate;
    input integer tile_in;
    input integer sx_in;
    input integer sy_in;
    integer local_x;
    integer local_y;
    begin
      local_x = sx_in - BASE_X - ((tile_in & 1) * 4);
      local_y = sy_in - BASE_Y - (((tile_in >> 1) & 1) * 4);
      if (tile_in < 0 || tile_in > 3 ||
          local_x < 0 || local_x > 3 ||
          local_y < 0 || local_y > 3)
        source_from_coordinate = -1;
      else
        source_from_coordinate = tile_in*16 + local_y*4 + local_x;
    end
  endfunction

  task automatic fail;
    input [1023:0] message;
    begin
      error_count = error_count + 1;
      if (error_count <= 30)
        $display("FAIL cycle=%0d random_cycle=%0d: %0s",
                 cycle_count, random_cycle_count, message);
    end
  endtask

  task automatic check_stalled_output;
    begin
      if (held_valid) begin
        stall_checks = stall_checks + 1;
        if (world_valid !== 1'b1 || mapped_valid !== held_mapped ||
            pose_found !== held_found || in_range !== held_range ||
            sensor_x !== held_sx || sensor_y !== held_sy ||
            tile_id !== held_tile || polarity !== held_polarity ||
            pose_version !== held_pose ||
            occurrence_timestamp_out !== held_time ||
            world_x !== held_wx || world_y !== held_wy)
          fail("world output changed while stalled");
      end
    end
  endtask

  task automatic check_current_output;
    begin
      next_output_record = output_record;
      if (output_record < 0) begin
        if (world_valid !== 1'b0)
          fail("phantom world_valid without a transform record");
        if (mapped_valid !== 1'b0)
          fail("mapped_valid asserted without world_valid");
      end else begin
        if (rec_state[output_record] != 3)
          fail("output record is not in transform state");
        if (world_valid !== 1'b1)
          fail("expected transform record is missing at world output");
        if (sensor_x !== rec_sx[output_record] ||
            sensor_y !== rec_sy[output_record] ||
            tile_id !== rec_tile[output_record] ||
            polarity !== rec_pol[output_record][0] ||
            pose_version !== rec_pose[output_record] ||
            occurrence_timestamp_out !== rec_time[output_record])
          fail("world event metadata mismatch");
        if (pose_found !== 1'b1 || in_range !== 1'b1 ||
            mapped_valid !== 1'b1 ||
            $signed(world_x) != rec_sx[output_record] ||
            $signed(world_y) != rec_sy[output_record])
          fail("identity transform or validity mismatch");
        if (world_valid && world_ready) begin
          rec_state[output_record] = 5;
          delivered_count = delivered_count + 1;
          pending_count = pending_count - 1;
          next_output_record = -1;
        end
      end
    end
  endtask

  task automatic process_rr_handshake;
    integer rr_tile;
    integer rr_idx;
    begin
      if (dut.rr_handshake) begin
        rr_tile = dut.rr_source;
        if (tile_head[rr_tile] >= tile_tail[rr_tile]) begin
          fail("phantom or duplicate RR dequeue");
        end else begin
          rr_idx = tile_queue[rr_tile*MAX_PER_TILE + tile_head[rr_tile]];
          tile_head[rr_tile] = tile_head[rr_tile] + 1;
          if (rec_state[rr_idx] != 2)
            fail("RR dequeued a record outside the tile FIFO");
          if (dut.rr_sensor_x !== rec_sx[rr_idx] ||
              dut.rr_sensor_y !== rec_sy[rr_idx] ||
              dut.rr_source !== rec_tile[rr_idx] ||
              dut.rr_polarity !== rec_pol[rr_idx][0] ||
              dut.rr_pose !== rec_pose[rr_idx] ||
              dut.rr_time !== rec_time[rr_idx])
            fail("RR metadata or per-tile FIFO order mismatch");
          if (next_output_record >= 0)
            fail("RR overwrote an unconsumed transform record");
          rec_state[rr_idx] = 3;
          next_output_record = rr_idx;
          rr_count = rr_count + 1;
          guard_next = guard_next - 1;
        end
      end
    end
  endtask

  task automatic process_expanded_batches;
    integer expanded_source;
    integer expanded_idx;
    integer expanded_tile;
    integer expanded_sx;
    integer expanded_sy;
    integer expanded_pol;
    integer expanded_pose;
    reg [TIMESTAMP_W-1:0] expanded_time;
    integer actual_overflow;
    begin
      if ((tile_fifo_overflow & ~dut.expanded_valid) != 0)
        fail("FIFO overflow asserted on an inactive expansion lane");

      for (lane = 0; lane < 32; lane = lane + 1) begin
        if (dut.expanded_valid[lane]) begin
          expanded_count = expanded_count + 1;
          expanded_tile = lane / 8;
          expanded_sx = dut.expanded_x_flat[lane*SENSOR_W +: SENSOR_W];
          expanded_sy = dut.expanded_y_flat[lane*SENSOR_W +: SENSOR_W];
          expanded_pol = dut.expanded_polarity[lane];
          expanded_pose = dut.expanded_pose_flat[lane*POSE_W +: POSE_W];
          expanded_time = dut.expanded_time_flat[
            lane*TIMESTAMP_W +: TIMESTAMP_W];
          expanded_source = source_from_coordinate(
            expanded_tile, expanded_sx, expanded_sy);

          if (expanded_source < 0) begin
            fail("expanded event has an invalid tile/local coordinate");
          end else if (source_head[expanded_source] >=
                       source_tail[expanded_source]) begin
            fail("phantom or duplicate AER expansion");
          end else begin
            expanded_idx = source_queue[
              expanded_source*MAX_PER_SOURCE +
              source_head[expanded_source]];
            source_head[expanded_source] =
              source_head[expanded_source] + 1;
            if (rec_state[expanded_idx] != 1)
              fail("expanded record is not resident in the AER model");
            if (rec_source[expanded_idx] != expanded_source ||
                rec_tile[expanded_idx] != expanded_tile ||
                rec_sx[expanded_idx] != expanded_sx ||
                rec_sy[expanded_idx] != expanded_sy ||
                rec_pol[expanded_idx] != expanded_pol ||
                rec_pose[expanded_idx] != expanded_pose ||
                rec_time[expanded_idx] !== expanded_time)
              fail("AER expansion metadata or per-source order mismatch");

            occupancy_before = tile_tail[expanded_tile] -
                               tile_head[expanded_tile];
            expected_overflow = (occupancy_before >= FIFO_DEPTH);
            actual_overflow = tile_fifo_overflow[lane];
            if (actual_overflow != expected_overflow)
              fail("tile FIFO overflow does not match pre-edge space");

            if (actual_overflow) begin
              rec_state[expanded_idx] = 4;
              fifo_drop_count = fifo_drop_count + 1;
              pending_count = pending_count - 1;
              guard_next = guard_next - 1;
            end else begin
              if (tile_tail[expanded_tile] >= MAX_PER_TILE)
                $fatal(1, "tile queue capacity exceeded");
              rec_state[expanded_idx] = 2;
              tile_queue[expanded_tile*MAX_PER_TILE +
                         tile_tail[expanded_tile]] = expanded_idx;
              tile_tail[expanded_tile] = tile_tail[expanded_tile] + 1;
              fifo_enqueue_count = fifo_enqueue_count + 1;
            end
          end
        end
      end
    end
  endtask

  task automatic process_arrivals;
    integer new_idx;
    integer source_depth;
    integer expected_sx;
    integer expected_sy;
    begin
      if ((aer_overrun & ~arrival) != 0)
        fail("AER overrun asserted without an arrival");

      for (source = 0; source < 64; source = source + 1) begin
        source_depth = source_tail[source] - source_head[source];
        if (source_depth < 0 || source_depth > 2)
          fail("software AER depth is outside 0..2");
        expected_aer_overrun = arrival[source] && (source_depth == 2);
        if (aer_overrun[source] !== expected_aer_overrun[0])
          fail("AER overrun does not match pre-edge depth-2 state");

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
            expected_sx = BASE_X + ((source/16) & 1)*4 + (source & 3);
            expected_sy = BASE_Y + (((source/16) >> 1) & 1)*4 +
                          ((source % 16) >> 2);
            rec_state[new_idx] = 1;
            rec_source[new_idx] = source;
            rec_tile[new_idx] = source / 16;
            rec_sx[new_idx] = expected_sx;
            rec_sy[new_idx] = expected_sy;
            rec_pol[new_idx] = polarity_in[source];
            rec_pose[new_idx] = occurrence_pose_version;
            rec_time[new_idx] = occurrence_timestamp;
            source_queue[source*MAX_PER_SOURCE + source_tail[source]] =
              new_idx;
            source_tail[source] = source_tail[source] + 1;
            aer_accepted_count = aer_accepted_count + 1;
            pending_count = pending_count + 1;
            guard_next = guard_next + 1;
          end
        end
      end
    end
  endtask

  task automatic sample_before_edge;
    integer model_total;
    begin
      check_stalled_output;
      check_current_output;
      guard_next = guard_count;

      // A pop frees space for the expansion batch on this same edge.
      process_rr_handshake;
      process_expanded_batches;
      // Consume registered expansions before testing current source depths.
      process_arrivals;

      model_total = aer_drop_count + fifo_drop_count +
                    delivered_count + pending_count;
      if (generated_count != model_total)
        fail("generated != AERdrop + FIFOdrop + delivered + pending");
      if (pending_count < 0)
        fail("pending event count became negative");
      if (guard_next < 0)
        fail("pose guard oracle underflowed");

      held_valid = world_valid && !world_ready;
      held_mapped = mapped_valid;
      held_found = pose_found;
      held_range = in_range;
      held_sx = sensor_x;
      held_sy = sensor_y;
      held_tile = tile_id;
      held_polarity = polarity;
      held_pose = pose_version;
      held_time = occurrence_timestamp_out;
      held_wx = world_x;
      held_wy = world_y;
    end
  endtask

  task automatic update_after_edge;
    integer pose_scan;
    integer tile_scan;
    integer model_occupancy;
    begin
      output_record = next_output_record;
      guard_count = guard_next;
      #1;
      if (pose_accounting_error)
        fail("pose guard accounting_error asserted");
      for (pose_scan = 0; pose_scan < (1 << POSE_W);
           pose_scan = pose_scan + 1) begin
        if (pose_scan == POSE_ID) begin
          if (dut.u_pose_guard.outstanding[pose_scan]
              !== guard_count[GUARD_COUNT_W-1:0])
            fail("pose guard outstanding count mismatch");
        end else if (dut.u_pose_guard.outstanding[pose_scan] !== 0) begin
          fail("unused pose ID acquired an outstanding count");
        end
      end
      for (tile_scan = 0; tile_scan < 4; tile_scan = tile_scan + 1) begin
        model_occupancy = tile_tail[tile_scan] - tile_head[tile_scan];
        if (dut.fifo_occupancy_flat[tile_scan*OCC_W +: OCC_W]
            !== model_occupancy[OCC_W-1:0])
          fail("tile FIFO occupancy differs from queue oracle");
      end
    end
  endtask

  task automatic randomize_inputs;
    reg [63:0] random_a;
    reg [63:0] random_b;
    integer source_pick;
    integer pick_i;
    begin
      random_a = {$random(rng_seed), $random(rng_seed)};
      random_b = {$random(rng_seed), $random(rng_seed)};
      polarity_in = {$random(rng_seed), $random(rng_seed)};
      draw = (($random(rng_seed) % 100) + 100) % 100;
      arrival = 64'd0;
      if (draw < 80) begin
        sparse_cycles = sparse_cycles + 1;
        sparse_events = (($random(rng_seed) % 5) + 5) % 5;
        for (pick_i = 0; pick_i < sparse_events; pick_i = pick_i + 1) begin
          source_pick = (($random(rng_seed) % 64) + 64) % 64;
          arrival[source_pick] = 1'b1;
        end
      end else if (draw < 95) begin
        arrival = random_a & random_b;
      end else begin
        burst_cycles = burst_cycles + 1;
        case (draw & 3)
          0: arrival = 64'hffff_ffff_ffff_ffff;
          1: arrival = random_a | random_b;
          2: arrival = 64'haaaa_aaaa_aaaa_aaaa;
          default: arrival = 64'h5555_5555_5555_5555;
        endcase
      end

      draw = (($random(rng_seed) % 100) + 100) % 100;
      world_ready = (draw < 57);
      if (world_ready)
        ready_cycles = ready_cycles + 1;
      else
        stall_cycles = stall_cycles + 1;

      timestamp_step = 1 + ($random(rng_seed) & 16'h00ff);
      occurrence_timestamp = occurrence_timestamp + timestamp_step;
      occurrence_pose_version = POSE_ID;
    end
  endtask

  task automatic run_random_cycle;
    begin
      @(negedge clk);
      randomize_inputs;
      #1;
      sample_before_edge;
      @(posedge clk);
      update_after_edge;
      cycle_count = cycle_count + 1;
      random_cycle_count = random_cycle_count + 1;
    end
  endtask

  task automatic run_drain_cycle;
    begin
      @(negedge clk);
      arrival = 0;
      polarity_in = 0;
      occurrence_pose_version = POSE_ID;
      occurrence_timestamp = occurrence_timestamp + 1;
      world_ready = 1'b1;
      #1;
      sample_before_edge;
      @(posedge clk);
      update_after_edge;
      cycle_count = cycle_count + 1;
      drain_cycles = drain_cycles + 1;
    end
  endtask

  initial begin
    rst = 1'b1;
    arrival = 0;
    polarity_in = 0;
    occurrence_pose_version = POSE_ID;
    occurrence_timestamp = 32'h1020_3040;
    pose_wr_req = 0;
    pose_wr_id = POSE_ID;
    pose_wr_m00 = Q;
    pose_wr_m01 = 0;
    pose_wr_m10 = 0;
    pose_wr_m11 = Q;
    pose_wr_tx = 0;
    pose_wr_ty = 0;
    base_sensor_origin_x = BASE_X;
    base_sensor_origin_y = BASE_Y;
    world_ready = 0;

    record_count = 0;
    output_record = -1;
    next_output_record = -1;
    pending_count = 0;
    guard_count = 0;
    guard_next = 0;
    cycle_count = 0;
    random_cycle_count = 0;
    generated_count = 0;
    aer_accepted_count = 0;
    aer_drop_count = 0;
    fifo_drop_count = 0;
    fifo_enqueue_count = 0;
    rr_count = 0;
    delivered_count = 0;
    expanded_count = 0;
    error_count = 0;
    stall_checks = 0;
    stall_cycles = 0;
    ready_cycles = 0;
    sparse_cycles = 0;
    burst_cycles = 0;
    polarity0_count = 0;
    polarity1_count = 0;
    rng_seed = 32'h5a17c0de;
    drain_cycles = 0;
    held_valid = 0;
    for (i = 0; i < 64; i = i + 1) begin
      source_head[i] = 0;
      source_tail[i] = 0;
    end
    for (i = 0; i < 4; i = i + 1) begin
      tile_head[i] = 0;
      tile_tail[i] = 0;
    end

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    pose_wr_req = 1'b1;
    #1;
    if (pose_wr_ready !== 1'b1 || pose_wr_commit !== 1'b1 ||
        pose_wr_rejected !== 1'b0)
      fail("identity pose preload did not commit");
    @(posedge clk);
    #1;
    if (!dut.u_pose_history.valid_mem[POSE_ID])
      fail("identity pose was not present after preload");
    pose_wr_req = 1'b0;

    for (random_iter = 0; random_iter < RANDOM_CYCLES;
         random_iter = random_iter + 1)
      run_random_cycle;

    while ((pending_count != 0 || output_record >= 0 ||
            dut.expanded_valid != 0 || dut.fifo_valid != 0) &&
           drain_cycles < 2000)
      run_drain_cycle;
    repeat (4)
      run_drain_cycle;

    if (pending_count != 0 || output_record >= 0)
      fail("pending scoreboard was not empty after drain");
    for (i = 0; i < 64; i = i + 1)
      if (source_head[i] != source_tail[i])
        fail("one source queue was not empty after drain");
    for (i = 0; i < 4; i = i + 1)
      if (tile_head[i] != tile_tail[i])
        fail("one tile FIFO queue was not empty after drain");
    for (i = 0; i < record_count; i = i + 1)
      if (rec_state[i] != 4 && rec_state[i] != 5)
        fail("accepted record did not reach exactly one terminal state");

    if (guard_count != 0 ||
        dut.u_pose_guard.outstanding[POSE_ID] !== 0)
      fail("pose guard leaked an outstanding reference after drain");
    if (pose_accounting_error)
      fail("pose accounting error remained set after drain");
    if (generated_count != aer_drop_count + fifo_drop_count +
                           delivered_count)
      fail("final generated-event conservation identity failed");
    if (generated_count != aer_accepted_count + aer_drop_count)
      fail("generated != AER accepted + AER drop");
    if (aer_accepted_count != fifo_drop_count + rr_count)
      fail("AER accepted != FIFO drop + RR retire");
    if (rr_count != delivered_count)
      fail("RR retired != delivered after complete drain");
    if (fifo_enqueue_count != rr_count)
      fail("FIFO enqueued != RR retired after complete drain");
    if (random_cycle_count < RANDOM_CYCLES || generated_count == 0 ||
        aer_drop_count == 0 || fifo_drop_count == 0 ||
        delivered_count == 0 || sparse_cycles == 0 || burst_cycles == 0 ||
        stall_cycles == 0 || ready_cycles == 0 || stall_checks == 0 ||
        polarity0_count == 0 || polarity1_count == 0)
      fail("random stress coverage target was not met");

    // A same-ID rewrite after the drain proves that the guard is truly free.
    @(negedge clk);
    arrival = 0;
    world_ready = 1;
    pose_wr_req = 1;
    #1;
    if (pose_wr_ready !== 1'b1 || pose_wr_commit !== 1'b1 ||
        pose_wr_rejected !== 1'b0)
      fail("pose guard remained busy after complete drain");
    @(posedge clk);
    #1;
    if (pose_accounting_error)
      fail("final pose rewrite caused an accounting error");
    pose_wr_req = 0;

    $display("TX64_SERIAL_RANDOM_COUNTS cycles=%0d generated=%0d accepted=%0d aer_drop=%0d fifo_drop=%0d delivered=%0d pending=%0d",
             random_cycle_count, generated_count, aer_accepted_count,
             aer_drop_count, fifo_drop_count, delivered_count, pending_count);
    $display("TX64_SERIAL_RANDOM_COVERAGE sparse=%0d burst=%0d ready=%0d stall=%0d stall_checks=%0d expanded=%0d drain=%0d",
             sparse_cycles, burst_cycles, ready_cycles, stall_cycles,
             stall_checks, expanded_count, drain_cycles);
    if (error_count == 0) begin
      $display("AER_TX64_POSE_AFFINE2D_SERIAL_RANDOM_PASS");
      $finish;
    end else begin
      $fatal(1, "AER_TX64_POSE_AFFINE2D_SERIAL_RANDOM_FAIL errors=%0d",
             error_count);
    end
  end
endmodule
