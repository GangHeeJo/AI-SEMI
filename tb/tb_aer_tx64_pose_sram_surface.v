`timescale 1ns/1ps

module tb_aer_tx64_pose_sram_surface;
  localparam integer POSE_W = 3;
  localparam integer SENSOR_W = 6;
  localparam integer RESULT_W = 16;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer FRAC_W = 14;
  localparam integer TIMESTAMP_W = 16;
  localparam integer FIFO_DEPTH = 16;
  localparam integer GUARD_COUNT_W = 10;
  localparam integer GRID_W = 7;
  localparam integer GRID_H = 6;
  localparam integer CELLS = GRID_W * GRID_H;
  localparam integer ADDR_W = $clog2(CELLS);
  localparam integer Q = (1 << FRAC_W);

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
  wire world_ready;
  wire mapped_valid;
  wire pose_found;
  wire in_range;
  wire [SENSOR_W-1:0] sensor_x;
  wire [SENSOR_W-1:0] sensor_y;
  wire [1:0] tile_id;
  wire polarity_out;
  wire [POSE_W-1:0] pose_version_out;
  wire [TIMESTAMP_W-1:0] occurrence_timestamp_out;
  wire signed [RESULT_W-1:0] world_x;
  wire signed [RESULT_W-1:0] world_y;

  wire surface_update_applied;
  wire surface_equal_time_merged;
  wire surface_stale_ignored;
  wire surface_range_error;
  wire mem_rd_req_valid;
  reg mem_rd_req_ready;
  wire [ADDR_W-1:0] mem_rd_req_addr;
  reg mem_rd_rsp_valid;
  wire mem_rd_rsp_ready;
  reg mem_rd_rsp_cell_valid;
  reg [TIMESTAMP_W-1:0] mem_rd_rsp_timestamp;
  reg [1:0] mem_rd_rsp_polarity_seen;
  wire mem_wr_req_valid;
  reg mem_wr_req_ready;
  wire [ADDR_W-1:0] mem_wr_req_addr;
  wire mem_wr_req_cell_valid;
  wire [TIMESTAMP_W-1:0] mem_wr_req_timestamp;
  wire [1:0] mem_wr_req_polarity_seen;

  aer_tx64_pose_sram_surface #(
    .POSE_W(POSE_W), .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .TIMESTAMP_W(TIMESTAMP_W), .FIFO_DEPTH(FIFO_DEPTH),
    .GUARD_COUNT_W(GUARD_COUNT_W),
    .GRID_W(GRID_W), .GRID_H(GRID_H), .ADDR_W(ADDR_W)
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
    .tile_id(tile_id), .polarity_out(polarity_out),
    .pose_version_out(pose_version_out),
    .occurrence_timestamp_out(occurrence_timestamp_out),
    .world_x(world_x), .world_y(world_y),
    .surface_update_applied(surface_update_applied),
    .surface_equal_time_merged(surface_equal_time_merged),
    .surface_stale_ignored(surface_stale_ignored),
    .surface_range_error(surface_range_error),
    .mem_rd_req_valid(mem_rd_req_valid),
    .mem_rd_req_ready(mem_rd_req_ready),
    .mem_rd_req_addr(mem_rd_req_addr),
    .mem_rd_rsp_valid(mem_rd_rsp_valid),
    .mem_rd_rsp_ready(mem_rd_rsp_ready),
    .mem_rd_rsp_cell_valid(mem_rd_rsp_cell_valid),
    .mem_rd_rsp_timestamp(mem_rd_rsp_timestamp),
    .mem_rd_rsp_polarity_seen(mem_rd_rsp_polarity_seen),
    .mem_wr_req_valid(mem_wr_req_valid),
    .mem_wr_req_ready(mem_wr_req_ready),
    .mem_wr_req_addr(mem_wr_req_addr),
    .mem_wr_req_cell_valid(mem_wr_req_cell_valid),
    .mem_wr_req_timestamp(mem_wr_req_timestamp),
    .mem_wr_req_polarity_seen(mem_wr_req_polarity_seen)
  );

  always #5 clk = ~clk;

  reg memory_valid [0:CELLS-1];
  reg [TIMESTAMP_W-1:0] memory_timestamp [0:CELLS-1];
  reg [1:0] memory_polarity [0:CELLS-1];
  reg response_pending;
  integer response_delay;
  reg response_pending_valid;
  reg [TIMESTAMP_W-1:0] response_pending_timestamp;
  reg [1:0] response_pending_polarity;

  integer guard_model [0:(1<<POSE_W)-1];
  integer guard_next [0:(1<<POSE_W)-1];
  integer system_pending;
  integer cycle_count;
  integer generated_count;
  integer aer_accepted_count;
  integer aer_drop_count;
  integer fifo_drop_count;
  integer rr_count;
  integer world_consumed_count;
  integer mapped_world_count;
  integer invalid_world_count;
  integer completed_count;
  integer update_count;
  integer equal_count;
  integer stale_count;
  integer read_count;
  integer write_count;
  integer world_stall_count;
  integer read_stall_count;
  integer write_stall_count;
  integer error_count;
  integer rng_seed;
  integer memory_seed;
  integer i;
  integer lane;
  integer source;
  integer pose_scan;
  integer drain_count;
  integer burst_cycle;
  integer source_index;
  integer baseline_updates;
  integer baseline_equal;
  integer baseline_stale;
  integer baseline_reads;
  integer baseline_writes;
  integer baseline_seen;
  integer address;

  integer directed_mode;
  integer directed_active;
  integer directed_seen;
  integer expected_sx;
  integer expected_sy;
  integer expected_tile;
  integer expected_polarity;
  integer expected_pose;
  integer expected_time;
  integer expected_found;
  integer expected_range;
  integer expected_mapped;
  integer expected_wx;
  integer expected_wy;

  reg held_world;
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
  reg held_read;
  reg [ADDR_W-1:0] held_read_addr;
  reg held_write;
  reg [ADDR_W-1:0] held_write_addr;
  reg held_write_valid;
  reg [TIMESTAMP_W-1:0] held_write_time;
  reg [1:0] held_write_polarity;

  function integer sensor_source;
    input integer x;
    input integer y;
    integer tile_local;
    begin
      tile_local = (y/4)*2 + (x/4);
      sensor_source = tile_local*16 + (y%4)*4 + (x%4);
    end
  endfunction

  function integer guard_total;
    integer p;
    begin
      guard_total = 0;
      for (p = 0; p < (1 << POSE_W); p = p + 1)
        guard_total = guard_total + guard_model[p];
    end
  endfunction

  task automatic fail;
    input [1023:0] message;
    begin
      error_count = error_count + 1;
      if (error_count <= 30)
        $display("FAIL cycle=%0d: %0s", cycle_count, message);
    end
  endtask

  // Random-latency external memory. The wrapper guarantees one outstanding
  // read, so the response queue only needs one entry.
  always @(posedge clk) begin
    if (rst) begin
      mem_rd_rsp_valid <= 1'b0;
      mem_rd_rsp_cell_valid <= 1'b0;
      mem_rd_rsp_timestamp <= 0;
      mem_rd_rsp_polarity_seen <= 0;
      response_pending <= 1'b0;
      response_delay <= 0;
    end else begin
      if (mem_rd_rsp_valid && mem_rd_rsp_ready)
        mem_rd_rsp_valid <= 1'b0;

      if (mem_rd_req_valid && mem_rd_req_ready) begin
        if (response_pending || mem_rd_rsp_valid)
          $fatal(1, "more than one external read became outstanding");
        if (mem_rd_req_addr >= CELLS)
          $fatal(1, "external read address outside non-power-of-two grid");
        response_pending <= 1'b1;
        response_delay <= (($random(memory_seed) % 7) + 7) % 7;
        response_pending_valid <= memory_valid[mem_rd_req_addr];
        response_pending_timestamp <= memory_timestamp[mem_rd_req_addr];
        response_pending_polarity <= memory_polarity[mem_rd_req_addr];
      end

      if (response_pending && !mem_rd_rsp_valid) begin
        if (response_delay == 0) begin
          mem_rd_rsp_valid <= 1'b1;
          mem_rd_rsp_cell_valid <= response_pending_valid;
          mem_rd_rsp_timestamp <= response_pending_timestamp;
          mem_rd_rsp_polarity_seen <= response_pending_polarity;
          response_pending <= 1'b0;
        end else begin
          response_delay <= response_delay - 1;
        end
      end

      if (mem_wr_req_valid && mem_wr_req_ready) begin
        if (mem_wr_req_addr >= CELLS)
          $fatal(1, "external write address outside non-power-of-two grid");
        memory_valid[mem_wr_req_addr] <= mem_wr_req_cell_valid;
        memory_timestamp[mem_wr_req_addr] <= mem_wr_req_timestamp;
        memory_polarity[mem_wr_req_addr] <= mem_wr_req_polarity_seen;
      end
    end
  end

  task automatic check_stability;
    begin
      if (held_world &&
          (!world_valid || mapped_valid !== held_mapped ||
           pose_found !== held_found || in_range !== held_range ||
           sensor_x !== held_sx || sensor_y !== held_sy ||
           tile_id !== held_tile || polarity_out !== held_polarity ||
           pose_version_out !== held_pose ||
           occurrence_timestamp_out !== held_time ||
           world_x !== held_wx || world_y !== held_wy))
        fail("affine world output changed while surface writer stalled");
      if (held_read &&
          (!mem_rd_req_valid || mem_rd_req_addr !== held_read_addr))
        fail("surface read request changed while external memory stalled");
      if (held_write &&
          (!mem_wr_req_valid || mem_wr_req_addr !== held_write_addr ||
           mem_wr_req_cell_valid !== held_write_valid ||
           mem_wr_req_timestamp !== held_write_time ||
           mem_wr_req_polarity_seen !== held_write_polarity))
        fail("surface write request changed while external memory stalled");
    end
  endtask

  task automatic check_directed_world;
    begin
      if (directed_mode && world_valid) begin
        if (!directed_active) begin
          fail("duplicate or phantom directed world event");
        end else begin
          if (sensor_x !== expected_sx || sensor_y !== expected_sy ||
              tile_id !== expected_tile ||
              polarity_out !== expected_polarity[0] ||
              pose_version_out !== expected_pose ||
              occurrence_timestamp_out !== expected_time ||
              pose_found !== expected_found[0] ||
              in_range !== expected_range[0] ||
              mapped_valid !== expected_mapped[0] ||
              $signed(world_x) != expected_wx ||
              $signed(world_y) != expected_wy)
            fail("directed world metadata or transform mismatch");
          if (world_ready) begin
            directed_active = 0;
            directed_seen = directed_seen + 1;
          end
        end
      end
    end
  endtask

  task automatic sample_before_edge;
    integer status_total;
    begin
      check_stability;
      check_directed_world;

      for (pose_scan = 0; pose_scan < (1 << POSE_W);
           pose_scan = pose_scan + 1)
        guard_next[pose_scan] = guard_model[pose_scan];

      status_total = surface_update_applied + surface_stale_ignored +
                     surface_range_error;
      if (status_total > 1)
        fail("mutually exclusive surface completion statuses overlapped");
      if (surface_equal_time_merged && !surface_update_applied)
        fail("equal-time status asserted without an applied update");
      if (surface_range_error)
        fail("wrapper leaked a mapped coordinate outside its own grid bounds");

      if (surface_update_applied) begin
        update_count = update_count + 1;
        completed_count = completed_count + 1;
        system_pending = system_pending - 1;
      end
      if (surface_equal_time_merged)
        equal_count = equal_count + 1;
      if (surface_stale_ignored) begin
        stale_count = stale_count + 1;
        completed_count = completed_count + 1;
        system_pending = system_pending - 1;
      end

      if (world_valid && world_ready) begin
        world_consumed_count = world_consumed_count + 1;
        if (mapped_valid) begin
          if (!pose_found || !in_range)
            fail("mapped world event lacks pose/range validity");
          mapped_world_count = mapped_world_count + 1;
        end else begin
          invalid_world_count = invalid_world_count + 1;
          completed_count = completed_count + 1;
          system_pending = system_pending - 1;
        end
      end
      if (world_valid && !world_ready)
        world_stall_count = world_stall_count + 1;

      if (dut.u_tx.rr_handshake) begin
        rr_count = rr_count + 1;
        if (guard_next[dut.u_tx.rr_pose] == 0)
          fail("pose guard oracle underflow at RR retirement");
        else
          guard_next[dut.u_tx.rr_pose] =
            guard_next[dut.u_tx.rr_pose] - 1;
      end

      if ((tile_fifo_overflow & ~dut.u_tx.expanded_valid) != 0)
        fail("tile FIFO overflow asserted for an inactive expanded lane");
      for (lane = 0; lane < 32; lane = lane + 1) begin
        if (tile_fifo_overflow[lane]) begin
          fifo_drop_count = fifo_drop_count + 1;
          system_pending = system_pending - 1;
          if (guard_next[dut.u_tx.expanded_pose_flat[
                         lane*POSE_W +: POSE_W]] == 0)
            fail("pose guard oracle underflow at FIFO drop");
          else
            guard_next[dut.u_tx.expanded_pose_flat[
                       lane*POSE_W +: POSE_W]] =
              guard_next[dut.u_tx.expanded_pose_flat[
                         lane*POSE_W +: POSE_W]] - 1;
        end
      end

      if ((aer_overrun & ~arrival) != 0)
        fail("AER overrun asserted without a matching arrival");
      for (source = 0; source < 64; source = source + 1) begin
        if (arrival[source]) begin
          generated_count = generated_count + 1;
          if (aer_overrun[source]) begin
            aer_drop_count = aer_drop_count + 1;
          end else begin
            aer_accepted_count = aer_accepted_count + 1;
            system_pending = system_pending + 1;
            guard_next[occurrence_pose_version] =
              guard_next[occurrence_pose_version] + 1;
          end
        end
      end

      if (generated_count != aer_drop_count + fifo_drop_count +
                             completed_count + system_pending)
        fail("end-to-end event conservation identity failed");
      if (system_pending < 0)
        fail("end-to-end pending count became negative");

      if (mem_rd_req_valid && mem_rd_req_ready)
        read_count = read_count + 1;
      if (mem_wr_req_valid && mem_wr_req_ready)
        write_count = write_count + 1;
      if (mem_rd_req_valid && !mem_rd_req_ready)
        read_stall_count = read_stall_count + 1;
      if (mem_wr_req_valid && !mem_wr_req_ready)
        write_stall_count = write_stall_count + 1;

      held_world = world_valid && !world_ready;
      held_mapped = mapped_valid;
      held_found = pose_found;
      held_range = in_range;
      held_sx = sensor_x;
      held_sy = sensor_y;
      held_tile = tile_id;
      held_polarity = polarity_out;
      held_pose = pose_version_out;
      held_time = occurrence_timestamp_out;
      held_wx = world_x;
      held_wy = world_y;
      held_read = mem_rd_req_valid && !mem_rd_req_ready;
      held_read_addr = mem_rd_req_addr;
      held_write = mem_wr_req_valid && !mem_wr_req_ready;
      held_write_addr = mem_wr_req_addr;
      held_write_valid = mem_wr_req_cell_valid;
      held_write_time = mem_wr_req_timestamp;
      held_write_polarity = mem_wr_req_polarity_seen;
    end
  endtask

  task automatic update_after_edge;
    begin
      #1;
      for (pose_scan = 0; pose_scan < (1 << POSE_W);
           pose_scan = pose_scan + 1) begin
        guard_model[pose_scan] = guard_next[pose_scan];
        if (dut.u_tx.u_pose_guard.outstanding[pose_scan]
            !== guard_model[pose_scan][GUARD_COUNT_W-1:0])
          fail("pose guard outstanding count mismatch");
      end
      if (pose_accounting_error)
        fail("pose guard accounting_error asserted");
      cycle_count = cycle_count + 1;
    end
  endtask

  task automatic tick;
    integer ready_draw;
    begin
      @(negedge clk);
      ready_draw = (($random(rng_seed) % 100) + 100) % 100;
      mem_rd_req_ready = (ready_draw < 51);
      ready_draw = (($random(rng_seed) % 100) + 100) % 100;
      mem_wr_req_ready = (ready_draw < 45);
      #1;
      sample_before_edge;
      @(posedge clk);
      update_after_edge;
    end
  endtask

  task automatic drain_all;
    begin
      arrival = 0;
      polarity_in = 0;
      drain_count = 0;
      while ((system_pending != 0 || guard_total() != 0 ||
              response_pending || mem_rd_rsp_valid ||
              dut.u_surface.state != 0) && drain_count < 10000) begin
        tick;
        drain_count = drain_count + 1;
      end
      repeat (3)
        tick;
      if (system_pending != 0 || guard_total() != 0 ||
          response_pending || mem_rd_rsp_valid || dut.u_surface.state != 0)
        fail("pipeline or surface writer did not drain");
    end
  endtask

  task automatic send_directed;
    input integer x;
    input integer y;
    input integer pose_id;
    input integer event_polarity;
    input integer event_time;
    begin
      source_index = sensor_source(x, y);
      directed_mode = 1;
      directed_active = 1;
      expected_sx = x;
      expected_sy = y;
      expected_tile = (y/4)*2 + (x/4);
      expected_polarity = event_polarity;
      expected_pose = pose_id;
      expected_time = event_time;
      expected_found = (pose_id == 0);
      expected_range = expected_found && x >= 0 && x < GRID_W &&
                       y >= 0 && y < GRID_H;
      expected_mapped = expected_range;
      expected_wx = expected_found ? x : 0;
      expected_wy = expected_found ? y : 0;
      baseline_seen = directed_seen;

      arrival = 64'd0;
      polarity_in = 64'd0;
      arrival[source_index] = 1'b1;
      polarity_in[source_index] = event_polarity[0];
      occurrence_pose_version = pose_id;
      occurrence_timestamp = event_time;
      tick;
      arrival = 0;
      polarity_in = 0;
      drain_all;
      if (directed_seen != baseline_seen + 1 || directed_active)
        fail("directed event was not consumed exactly once");
      directed_mode = 0;
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
    pose_wr_m00 = Q;
    pose_wr_m01 = 0;
    pose_wr_m10 = 0;
    pose_wr_m11 = Q;
    pose_wr_tx = 0;
    pose_wr_ty = 0;
    base_sensor_origin_x = 0;
    base_sensor_origin_y = 0;
    mem_rd_req_ready = 0;
    mem_wr_req_ready = 0;
    mem_rd_rsp_valid = 0;
    mem_rd_rsp_cell_valid = 0;
    mem_rd_rsp_timestamp = 0;
    mem_rd_rsp_polarity_seen = 0;
    response_pending = 0;
    response_delay = 0;
    response_pending_valid = 0;
    response_pending_timestamp = 0;
    response_pending_polarity = 0;
    system_pending = 0;
    cycle_count = 0;
    generated_count = 0;
    aer_accepted_count = 0;
    aer_drop_count = 0;
    fifo_drop_count = 0;
    rr_count = 0;
    world_consumed_count = 0;
    mapped_world_count = 0;
    invalid_world_count = 0;
    completed_count = 0;
    update_count = 0;
    equal_count = 0;
    stale_count = 0;
    read_count = 0;
    write_count = 0;
    world_stall_count = 0;
    read_stall_count = 0;
    write_stall_count = 0;
    error_count = 0;
    rng_seed = 32'h4a5b6c7d;
    memory_seed = 32'h10293847;
    directed_mode = 0;
    directed_active = 0;
    directed_seen = 0;
    held_world = 0;
    held_read = 0;
    held_write = 0;
    for (i = 0; i < (1 << POSE_W); i = i + 1) begin
      guard_model[i] = 0;
      guard_next[i] = 0;
    end
    for (i = 0; i < CELLS; i = i + 1) begin
      memory_valid[i] = 0;
      memory_timestamp[i] = 0;
      memory_polarity[i] = 0;
    end

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    pose_wr_req = 1'b1;
    #1;
    if (!pose_wr_ready || !pose_wr_commit || pose_wr_rejected)
      fail("identity pose preload failed");
    @(posedge clk);
    #1;
    pose_wr_req = 1'b0;
    if (!dut.u_tx.u_pose_history.valid_mem[0])
      fail("identity pose history entry is invalid after preload");

    // Identity update, then newer replacement followed by an older stale event.
    address = 2*GRID_W + 1;
    send_directed(1, 2, 0, 0, 100);
    if (!memory_valid[address] || memory_timestamp[address] != 100 ||
        memory_polarity[address] != 2'b01)
      fail("identity event did not initialize its world cell");
    send_directed(1, 2, 0, 1, 200);
    if (memory_timestamp[address] != 200 ||
        memory_polarity[address] != 2'b10)
      fail("newer event did not replace world cell metadata");
    baseline_stale = stale_count;
    send_directed(1, 2, 0, 0, 150);
    if (stale_count != baseline_stale + 1 ||
        memory_timestamp[address] != 200 ||
        memory_polarity[address] != 2'b10)
      fail("older event was not ignored without a memory change");

    // Equal-time opposite polarities must merge to both bits.
    address = 4*GRID_W + 3;
    send_directed(3, 4, 0, 0, 300);
    baseline_updates = update_count;
    baseline_equal = equal_count;
    send_directed(3, 4, 0, 1, 300);
    if (update_count != baseline_updates + 1 ||
        equal_count != baseline_equal + 1 ||
        memory_timestamp[address] != 300 ||
        memory_polarity[address] != 2'b11)
      fail("equal-time polarity merge failed");

    // A missing pose and identity coordinates beyond 7x6 are preserved on the
    // world stream but mapped-invalid, so neither may access external memory.
    baseline_reads = read_count;
    baseline_writes = write_count;
    send_directed(2, 1, 1, 1, 400);
    if (read_count != baseline_reads || write_count != baseline_writes)
      fail("missing-pose event touched external memory");
    baseline_reads = read_count;
    baseline_writes = write_count;
    send_directed(7, 5, 0, 0, 401);
    if (read_count != baseline_reads || write_count != baseline_writes)
      fail("out-of-range transformed event touched external memory");
    baseline_reads = read_count;
    baseline_writes = write_count;
    send_directed(4, 6, 0, 1, 402);
    if (read_count != baseline_reads || write_count != baseline_writes)
      fail("non-power-of-two Y-range event touched external memory");

    // Sustained traffic makes the serialized writer backpressure the affine
    // stream and exercises both upstream terminal drop mechanisms.
    directed_mode = 0;
    for (burst_cycle = 0; burst_cycle < 48;
         burst_cycle = burst_cycle + 1) begin
      arrival = 64'hffff_ffff_ffff_ffff;
      polarity_in = {$random(rng_seed), $random(rng_seed)};
      occurrence_pose_version = 0;
      occurrence_timestamp = 1000 + burst_cycle;
      tick;
    end
    arrival = 0;
    polarity_in = 0;
    drain_all;

    if (system_pending != 0 || guard_total() != 0)
      fail("end-to-end pending or pose guard count leaked after drain");
    if (generated_count != aer_drop_count + fifo_drop_count +
                           completed_count)
      fail("final end-to-end conservation identity failed");
    if (aer_accepted_count != fifo_drop_count + completed_count)
      fail("accepted events did not all drop or complete exactly once");
    if (rr_count != world_consumed_count)
      fail("RR retirement and world consumption totals differ after drain");
    if (world_consumed_count != mapped_world_count + invalid_world_count)
      fail("world consumption classification totals differ");
    if (mapped_world_count != update_count + stale_count)
      fail("mapped world events did not all update or go stale");
    if (write_count != update_count || read_count != mapped_world_count)
      fail("external memory transaction totals disagree with surface status");
    if (aer_drop_count == 0 || fifo_drop_count == 0 ||
        world_stall_count == 0 || read_stall_count == 0 ||
        write_stall_count == 0 || equal_count == 0 || stale_count == 0 ||
        invalid_world_count < 3 || pose_accounting_error)
      fail("required integration/backpressure coverage was not reached");

    pose_wr_id = 0;
    #1;
    if (!pose_wr_ready)
      fail("pose guard remained busy after the full pipeline drained");

    $display("AER_SRAM_SURFACE_COUNTS generated=%0d aer_drop=%0d fifo_drop=%0d completed=%0d updates=%0d equal=%0d stale=%0d invalid=%0d",
             generated_count, aer_drop_count, fifo_drop_count,
             completed_count, update_count, equal_count, stale_count,
             invalid_world_count);
    $display("AER_SRAM_SURFACE_FLOW accepted=%0d rr=%0d world=%0d reads=%0d writes=%0d pending=%0d cycles=%0d",
             aer_accepted_count, rr_count, world_consumed_count,
             read_count, write_count, system_pending, cycle_count);
    $display("AER_SRAM_SURFACE_STALLS world=%0d read_req=%0d write_req=%0d",
             world_stall_count, read_stall_count, write_stall_count);
    if (error_count == 0) begin
      $display("AER_TX64_POSE_SRAM_SURFACE_PASS");
      $finish;
    end else begin
      $fatal(1, "AER_TX64_POSE_SRAM_SURFACE_FAIL errors=%0d", error_count);
    end
  end
endmodule
