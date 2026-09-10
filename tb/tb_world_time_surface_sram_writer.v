`timescale 1ns/1ps

module tb_world_time_surface_sram_writer;
  localparam integer GRID_W = 7;
  localparam integer GRID_H = 6;
  localparam integer CELLS = GRID_W * GRID_H;
  localparam integer COORD_W = 8;
  localparam integer TIMESTAMP_W = 12;
  localparam integer ADDR_W = $clog2(CELLS);
  localparam integer RANDOM_EVENTS = 2500;

  localparam integer IDLE = 0;
  localparam integer READ_REQUEST = 1;
  localparam integer READ_RESPONSE = 2;
  localparam integer WRITE_REQUEST = 3;

  reg clk = 1'b0;
  reg rst;
  reg event_valid;
  wire event_ready;
  reg mapped_valid;
  reg signed [COORD_W-1:0] world_x;
  reg signed [COORD_W-1:0] world_y;
  reg polarity;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp;
  wire update_applied;
  wire equal_time_merged;
  wire stale_ignored;
  wire range_error;

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

  world_time_surface_sram_writer #(
    .GRID_W(GRID_W), .GRID_H(GRID_H), .COORD_W(COORD_W),
    .TIMESTAMP_W(TIMESTAMP_W), .ADDR_W(ADDR_W)
  ) dut (
    .clk(clk), .rst(rst),
    .event_valid(event_valid), .event_ready(event_ready),
    .mapped_valid(mapped_valid), .world_x(world_x), .world_y(world_y),
    .polarity(polarity), .occurrence_timestamp(occurrence_timestamp),
    .update_applied(update_applied),
    .equal_time_merged(equal_time_merged),
    .stale_ignored(stale_ignored), .range_error(range_error),
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
  reg oracle_valid [0:CELLS-1];
  reg [TIMESTAMP_W-1:0] oracle_timestamp [0:CELLS-1];
  reg [1:0] oracle_polarity [0:CELLS-1];

  reg response_pending;
  integer response_delay;
  reg response_pending_valid;
  reg [TIMESTAMP_W-1:0] response_pending_timestamp;
  reg [1:0] response_pending_polarity;
  integer memory_seed;

  integer model_phase;
  integer next_model_phase;
  integer pending_addr;
  integer pending_polarity;
  reg [TIMESTAMP_W-1:0] pending_timestamp;
  integer expected_write_addr;
  reg [TIMESTAMP_W-1:0] expected_write_timestamp;
  reg [1:0] expected_write_polarity;
  integer expected_write_equal;
  integer apply_oracle_write;

  integer expected_update;
  integer expected_equal;
  integer expected_stale;
  integer expected_range;
  integer last_event_handshake;
  integer cycle_count;
  integer generated_count;
  integer accepted_count;
  integer mapped_ignored_count;
  integer range_count;
  integer update_count;
  integer equal_count;
  integer stale_count;
  integer read_stall_count;
  integer write_stall_count;
  integer response_wait_cycles;
  integer event_stall_count;
  integer error_count;
  integer rng_seed;
  integer i;
  integer event_index;
  integer address;
  integer mode;
  integer random_value;
  integer send_done;
  integer drain_count;

  reg held_event;
  reg held_mapped_valid;
  reg signed [COORD_W-1:0] held_world_x;
  reg signed [COORD_W-1:0] held_world_y;
  reg held_polarity;
  reg [TIMESTAMP_W-1:0] held_timestamp;
  reg held_read;
  reg [ADDR_W-1:0] held_read_addr;
  reg held_write;
  reg [ADDR_W-1:0] held_write_addr;
  reg held_write_valid;
  reg [TIMESTAMP_W-1:0] held_write_timestamp;
  reg [1:0] held_write_polarity;

  task automatic fail;
    input [1023:0] message;
    begin
      error_count = error_count + 1;
      if (error_count <= 30)
        $display("FAIL cycle=%0d phase=%0d: %0s",
                 cycle_count, model_phase, message);
    end
  endtask

  // External single-outstanding SRAM model. Read response latency is 1..8
  // cycles after request acceptance and response data remains valid until used.
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
          $fatal(1, "memory model received more than one outstanding read");
        response_pending <= 1'b1;
        response_delay <= (($random(memory_seed) % 8) + 8) % 8;
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
        memory_valid[mem_wr_req_addr] <= mem_wr_req_cell_valid;
        memory_timestamp[mem_wr_req_addr] <= mem_wr_req_timestamp;
        memory_polarity[mem_wr_req_addr] <= mem_wr_req_polarity_seen;
      end
    end
  end

  task automatic check_stability;
    begin
      if (held_event) begin
        if (!event_valid || mapped_valid !== held_mapped_valid ||
            world_x !== held_world_x || world_y !== held_world_y ||
            polarity !== held_polarity ||
            occurrence_timestamp !== held_timestamp)
          fail("producer event changed while backpressured");
      end
      if (held_read &&
          (!mem_rd_req_valid || mem_rd_req_addr !== held_read_addr))
        fail("read request changed while memory stalled");
      if (held_write &&
          (!mem_wr_req_valid || mem_wr_req_addr !== held_write_addr ||
           mem_wr_req_cell_valid !== held_write_valid ||
           mem_wr_req_timestamp !== held_write_timestamp ||
           mem_wr_req_polarity_seen !== held_write_polarity))
        fail("write request changed while memory stalled");
    end
  endtask

  task automatic check_phase_outputs;
    begin
      if (event_ready !== (model_phase == IDLE))
        fail("event_ready disagrees with the single-outstanding model");
      if (mem_rd_req_valid !== (model_phase == READ_REQUEST))
        fail("read request valid asserted in the wrong phase");
      if (mem_rd_rsp_ready !== (model_phase == READ_RESPONSE))
        fail("read response ready asserted in the wrong phase");
      if (mem_wr_req_valid !== (model_phase == WRITE_REQUEST))
        fail("write request valid asserted in the wrong phase");
      if (model_phase == READ_REQUEST &&
          mem_rd_req_addr !== pending_addr[ADDR_W-1:0])
        fail("read request address mismatch");
      if (model_phase == WRITE_REQUEST &&
          (mem_wr_req_addr !== expected_write_addr[ADDR_W-1:0] ||
           mem_wr_req_cell_valid !== 1'b1 ||
           mem_wr_req_timestamp !== expected_write_timestamp ||
           mem_wr_req_polarity_seen !== expected_write_polarity))
        fail("write request payload mismatch");
    end
  endtask

  task automatic sample_before_edge;
    reg [1:0] incoming_polarity;
    begin
      check_stability;
      check_phase_outputs;
      expected_update = 0;
      expected_equal = 0;
      expected_stale = 0;
      expected_range = 0;
      apply_oracle_write = 0;
      last_event_handshake = 0;
      next_model_phase = model_phase;

      case (model_phase)
        IDLE: begin
          if (event_valid && event_ready) begin
            last_event_handshake = 1;
            accepted_count = accepted_count + 1;
            if (!mapped_valid) begin
              mapped_ignored_count = mapped_ignored_count + 1;
            end else if ($signed(world_x) < 0 || $signed(world_x) >= GRID_W ||
                         $signed(world_y) < 0 || $signed(world_y) >= GRID_H) begin
              expected_range = 1;
              range_count = range_count + 1;
            end else begin
              pending_addr = $signed(world_y) * GRID_W + $signed(world_x);
              pending_polarity = polarity;
              pending_timestamp = occurrence_timestamp;
              next_model_phase = READ_REQUEST;
            end
          end
        end

        READ_REQUEST: begin
          if (mem_rd_req_valid && mem_rd_req_ready)
            next_model_phase = READ_RESPONSE;
          else
            read_stall_count = read_stall_count + 1;
        end

        READ_RESPONSE: begin
          if (mem_rd_rsp_valid && mem_rd_rsp_ready) begin
            if (mem_rd_rsp_cell_valid !== oracle_valid[pending_addr] ||
                mem_rd_rsp_timestamp !== oracle_timestamp[pending_addr] ||
                mem_rd_rsp_polarity_seen !== oracle_polarity[pending_addr])
              fail("read response differs from the software memory oracle");
            incoming_polarity = pending_polarity ? 2'b10 : 2'b01;
            if (!oracle_valid[pending_addr] ||
                pending_timestamp > oracle_timestamp[pending_addr]) begin
              expected_write_addr = pending_addr;
              expected_write_timestamp = pending_timestamp;
              expected_write_polarity = incoming_polarity;
              expected_write_equal = 0;
              next_model_phase = WRITE_REQUEST;
            end else if (pending_timestamp ==
                         oracle_timestamp[pending_addr]) begin
              expected_write_addr = pending_addr;
              expected_write_timestamp = oracle_timestamp[pending_addr];
              expected_write_polarity = oracle_polarity[pending_addr] |
                                        incoming_polarity;
              expected_write_equal = 1;
              next_model_phase = WRITE_REQUEST;
            end else begin
              expected_stale = 1;
              stale_count = stale_count + 1;
              next_model_phase = IDLE;
            end
          end else begin
            response_wait_cycles = response_wait_cycles + 1;
          end
        end

        WRITE_REQUEST: begin
          if (mem_wr_req_valid && mem_wr_req_ready) begin
            expected_update = 1;
            expected_equal = expected_write_equal;
            update_count = update_count + 1;
            if (expected_write_equal)
              equal_count = equal_count + 1;
            apply_oracle_write = 1;
            next_model_phase = IDLE;
          end else begin
            write_stall_count = write_stall_count + 1;
          end
        end
      endcase

      held_event = event_valid && !event_ready;
      held_mapped_valid = mapped_valid;
      held_world_x = world_x;
      held_world_y = world_y;
      held_polarity = polarity;
      held_timestamp = occurrence_timestamp;
      held_read = mem_rd_req_valid && !mem_rd_req_ready;
      held_read_addr = mem_rd_req_addr;
      held_write = mem_wr_req_valid && !mem_wr_req_ready;
      held_write_addr = mem_wr_req_addr;
      held_write_valid = mem_wr_req_cell_valid;
      held_write_timestamp = mem_wr_req_timestamp;
      held_write_polarity = mem_wr_req_polarity_seen;
    end
  endtask

  task automatic check_after_edge;
    begin
      #1;
      if (apply_oracle_write) begin
        oracle_valid[expected_write_addr] = 1'b1;
        oracle_timestamp[expected_write_addr] = expected_write_timestamp;
        oracle_polarity[expected_write_addr] = expected_write_polarity;
      end
      model_phase = next_model_phase;
      if (update_applied !== expected_update[0] ||
          equal_time_merged !== expected_equal[0] ||
          stale_ignored !== expected_stale[0] ||
          range_error !== expected_range[0])
        fail("status pulse mismatch");
      if (event_ready !== (model_phase == IDLE))
        fail("post-edge event_ready mismatch");
      if (apply_oracle_write &&
          (memory_valid[expected_write_addr] !== 1'b1 ||
           memory_timestamp[expected_write_addr] !== expected_write_timestamp ||
           memory_polarity[expected_write_addr] !== expected_write_polarity))
        fail("external memory write did not match the oracle");
      cycle_count = cycle_count + 1;
    end
  endtask

  task automatic tick;
    begin
      @(negedge clk);
      random_value = (($random(rng_seed) % 100) + 100) % 100;
      mem_rd_req_ready = (random_value < 53);
      random_value = (($random(rng_seed) % 100) + 100) % 100;
      mem_wr_req_ready = (random_value < 47);
      #1;
      sample_before_edge;
      @(posedge clk);
      check_after_edge;
    end
  endtask

  task automatic send_event;
    input integer mapped_in;
    input integer x_in;
    input integer y_in;
    input integer polarity_in;
    input integer timestamp_in;
    begin
      event_valid = 1'b1;
      mapped_valid = mapped_in[0];
      world_x = x_in;
      world_y = y_in;
      polarity = polarity_in[0];
      occurrence_timestamp = timestamp_in;
      generated_count = generated_count + 1;
      send_done = 0;
      while (!send_done) begin
        tick;
        if (last_event_handshake)
          send_done = 1;
        else
          event_stall_count = event_stall_count + 1;
      end
      event_valid = 1'b0;
    end
  endtask

  initial begin
    rst = 1'b1;
    event_valid = 0;
    mapped_valid = 0;
    world_x = 0;
    world_y = 0;
    polarity = 0;
    occurrence_timestamp = 0;
    mem_rd_req_ready = 0;
    mem_wr_req_ready = 0;
    mem_rd_rsp_valid = 0;
    mem_rd_rsp_cell_valid = 0;
    mem_rd_rsp_timestamp = 0;
    mem_rd_rsp_polarity_seen = 0;
    response_pending = 0;
    response_pending_valid = 0;
    response_pending_timestamp = 0;
    response_pending_polarity = 0;
    model_phase = IDLE;
    next_model_phase = IDLE;
    pending_addr = 0;
    pending_polarity = 0;
    pending_timestamp = 0;
    expected_write_addr = 0;
    expected_write_timestamp = 0;
    expected_write_polarity = 0;
    expected_write_equal = 0;
    apply_oracle_write = 0;
    expected_update = 0;
    expected_equal = 0;
    expected_stale = 0;
    expected_range = 0;
    last_event_handshake = 0;
    cycle_count = 0;
    generated_count = 0;
    accepted_count = 0;
    mapped_ignored_count = 0;
    range_count = 0;
    update_count = 0;
    equal_count = 0;
    stale_count = 0;
    read_stall_count = 0;
    write_stall_count = 0;
    response_wait_cycles = 0;
    event_stall_count = 0;
    error_count = 0;
    rng_seed = 32'h13579bdf;
    memory_seed = 32'h2468ace1;
    held_event = 0;
    held_read = 0;
    held_write = 0;
    drain_count = 0;
    for (i = 0; i < CELLS; i = i + 1) begin
      memory_valid[i] = 0;
      memory_timestamp[i] = 0;
      memory_polarity[i] = 0;
      oracle_valid[i] = 0;
      oracle_timestamp[i] = 0;
      oracle_polarity[i] = 0;
    end

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    #1;
    if (!event_ready || mem_rd_req_valid || mem_rd_rsp_ready ||
        mem_wr_req_valid)
      fail("reset release interface state mismatch");
    // Move past the first reset-free edge before the event-driving tasks,
    // which present their next payload immediately after a positive edge.
    @(posedge clk);
    #1;

    // Directed semantics: new, equal-time polarity OR, stale, mapping failure,
    // and both signed-low and non-power-of-two-high range failures.
    send_event(1, 2, 3, 0, 100);
    send_event(1, 2, 3, 1, 100);
    send_event(1, 2, 3, 0, 99);
    send_event(0, 2, 3, 1, 300);
    send_event(1, -1, 3, 0, 301);
    send_event(1, GRID_W, 3, 1, 302);
    send_event(1, 2, -2, 0, 303);
    send_event(1, 2, GRID_H, 1, 304);

    for (event_index = 0; event_index < RANDOM_EVENTS;
         event_index = event_index + 1) begin
      random_value = (($random(rng_seed) % 100) + 100) % 100;
      mode = random_value % 10;
      world_x = (($random(rng_seed) % GRID_W) + GRID_W) % GRID_W;
      world_y = (($random(rng_seed) % GRID_H) + GRID_H) % GRID_H;
      address = world_y * GRID_W + world_x;
      polarity = $random(rng_seed);

      if (mode == 0) begin
        send_event(0, world_x, world_y, polarity, $random(rng_seed));
      end else if (mode == 1) begin
        send_event(1, -1, world_y, polarity, $random(rng_seed));
      end else if (mode == 2) begin
        send_event(1, GRID_W, world_y, polarity, $random(rng_seed));
      end else if (!oracle_valid[address]) begin
        send_event(1, world_x, world_y, polarity,
                   1 + ($random(rng_seed) & 12'h3ff));
      end else if (mode <= 5) begin
        send_event(1, world_x, world_y, polarity,
                   oracle_timestamp[address] + 1 +
                   ($random(rng_seed) & 12'h00f));
      end else if (mode <= 7) begin
        send_event(1, world_x, world_y, polarity,
                   oracle_timestamp[address]);
      end else begin
        send_event(1, world_x, world_y, polarity,
                   (oracle_timestamp[address] == 0) ? 0 :
                   oracle_timestamp[address] - 1);
      end
    end

    event_valid = 0;
    while ((model_phase != IDLE || response_pending || mem_rd_rsp_valid) &&
           drain_count < 100) begin
      tick;
      drain_count = drain_count + 1;
    end
    repeat (3)
      tick;

    if (model_phase != IDLE || response_pending || mem_rd_rsp_valid)
      fail("serialized transaction did not drain");
    if (generated_count != accepted_count)
      fail("generated event was lost under input backpressure");
    for (i = 0; i < CELLS; i = i + 1) begin
      if (memory_valid[i] !== oracle_valid[i] ||
          memory_timestamp[i] !== oracle_timestamp[i] ||
          memory_polarity[i] !== oracle_polarity[i])
        fail("final external memory image differs from oracle");
    end
    if (mapped_ignored_count == 0 || range_count == 0 ||
        update_count == 0 || equal_count == 0 || stale_count == 0 ||
        read_stall_count == 0 || write_stall_count == 0 ||
        response_wait_cycles == 0 || event_stall_count == 0)
      fail("required semantic or backpressure coverage was not reached");

    $display("WORLD_TIME_SURFACE_SRAM_COUNTS events=%0d updates=%0d equal=%0d stale=%0d range=%0d mapped_invalid=%0d cycles=%0d",
             generated_count, update_count, equal_count, stale_count,
             range_count, mapped_ignored_count, cycle_count);
    $display("WORLD_TIME_SURFACE_SRAM_STALLS event=%0d read_req=%0d response_wait=%0d write_req=%0d",
             event_stall_count, read_stall_count,
             response_wait_cycles, write_stall_count);
    if (error_count == 0) begin
      $display("WORLD_TIME_SURFACE_SRAM_WRITER_PASS");
      $finish;
    end else begin
      $fatal(1, "WORLD_TIME_SURFACE_SRAM_WRITER_FAIL errors=%0d",
             error_count);
    end
  end
endmodule
