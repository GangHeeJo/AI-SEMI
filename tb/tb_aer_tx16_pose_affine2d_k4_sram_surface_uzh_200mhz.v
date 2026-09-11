`timescale 1ns/1ps

// Real-time UZH schedule through K=4 transforms and a four-bank SRAM surface.
// Long idle gaps are skipped only after the complete DUT and memory model drain.
module tb_aer_tx16_pose_affine2d_k4_sram_surface_uzh_200mhz;
  parameter integer FIFO_DEPTH = 8;
  parameter integer MEM_RESPONSE_DELAY = 0;
  parameter integer DRAIN_LIMIT = 200000;
  parameter integer MAX_LATENCY = 20000;
  parameter integer MAX_EVENTS_PER_SOURCE = 2048;

  localparam POSE_W = 1;
  localparam SENSOR_W = 4;
  localparam RESULT_W = 8;
  localparam MATRIX_W = 16;
  localparam OFFSET_W = 24;
  localparam FRAC_W = 14;
  localparam TIMESTAMP_W = 64;
  localparam GRID_W = 4;
  localparam GRID_H = 4;
  localparam BANK_CELLS = 4;
  localparam ADDR_W = 2;
  localparam Q14_ONE = 16384;
  localparam RECORDS = 16 * MAX_EVENTS_PER_SOURCE;

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

  wire [15:0] aer_overrun;
  wire [7:0] fifo_overflow;
  wire pose_wr_ready;
  wire pose_wr_commit;
  wire pose_wr_rejected;
  wire pose_accounting_error;
  wire [3:0] world_valid;
  wire [3:0] world_ready;
  wire [3:0] mapped_valid;
  wire [3:0] pose_found;
  wire [3:0] in_range;
  wire [4*SENSOR_W-1:0] sensor_x_flat;
  wire [4*SENSOR_W-1:0] sensor_y_flat;
  wire [3:0] polarity_out;
  wire [4*POSE_W-1:0] pose_flat;
  wire [4*TIMESTAMP_W-1:0] timestamp_flat;
  wire [4*RESULT_W-1:0] world_x_flat;
  wire [4*RESULT_W-1:0] world_y_flat;
  wire [3:0] surface_update_applied;
  wire [3:0] surface_equal_time_merged;
  wire [3:0] surface_stale_ignored;
  wire [3:0] surface_range_error;
  wire [3:0] mem_rd_req_valid;
  wire [3:0] mem_rd_req_ready = 4'b1111;
  wire [4*ADDR_W-1:0] mem_rd_req_addr_flat;
  wire [3:0] mem_rd_rsp_valid;
  wire [3:0] mem_rd_rsp_ready;
  wire [3:0] mem_rd_rsp_cell_valid;
  wire [4*TIMESTAMP_W-1:0] mem_rd_rsp_timestamp_flat;
  wire [7:0] mem_rd_rsp_polarity_seen_flat;
  wire [3:0] mem_wr_req_valid;
  wire [3:0] mem_wr_req_ready = 4'b1111;
  wire [4*ADDR_W-1:0] mem_wr_req_addr_flat;
  wire [3:0] mem_wr_req_cell_valid;
  wire [4*TIMESTAMP_W-1:0] mem_wr_req_timestamp_flat;
  wire [7:0] mem_wr_req_polarity_seen_flat;
  wire [3:0] world_fire = world_valid & world_ready;

  aer_tx16_pose_affine2d_k4_sram_surface #(
    .FIFO_DEPTH(FIFO_DEPTH), .POSE_W(POSE_W), .SENSOR_W(SENSOR_W),
    .RESULT_W(RESULT_W), .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W),
    .FRAC_W(FRAC_W), .TIMESTAMP_W(TIMESTAMP_W),
    .GRID_W(GRID_W), .GRID_H(GRID_H), .BANK_ADDR_W(ADDR_W)
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
    .world_valid(world_valid), .world_ready(world_ready),
    .mapped_valid(mapped_valid), .pose_found(pose_found),
    .in_range(in_range),
    .sensor_x_out_flat(sensor_x_flat), .sensor_y_out_flat(sensor_y_flat),
    .polarity_out(polarity_out), .pose_version_out_flat(pose_flat),
    .occurrence_timestamp_out_flat(timestamp_flat),
    .world_x_out_flat(world_x_flat), .world_y_out_flat(world_y_flat),
    .surface_update_applied(surface_update_applied),
    .surface_equal_time_merged(surface_equal_time_merged),
    .surface_stale_ignored(surface_stale_ignored),
    .surface_range_error(surface_range_error),
    .mem_rd_req_valid(mem_rd_req_valid),
    .mem_rd_req_ready(mem_rd_req_ready),
    .mem_rd_req_addr_flat(mem_rd_req_addr_flat),
    .mem_rd_rsp_valid(mem_rd_rsp_valid),
    .mem_rd_rsp_ready(mem_rd_rsp_ready),
    .mem_rd_rsp_cell_valid(mem_rd_rsp_cell_valid),
    .mem_rd_rsp_timestamp_flat(mem_rd_rsp_timestamp_flat),
    .mem_rd_rsp_polarity_seen_flat(mem_rd_rsp_polarity_seen_flat),
    .mem_wr_req_valid(mem_wr_req_valid),
    .mem_wr_req_ready(mem_wr_req_ready),
    .mem_wr_req_addr_flat(mem_wr_req_addr_flat),
    .mem_wr_req_cell_valid(mem_wr_req_cell_valid),
    .mem_wr_req_timestamp_flat(mem_wr_req_timestamp_flat),
    .mem_wr_req_polarity_seen_flat(mem_wr_req_polarity_seen_flat)
  );

  reg memory_valid [0:15];
  reg [TIMESTAMP_W-1:0] memory_timestamp [0:15];
  reg [1:0] memory_polarity [0:15];
  reg [3:0] response_pending;
  reg [3:0] response_waiting;
  reg [ADDR_W-1:0] response_addr [0:3];
  integer response_delay [0:3];

  reg [TIMESTAMP_W-1:0] accepted_time [0:RECORDS-1];
  reg accepted_polarity [0:RECORDS-1];
  reg [TIMESTAMP_W-1:0] world_time_record [0:RECORDS-1];
  reg world_polarity_record [0:RECORDS-1];
  integer accepted_by_source [0:15];
  integer retired_by_source [0:15];
  integer world_by_source [0:15];
  integer committed_by_source [0:15];
  integer commits_by_bank [0:3];
  integer latency_hist [0:MAX_LATENCY];

  integer fd;
  integer scan_ret;
  reg [63:0] next_cycle;
  integer next_addr;
  integer next_pol;
  reg [63:0] logical_cycle;
  reg [63:0] first_cycle;
  reg [63:0] last_cycle;
  reg [63:0] skipped_idle_cycles;
  reg [63:0] latency_total;
  integer trace_rows;
  integer drain_cycles;
  integer stepped_cycles;
  integer generated_count;
  integer accepted_count;
  integer aer_drop_count;
  integer fifo_drop_count;
  integer pending_count;
  integer world_count;
  integer memory_write_count;
  integer update_count;
  integer equal_count;
  integer stale_count;
  integer range_count;
  integer latency_max;
  integer latency_p50;
  integer latency_p99;
  integer error_count;
  integer source;
  integer lane;
  integer adapter_lane;
  integer bank;
  integer index;
  integer record_index;
  integer got_x;
  integer got_y;
  integer got_source;
  integer got_polarity;
  reg [TIMESTAMP_W-1:0] got_timestamp;
  integer got_address;
  integer latency;
  integer cumulative;
  integer target50;
  integer target99;
  integer found50;
  integer found99;
  integer i;
  integer memory_loop;
  integer memory_array_index;

  genvar memory_bank;
  generate
    for (memory_bank = 0; memory_bank < 4;
         memory_bank = memory_bank + 1) begin: memory_outputs
      assign mem_rd_rsp_valid[memory_bank] = response_pending[memory_bank];
      assign mem_rd_rsp_cell_valid[memory_bank] =
        memory_valid[memory_bank*BANK_CELLS + response_addr[memory_bank]];
      assign mem_rd_rsp_timestamp_flat[
        memory_bank*TIMESTAMP_W +: TIMESTAMP_W] =
        memory_timestamp[
          memory_bank*BANK_CELLS + response_addr[memory_bank]];
      assign mem_rd_rsp_polarity_seen_flat[memory_bank*2 +: 2] =
        memory_polarity[
          memory_bank*BANK_CELLS + response_addr[memory_bank]];
    end
  endgenerate

  wire system_idle =
    pending_count == 0 && world_count == update_count + stale_count + range_count &&
    !(|world_valid) && !(|mem_rd_req_valid) && !(|mem_rd_rsp_valid) &&
    !(|mem_wr_req_valid) && !(|response_pending) && !(|response_waiting) &&
    !(|dut.u_tx.fifo_occupancy_flat);

  always #2.5 clk = ~clk;

  task automatic fail;
    input [8*128-1:0] message;
    begin
      error_count = error_count + 1;
      $display("UZH_200MHZ_MEMORY_FAIL logical_cycle=%0d %0s",
               logical_cycle, message);
    end
  endtask

  always @(posedge clk) begin
    if (rst) begin
      response_pending <= 0;
      response_waiting <= 0;
      for (memory_loop = 0; memory_loop < 4;
           memory_loop = memory_loop + 1) begin
        response_addr[memory_loop] <= 0;
        response_delay[memory_loop] <= 0;
      end
    end else begin
      for (memory_loop = 0; memory_loop < 4;
           memory_loop = memory_loop + 1) begin
        if (response_pending[memory_loop] &&
            mem_rd_rsp_ready[memory_loop])
          response_pending[memory_loop] <= 1'b0;
        if (response_waiting[memory_loop]) begin
          if (response_delay[memory_loop] == 0) begin
            response_waiting[memory_loop] <= 1'b0;
            response_pending[memory_loop] <= 1'b1;
          end else begin
            response_delay[memory_loop] <=
              response_delay[memory_loop] - 1;
          end
        end
        if (mem_rd_req_valid[memory_loop] &&
            mem_rd_req_ready[memory_loop]) begin
          if (response_pending[memory_loop] ||
              response_waiting[memory_loop])
            fail("memory accepted a second outstanding read");
          response_addr[memory_loop] <=
            mem_rd_req_addr_flat[memory_loop*ADDR_W +: ADDR_W];
          if (MEM_RESPONSE_DELAY == 0) begin
            response_pending[memory_loop] <= 1'b1;
          end else begin
            response_waiting[memory_loop] <= 1'b1;
            response_delay[memory_loop] <= MEM_RESPONSE_DELAY - 1;
          end
        end
        if (mem_wr_req_valid[memory_loop] &&
            mem_wr_req_ready[memory_loop]) begin
          memory_array_index = memory_loop*BANK_CELLS +
            mem_wr_req_addr_flat[memory_loop*ADDR_W +: ADDR_W];
          memory_valid[memory_array_index] <=
            mem_wr_req_cell_valid[memory_loop];
          memory_timestamp[memory_array_index] <=
            mem_wr_req_timestamp_flat[
              memory_loop*TIMESTAMP_W +: TIMESTAMP_W];
          memory_polarity[memory_array_index] <=
            mem_wr_req_polarity_seen_flat[memory_loop*2 +: 2];
        end
      end
    end
  end

  always @(posedge clk) begin
    if (!rst) begin
      stepped_cycles = stepped_cycles + 1;
      if (pose_accounting_error || pose_wr_rejected)
        fail("pose guard/write error");

      // A world handshake is the terminal transport action. Validate it
      // before same-edge FIFO drops so per-source order remains explicit.
      for (lane = 0; lane < 4; lane = lane + 1) begin
        if (world_fire[lane]) begin
          got_x = sensor_x_flat[lane*SENSOR_W +: SENSOR_W];
          got_y = sensor_y_flat[lane*SENSOR_W +: SENSOR_W];
          got_source = got_y*4 + got_x;
          if (got_x > 3 || got_y > 3 || got_source > 15) begin
            fail("world source coordinate escaped 4x4");
          end else if (retired_by_source[got_source] >=
                       accepted_by_source[got_source]) begin
            fail("world output was phantom or duplicated");
          end else begin
            record_index = got_source*MAX_EVENTS_PER_SOURCE +
                           retired_by_source[got_source];
            got_timestamp =
              timestamp_flat[lane*TIMESTAMP_W +: TIMESTAMP_W];
            got_polarity = polarity_out[lane];
            if (got_timestamp !== accepted_time[record_index] ||
                got_polarity != accepted_polarity[record_index])
              fail("world timestamp or polarity reordered within source");
            if (!mapped_valid[lane] || !pose_found[lane] ||
                !in_range[lane] ||
                pose_flat[lane*POSE_W +: POSE_W] != 0 || lane != got_x ||
                $signed(world_x_flat[lane*RESULT_W +: RESULT_W]) != got_x ||
                $signed(world_y_flat[lane*RESULT_W +: RESULT_W]) != got_y)
              fail("identity transform or static K4 lane mismatch");
            retired_by_source[got_source] =
              retired_by_source[got_source] + 1;
            pending_count = pending_count - 1;
            record_index = got_source*MAX_EVENTS_PER_SOURCE +
                           world_by_source[got_source];
            world_time_record[record_index] = got_timestamp;
            world_polarity_record[record_index] = got_polarity;
            world_by_source[got_source] = world_by_source[got_source] + 1;
            world_count = world_count + 1;
          end
        end
      end

      for (adapter_lane = 0; adapter_lane < 8;
           adapter_lane = adapter_lane + 1) begin
        if (fifo_overflow[adapter_lane]) begin
          got_x = dut.u_tx.batch_x_flat[
            adapter_lane*SENSOR_W +: SENSOR_W];
          got_y = dut.u_tx.batch_y_flat[
            adapter_lane*SENSOR_W +: SENSOR_W];
          got_source = got_y*4 + got_x;
          if (got_x > 3 || got_y > 3 ||
              retired_by_source[got_source] >=
              accepted_by_source[got_source]) begin
            fail("FIFO drop was phantom or malformed");
          end else begin
            record_index = got_source*MAX_EVENTS_PER_SOURCE +
                           retired_by_source[got_source];
            got_timestamp = dut.u_tx.batch_time_flat[
              adapter_lane*TIMESTAMP_W +: TIMESTAMP_W];
            got_polarity = dut.u_tx.batch_polarity[adapter_lane];
            if (got_timestamp !== accepted_time[record_index] ||
                got_polarity != accepted_polarity[record_index])
              fail("FIFO drop metadata reordered within source");
            retired_by_source[got_source] =
              retired_by_source[got_source] + 1;
            pending_count = pending_count - 1;
            fifo_drop_count = fifo_drop_count + 1;
          end
        end
      end

      for (bank = 0; bank < 4; bank = bank + 1) begin
        if (mem_wr_req_valid[bank] && mem_wr_req_ready[bank]) begin
          got_address =
            mem_wr_req_addr_flat[bank*ADDR_W +: ADDR_W];
          got_source = got_address*4 + bank;
          if (got_address > 3 || committed_by_source[got_source] >=
              world_by_source[got_source]) begin
            fail("memory write was phantom or used a bad address");
          end else begin
            record_index = got_source*MAX_EVENTS_PER_SOURCE +
                           committed_by_source[got_source];
            got_timestamp = mem_wr_req_timestamp_flat[
              bank*TIMESTAMP_W +: TIMESTAMP_W];
            if (got_timestamp !== world_time_record[record_index] ||
                mem_wr_req_polarity_seen_flat[bank*2 +: 2] !==
                  (world_polarity_record[record_index] ? 2'b10 : 2'b01) ||
                !mem_wr_req_cell_valid[bank])
              fail("memory commit payload mismatch");
            if (logical_cycle < got_timestamp) begin
              fail("memory commit preceded occurrence cycle");
            end else begin
              latency = logical_cycle - got_timestamp;
              if (latency > MAX_LATENCY) begin
                fail("memory commit latency exceeded histogram range");
              end else begin
                latency_hist[latency] = latency_hist[latency] + 1;
                latency_total = latency_total + latency;
                if (latency > latency_max)
                  latency_max = latency;
              end
            end
            committed_by_source[got_source] =
              committed_by_source[got_source] + 1;
            commits_by_bank[bank] = commits_by_bank[bank] + 1;
            memory_write_count = memory_write_count + 1;
          end
        end
        if (surface_update_applied[bank])
          update_count = update_count + 1;
        if (surface_equal_time_merged[bank])
          equal_count = equal_count + 1;
        if (surface_stale_ignored[bank])
          stale_count = stale_count + 1;
        if (surface_range_error[bank])
          range_count = range_count + 1;
      end

      for (source = 0; source < 16; source = source + 1) begin
        if (arrival[source]) begin
          generated_count = generated_count + 1;
          if (aer_overrun[source]) begin
            aer_drop_count = aer_drop_count + 1;
          end else if (accepted_by_source[source] >=
                       MAX_EVENTS_PER_SOURCE) begin
            fail("per-source scoreboard capacity exceeded");
          end else begin
            record_index = source*MAX_EVENTS_PER_SOURCE +
                           accepted_by_source[source];
            accepted_time[record_index] = occurrence_timestamp;
            accepted_polarity[record_index] = polarity_in[source];
            accepted_by_source[source] = accepted_by_source[source] + 1;
            accepted_count = accepted_count + 1;
            pending_count = pending_count + 1;
          end
        end
      end
    end
  end

  task automatic program_identity_pose;
    begin
      @(negedge clk);
      pose_wr_id = 0;
      pose_wr_m00 = Q14_ONE;
      pose_wr_m01 = 0;
      pose_wr_m10 = 0;
      pose_wr_m11 = Q14_ONE;
      pose_wr_tx = 0;
      pose_wr_ty = 0;
      pose_wr_req = 1'b1;
      #1;
      if (!pose_wr_ready || !pose_wr_commit || pose_wr_rejected)
        fail("identity pose write did not commit");
      @(posedge clk);
      #1;
      pose_wr_req = 1'b0;
    end
  endtask

  task automatic step_cycle;
    input [15:0] address_in;
    input [15:0] polarity_value;
    begin
      @(negedge clk);
      arrival = address_in;
      polarity_in = polarity_value & address_in;
      occurrence_pose_version = 0;
      occurrence_timestamp = logical_cycle;
      @(posedge clk);
      #1;
      arrival = 0;
      polarity_in = 0;
      logical_cycle = logical_cycle + 1;
    end
  endtask

  task automatic calculate_percentiles;
    begin
      target50 = (memory_write_count + 1) / 2;
      target99 = (memory_write_count*99 + 99) / 100;
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
    if (MEM_RESPONSE_DELAY < 0)
      $fatal(1, "MEM_RESPONSE_DELAY must be non-negative");
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
    logical_cycle = 0;
    first_cycle = 0;
    last_cycle = 0;
    skipped_idle_cycles = 0;
    latency_total = 0;
    trace_rows = 0;
    drain_cycles = 0;
    stepped_cycles = 0;
    generated_count = 0;
    accepted_count = 0;
    aer_drop_count = 0;
    fifo_drop_count = 0;
    pending_count = 0;
    world_count = 0;
    memory_write_count = 0;
    update_count = 0;
    equal_count = 0;
    stale_count = 0;
    range_count = 0;
    latency_max = 0;
    latency_p50 = 0;
    latency_p99 = 0;
    error_count = 0;
    for (i = 0; i < 16; i = i + 1) begin
      memory_valid[i] = 1'b0;
      memory_timestamp[i] = 0;
      memory_polarity[i] = 0;
      accepted_by_source[i] = 0;
      retired_by_source[i] = 0;
      world_by_source[i] = 0;
      committed_by_source[i] = 0;
    end
    for (i = 0; i < 4; i = i + 1)
      commits_by_bank[i] = 0;
    for (i = 0; i <= MAX_LATENCY; i = i + 1)
      latency_hist[i] = 0;

    if (!$value$plusargs("TRACE_FILE=%s", trace_file_r))
      $fatal(1, "trace path is required via +TRACE_FILE=");
    fd = $fopen(trace_file_r, "r");
    if (fd == 0)
      $fatal(1, "cannot open trace %0s", trace_file_r);
    scan_ret = $fscanf(fd, "%d %h %h", next_cycle, next_addr, next_pol);
    if (scan_ret != 3)
      $fatal(1, "200 MHz trace is empty or malformed");
    first_cycle = next_cycle;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    program_identity_pose();

    while (scan_ret == 3) begin
      if (next_cycle < logical_cycle) begin
        fail("trace cycle moved backward");
      end else begin
        while (logical_cycle < next_cycle) begin
          if (system_idle) begin
            skipped_idle_cycles = skipped_idle_cycles +
                                  (next_cycle - logical_cycle);
            logical_cycle = next_cycle;
          end else begin
            step_cycle(0, 0);
          end
        end
      end
      step_cycle(next_addr[15:0], next_pol[15:0]);
      trace_rows = trace_rows + 1;
      last_cycle = next_cycle;
      scan_ret = $fscanf(fd, "%d %h %h", next_cycle, next_addr, next_pol);
    end

    while (!system_idle && drain_cycles < DRAIN_LIMIT) begin
      step_cycle(0, 0);
      drain_cycles = drain_cycles + 1;
    end
    repeat (3)
      step_cycle(0, 0);

    if (!system_idle)
      fail("bounded drain did not empty transport and memory");
    if (generated_count != 8503 || trace_rows != 8461)
      fail("checked-in 200 MHz trace receipt changed");
    if (generated_count != accepted_count + aer_drop_count)
      fail("generated/AER conservation mismatch");
    if (accepted_count != fifo_drop_count + world_count)
      fail("accepted/FIFO/world conservation mismatch");
    if (world_count != memory_write_count ||
        memory_write_count != update_count)
      fail("world/memory/update conservation mismatch");
    if (equal_count != 0 || stale_count != 0 || range_count != 0)
      fail("identity traffic produced equal/stale/range terminal status");
    if (memory_write_count == 0)
      fail("memory latency population is empty");
    for (source = 0; source < 16; source = source + 1) begin
      if (retired_by_source[source] != accepted_by_source[source])
        fail("accepted source record did not retire");
      if (committed_by_source[source] != world_by_source[source])
        fail("world source record did not commit");
    end
    pose_wr_id = 0;
    #1;
    if (!pose_wr_ready || pose_accounting_error)
      fail("pose guard did not drain");

    calculate_percentiles();
    $display(
      "UZH_200MHZ_MEMORY timebase=eventmeta_ns_floor_5ns idle_skip=only_when_empty fifo_depth=%0d mem_response_delay=%0d trace_rows=%0d span_cycles=%0d skipped_idle=%0d stepped=%0d drain=%0d",
      FIFO_DEPTH, MEM_RESPONSE_DELAY, trace_rows, last_cycle-first_cycle,
      skipped_idle_cycles, stepped_cycles, drain_cycles);
    $display(
      "UZH_200MHZ_MEMORY_COUNTS generated=%0d accepted=%0d aer_overrun=%0d fifo_overflow=%0d world=%0d committed=%0d updates=%0d bank_commits=%0d,%0d,%0d,%0d",
      generated_count, accepted_count, aer_drop_count, fifo_drop_count,
      world_count, memory_write_count, update_count, commits_by_bank[0],
      commits_by_bank[1], commits_by_bank[2], commits_by_bank[3]);
    $display(
      "UZH_200MHZ_MEMORY_LATENCY population=%0d mean=%0d p50=%0d p99=%0d max=%0d",
      memory_write_count, latency_total/memory_write_count,
      latency_p50, latency_p99, latency_max);
    if (error_count == 0) begin
      $display("STAGE2_K4_SRAM_UZH_200MHZ_PASS");
      $fclose(fd);
      $finish;
    end else begin
      $fclose(fd);
      $fatal(1, "STAGE2_K4_SRAM_UZH_200MHZ_FAIL errors=%0d", error_count);
    end
  end

  initial begin
    #200000000;
    $fatal(1, "STAGE2_K4_SRAM_UZH_200MHZ_TIMEOUT");
  end
endmodule
