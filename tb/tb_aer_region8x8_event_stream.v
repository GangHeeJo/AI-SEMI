`timescale 1ns/1ps

module tb_aer_region8x8_event_stream;
  localparam integer POSE_W = 1;
  localparam integer SENSOR_W = 6;
  localparam integer TIMESTAMP_W = 20;
  localparam integer FIFO_DEPTH = 4;
  localparam integer OCC_W = $clog2(FIFO_DEPTH + 1);
  localparam integer RANDOM_CYCLES = 3000;
  localparam integer MAX_RECORDS = 110000;
  localparam integer MAX_PER_SOURCE = 4096;
  localparam integer MAX_PER_TILE = 4096;
  localparam integer BASE_X = 9;
  localparam integer BASE_Y = 17;
  localparam integer ORDER_SOURCE = 42;

  reg clk = 1'b0;
  reg rst;
  reg [63:0] arrival;
  reg [63:0] polarity_in;
  reg [POSE_W-1:0] occurrence_pose_version;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp;
  reg [SENSOR_W-1:0] base_sensor_origin_x;
  reg [SENSOR_W-1:0] base_sensor_origin_y;
  wire [63:0] aer_overrun;
  wire [31:0] tile_fifo_overflow;
  wire [6:0] admitted_count;
  wire [5:0] drop_count0;
  wire [5:0] drop_count1;
  wire event_valid;
  reg event_ready;
  wire [SENSOR_W-1:0] sensor_x;
  wire [SENSOR_W-1:0] sensor_y;
  wire polarity;
  wire [POSE_W-1:0] pose_version;
  wire [TIMESTAMP_W-1:0] occurrence_timestamp_out;

  aer_region8x8_event_stream #(
    .POSE_W(POSE_W), .SENSOR_W(SENSOR_W),
    .TIMESTAMP_W(TIMESTAMP_W), .FIFO_DEPTH(FIFO_DEPTH)
  ) dut (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in),
    .occurrence_pose_version(occurrence_pose_version),
    .occurrence_timestamp(occurrence_timestamp),
    .base_sensor_origin_x(base_sensor_origin_x),
    .base_sensor_origin_y(base_sensor_origin_y),
    .aer_overrun(aer_overrun),
    .tile_fifo_overflow(tile_fifo_overflow),
    .admitted_count(admitted_count),
    .drop_count0(drop_count0), .drop_count1(drop_count1),
    .event_valid(event_valid), .event_ready(event_ready),
    .sensor_x(sensor_x), .sensor_y(sensor_y), .polarity(polarity),
    .pose_version(pose_version),
    .occurrence_timestamp_out(occurrence_timestamp_out)
  );

  always #5 clk = ~clk;

  // Record states: 1=AER resident, 2=tile FIFO resident,
  // 3=FIFO overflow drop, 4=streamed.
  integer rec_state [0:MAX_RECORDS-1];
  integer rec_source [0:MAX_RECORDS-1];
  integer rec_tile [0:MAX_RECORDS-1];
  integer rec_sx [0:MAX_RECORDS-1];
  integer rec_sy [0:MAX_RECORDS-1];
  integer rec_pol [0:MAX_RECORDS-1];
  integer rec_pose [0:MAX_RECORDS-1];
  reg [TIMESTAMP_W-1:0] rec_time [0:MAX_RECORDS-1];

  integer source_queue [0:(64*MAX_PER_SOURCE)-1];
  integer source_head [0:63];
  integer source_tail [0:63];
  integer tile_queue [0:(4*MAX_PER_TILE)-1];
  integer tile_head [0:3];
  integer tile_tail [0:3];

  integer record_count;
  integer generated_count;
  integer aer_accepted_count;
  integer aer_drop_count;
  integer fifo_drop_count;
  integer fifo_drop_pose0;
  integer fifo_drop_pose1;
  integer streamed_count;
  integer pending_count;
  integer expanded_count;
  integer error_count;
  integer cycle_count;
  integer random_cycle_count;
  integer stall_checks;
  integer stall_cycles;
  integer ready_cycles;
  integer sparse_cycles;
  integer burst_cycles;
  integer fairness_active;
  integer fairness_seen;
  integer order_active;
  integer order_seen;
  integer tile_stream_count [0:3];
  integer rng_seed;
  integer drain_cycles;

  integer i;
  integer lane;
  integer source;
  integer tile;
  integer idx;
  integer draw;
  integer random_iter;
  integer source_pick;
  integer pick_i;
  integer sparse_events;
  integer timestamp_step;

  reg held_valid;
  reg [SENSOR_W-1:0] held_sx;
  reg [SENSOR_W-1:0] held_sy;
  reg held_polarity;
  reg [POSE_W-1:0] held_pose;
  reg [TIMESTAMP_W-1:0] held_time;

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
        $display("FAIL cycle=%0d random=%0d: %0s",
                 cycle_count, random_cycle_count, message);
    end
  endtask

  task automatic check_stalled_output;
    begin
      if (held_valid) begin
        stall_checks = stall_checks + 1;
        if (event_valid !== 1'b1 || sensor_x !== held_sx ||
            sensor_y !== held_sy || polarity !== held_polarity ||
            pose_version !== held_pose ||
            occurrence_timestamp_out !== held_time)
          fail("event output changed while stalled");
      end
    end
  endtask

  task automatic process_stream;
    integer stream_tile;
    integer stream_idx;
    begin
      if (event_valid) begin
        stream_tile = dut.rr_source;
        if (tile_head[stream_tile] >= tile_tail[stream_tile]) begin
          fail("phantom stream event or duplicate dequeue");
        end else begin
          stream_idx = tile_queue[stream_tile*MAX_PER_TILE +
                                  tile_head[stream_tile]];
          if (rec_state[stream_idx] != 2)
            fail("stream head is not resident in its tile FIFO");
          if (sensor_x !== rec_sx[stream_idx] ||
              sensor_y !== rec_sy[stream_idx] ||
              polarity !== rec_pol[stream_idx][0] ||
              pose_version !== rec_pose[stream_idx] ||
              occurrence_timestamp_out !== rec_time[stream_idx])
            fail("stream metadata or per-tile source order mismatch");

          if (event_ready) begin
            if (fairness_active != 0) begin
              if (stream_tile != fairness_seen)
                fail("four-way round-robin order was not 0,1,2,3");
              fairness_seen = fairness_seen + 1;
            end
            if (order_active != 0 &&
                rec_source[stream_idx] == ORDER_SOURCE) begin
              if ((order_seen == 0 && rec_time[stream_idx] != 20'd100) ||
                  (order_seen == 1 && rec_time[stream_idx] != 20'd101))
                fail("same-source FIFO order changed");
              order_seen = order_seen + 1;
            end
            tile_head[stream_tile] = tile_head[stream_tile] + 1;
            rec_state[stream_idx] = 4;
            tile_stream_count[stream_tile] =
              tile_stream_count[stream_tile] + 1;
            streamed_count = streamed_count + 1;
            pending_count = pending_count - 1;
          end
        end
      end else if (dut.fifo_valid != 0) begin
        fail("arbiter suppressed all valid FIFO inputs");
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
    integer occupancy_before;
    integer expected_overflow;
    integer actual_overflow;
    integer cycle_drop0;
    integer cycle_drop1;
    begin
      cycle_drop0 = 0;
      cycle_drop1 = 0;
      if ((tile_fifo_overflow & ~dut.expanded_valid) != 0)
        fail("FIFO overflow asserted on an inactive expansion lane");

      for (lane = 0; lane < 32; lane = lane + 1) begin
        if (dut.expanded_valid[lane]) begin
          expanded_count = expanded_count + 1;
          expanded_tile = lane / 8;
          expanded_sx = dut.expanded_x_flat[
            lane*SENSOR_W +: SENSOR_W];
          expanded_sy = dut.expanded_y_flat[
            lane*SENSOR_W +: SENSOR_W];
          expanded_pol = dut.expanded_polarity[lane];
          expanded_pose = dut.expanded_pose_flat[
            lane*POSE_W +: POSE_W];
          expanded_time = dut.expanded_time_flat[
            lane*TIMESTAMP_W +: TIMESTAMP_W];
          expanded_source = source_from_coordinate(
            expanded_tile, expanded_sx, expanded_sy);

          if (expanded_source < 0) begin
            fail("expanded event has an invalid leaf/global coordinate");
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
              fail("expanded record was not AER resident");
            if (rec_source[expanded_idx] != expanded_source ||
                rec_tile[expanded_idx] != expanded_tile ||
                rec_sx[expanded_idx] != expanded_sx ||
                rec_sy[expanded_idx] != expanded_sy ||
                rec_pol[expanded_idx] != expanded_pol ||
                rec_pose[expanded_idx] != expanded_pose ||
                rec_time[expanded_idx] !== expanded_time)
              fail("AER expansion metadata or source FIFO order mismatch");

            occupancy_before = tile_tail[expanded_tile] -
                               tile_head[expanded_tile];
            expected_overflow = (occupancy_before >= FIFO_DEPTH);
            actual_overflow = tile_fifo_overflow[lane];
            if (actual_overflow != expected_overflow)
              fail("tile FIFO overflow disagrees with available slots");

            if (actual_overflow) begin
              rec_state[expanded_idx] = 3;
              fifo_drop_count = fifo_drop_count + 1;
              pending_count = pending_count - 1;
              if (expanded_pose == 0) begin
                fifo_drop_pose0 = fifo_drop_pose0 + 1;
                cycle_drop0 = cycle_drop0 + 1;
              end else begin
                fifo_drop_pose1 = fifo_drop_pose1 + 1;
                cycle_drop1 = cycle_drop1 + 1;
              end
            end else begin
              if (tile_tail[expanded_tile] >= MAX_PER_TILE)
                $fatal(1, "tile queue capacity exceeded");
              rec_state[expanded_idx] = 2;
              tile_queue[expanded_tile*MAX_PER_TILE +
                         tile_tail[expanded_tile]] = expanded_idx;
              tile_tail[expanded_tile] = tile_tail[expanded_tile] + 1;
            end
          end
        end
      end

      if (drop_count0 !== cycle_drop0[5:0] ||
          drop_count1 !== cycle_drop1[5:0])
        fail("pose-split FIFO drop counts are incorrect");
    end
  endtask

  task automatic process_arrivals;
    integer source_depth;
    integer expected_overrun;
    integer expected_sx;
    integer expected_sy;
    integer new_idx;
    integer cycle_admitted;
    begin
      cycle_admitted = 0;
      if ((aer_overrun & ~arrival) != 0)
        fail("AER overrun asserted without an arrival");

      for (source = 0; source < 64; source = source + 1) begin
        source_depth = source_tail[source] - source_head[source];
        if (source_depth < 0 || source_depth > 2)
          fail("software AER source depth is outside 0..2");
        expected_overrun = arrival[source] && (source_depth == 2);
        if (aer_overrun[source] !== expected_overrun[0])
          fail("AER overrun disagrees with pre-edge depth-2 state");

        if (arrival[source]) begin
          generated_count = generated_count + 1;
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
            cycle_admitted = cycle_admitted + 1;
          end
        end
      end

      if (admitted_count !== cycle_admitted[6:0])
        fail("admitted_count is not popcount(arrival & ~aer_overrun)");
    end
  endtask

  task automatic check_conservation;
    integer resident_count;
    integer scan;
    begin
      resident_count = 0;
      for (scan = 0; scan < 64; scan = scan + 1)
        resident_count = resident_count +
                         source_tail[scan] - source_head[scan];
      for (scan = 0; scan < 4; scan = scan + 1)
        resident_count = resident_count +
                         tile_tail[scan] - tile_head[scan];
      if (pending_count != resident_count)
        fail("pending count differs from AER plus tile-FIFO residents");
      if (aer_accepted_count != fifo_drop_count +
                                streamed_count + resident_count)
        fail("accepted != FIFO drop + streamed + resident");
      if (generated_count != aer_drop_count + aer_accepted_count)
        fail("generated != AER drop + admitted");
      if (pending_count < 0)
        fail("pending event count became negative");
    end
  endtask

  task automatic sample_before_edge;
    begin
      check_stalled_output;
      process_stream;
      process_expanded_batches;
      process_arrivals;
      check_conservation;

      held_valid = event_valid && !event_ready;
      held_sx = sensor_x;
      held_sy = sensor_y;
      held_polarity = polarity;
      held_pose = pose_version;
      held_time = occurrence_timestamp_out;
    end
  endtask

  task automatic update_after_edge;
    integer scan;
    integer model_occupancy;
    begin
      #1;
      for (scan = 0; scan < 4; scan = scan + 1) begin
        model_occupancy = tile_tail[scan] - tile_head[scan];
        if (dut.fifo_occupancy_flat[scan*OCC_W +: OCC_W]
            !== model_occupancy[OCC_W-1:0])
          fail("hardware tile FIFO occupancy differs from oracle");
      end
    end
  endtask

  task automatic drive_cycle;
    input [63:0] next_arrival;
    input [63:0] next_polarity;
    input [POSE_W-1:0] next_pose;
    input [TIMESTAMP_W-1:0] next_time;
    input next_ready;
    begin
      @(negedge clk);
      arrival = next_arrival;
      polarity_in = next_polarity;
      occurrence_pose_version = next_pose;
      occurrence_timestamp = next_time;
      event_ready = next_ready;
      #1;
      sample_before_edge;
      @(posedge clk);
      update_after_edge;
      cycle_count = cycle_count + 1;
    end
  endtask

  task automatic drive_random_cycle;
    reg [63:0] random_a;
    reg [63:0] random_b;
    reg [63:0] next_arrival;
    reg [63:0] next_polarity;
    reg next_ready;
    reg next_pose;
    begin
      random_a = {$random(rng_seed), $random(rng_seed)};
      random_b = {$random(rng_seed), $random(rng_seed)};
      next_polarity = {$random(rng_seed), $random(rng_seed)};
      next_arrival = 64'd0;
      draw = (($random(rng_seed) % 100) + 100) % 100;
      if (draw < 72) begin
        sparse_cycles = sparse_cycles + 1;
        sparse_events = (($random(rng_seed) % 5) + 5) % 5;
        for (pick_i = 0; pick_i < sparse_events; pick_i = pick_i + 1) begin
          source_pick = (($random(rng_seed) % 64) + 64) % 64;
          next_arrival[source_pick] = 1'b1;
        end
      end else if (draw < 95) begin
        next_arrival = random_a & random_b;
      end else begin
        burst_cycles = burst_cycles + 1;
        case (draw & 3)
          0: next_arrival = 64'hffff_ffff_ffff_ffff;
          1: next_arrival = random_a | random_b;
          2: next_arrival = 64'haaaa_aaaa_aaaa_aaaa;
          default: next_arrival = 64'h5555_5555_5555_5555;
        endcase
      end
      draw = (($random(rng_seed) % 100) + 100) % 100;
      next_ready = (draw < 58);
      if (next_ready)
        ready_cycles = ready_cycles + 1;
      else
        stall_cycles = stall_cycles + 1;
      next_pose = $random(rng_seed);
      timestamp_step = 1 + ($random(rng_seed) & 16'h00ff);
      occurrence_timestamp = occurrence_timestamp + timestamp_step;
      drive_cycle(next_arrival, next_polarity, next_pose,
                  occurrence_timestamp, next_ready);
      random_cycle_count = random_cycle_count + 1;
    end
  endtask

  initial begin
    rst = 1'b1;
    arrival = 0;
    polarity_in = 0;
    occurrence_pose_version = 0;
    occurrence_timestamp = 0;
    base_sensor_origin_x = BASE_X;
    base_sensor_origin_y = BASE_Y;
    event_ready = 0;
    record_count = 0;
    generated_count = 0;
    aer_accepted_count = 0;
    aer_drop_count = 0;
    fifo_drop_count = 0;
    fifo_drop_pose0 = 0;
    fifo_drop_pose1 = 0;
    streamed_count = 0;
    pending_count = 0;
    expanded_count = 0;
    error_count = 0;
    cycle_count = 0;
    random_cycle_count = 0;
    stall_checks = 0;
    stall_cycles = 0;
    ready_cycles = 0;
    sparse_cycles = 0;
    burst_cycles = 0;
    fairness_active = 0;
    fairness_seen = 0;
    order_active = 0;
    order_seen = 0;
    rng_seed = 32'h6712a55a;
    drain_cycles = 0;
    held_valid = 0;
    for (i = 0; i < 64; i = i + 1) begin
      source_head[i] = 0;
      source_tail[i] = 0;
    end
    for (i = 0; i < 4; i = i + 1) begin
      tile_head[i] = 0;
      tile_tail[i] = 0;
      tile_stream_count[i] = 0;
    end

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    // One different local coordinate in each leaf.  Equal arrival time proves
    // the initial fair order and all four global-origin offsets.
    fairness_active = 1;
    drive_cycle((64'h1 << 0) | (64'h1 << 23) |
                (64'h1 << 41) | (64'h1 << 62),
                (64'h1 << 23) | (64'h1 << 62), 1'b1, 20'd10, 1'b1);
    while (fairness_seen < 4 && cycle_count < 40)
      drive_cycle(0, 0, 0, occurrence_timestamp + 1'b1, 1'b1);
    fairness_active = 0;
    if (fairness_seen != 4)
      fail("four-leaf fairness/coordinate phase did not drain");

    // Consecutive arrivals at one source carry distinct epoch/time metadata.
    order_active = 1;
    drive_cycle(64'h1 << ORDER_SOURCE, 64'h0, 1'b0, 20'd100, 1'b0);
    drive_cycle(64'h1 << ORDER_SOURCE, 64'h1 << ORDER_SOURCE,
                1'b1, 20'd101, 1'b0);
    repeat (4)
      drive_cycle(0, 0, 0, occurrence_timestamp + 1'b1, 1'b0);
    while (order_seen < 2 && cycle_count < 80)
      drive_cycle(0, 0, 0, occurrence_timestamp + 1'b1, 1'b1);
    order_active = 0;
    if (order_seen != 2)
      fail("same-source ordering phase did not stream both events");

    // Small tile FIFOs plus a stopped consumer force both loss boundaries.
    for (i = 0; i < 12; i = i + 1)
      drive_cycle(64'hffff_ffff_ffff_ffff,
                  (i & 1) ? 64'haaaa_aaaa_aaaa_aaaa
                          : 64'h5555_5555_5555_5555,
                  i[0], 20'd200 + i, 1'b0);
    repeat (8)
      drive_cycle(0, 0, 0, occurrence_timestamp + 1'b1, 1'b0);
    while (pending_count != 0 && cycle_count < 300)
      drive_cycle(0, 0, 0, occurrence_timestamp + 1'b1, 1'b1);
    if (aer_drop_count == 0)
      fail("directed pressure did not force an AER overrun");
    if (fifo_drop_count == 0 ||
        fifo_drop_pose0 == 0 || fifo_drop_pose1 == 0)
      fail("directed pressure did not force both pose FIFO drops");

    for (random_iter = 0; random_iter < RANDOM_CYCLES;
         random_iter = random_iter + 1)
      drive_random_cycle;

    while ((pending_count != 0 || dut.expanded_valid != 0 ||
            dut.fifo_valid != 0 || event_valid) && drain_cycles < 5000) begin
      drive_cycle(0, 0, 0, occurrence_timestamp + 1'b1, 1'b1);
      drain_cycles = drain_cycles + 1;
    end
    repeat (4)
      drive_cycle(0, 0, 0, occurrence_timestamp + 1'b1, 1'b1);

    if (pending_count != 0)
      fail("accepted residents did not completely drain");
    for (i = 0; i < 64; i = i + 1)
      if (source_head[i] != source_tail[i])
        fail("one source FIFO oracle did not drain");
    for (i = 0; i < 4; i = i + 1) begin
      if (tile_head[i] != tile_tail[i])
        fail("one tile FIFO oracle did not drain");
      if (tile_stream_count[i] == 0)
        fail("one tile never won the fair arbiter");
    end
    for (i = 0; i < record_count; i = i + 1)
      if (rec_state[i] != 3 && rec_state[i] != 4)
        fail("one admitted event lacked exactly one terminal outcome");
    if (aer_accepted_count != fifo_drop_count + streamed_count)
      fail("final admitted-event conservation identity failed");
    if (random_cycle_count != RANDOM_CYCLES || sparse_cycles == 0 ||
        burst_cycles == 0 || stall_cycles == 0 || ready_cycles == 0 ||
        stall_checks == 0 || expanded_count == 0)
      fail("random stress coverage target was not met");

    $display("REGION8X8_COUNTS cycles=%0d generated=%0d admitted=%0d aer_drop=%0d fifo_drop=%0d streamed=%0d",
             random_cycle_count, generated_count, aer_accepted_count,
             aer_drop_count, fifo_drop_count, streamed_count);
    $display("REGION8X8_COVERAGE fairness=%0d order=%0d stall_checks=%0d expanded=%0d drop0=%0d drop1=%0d drain=%0d",
             fairness_seen, order_seen, stall_checks, expanded_count,
             fifo_drop_pose0, fifo_drop_pose1, drain_cycles);
    if (error_count == 0) begin
      $display("AER_REGION8X8_EVENT_STREAM_PASS");
      $finish;
    end else begin
      $fatal(1, "AER_REGION8X8_EVENT_STREAM_FAIL errors=%0d", error_count);
    end
  end
endmodule
