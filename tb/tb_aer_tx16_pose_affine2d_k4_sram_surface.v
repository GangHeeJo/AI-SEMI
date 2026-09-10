`timescale 1ns/1ps

module tb_aer_tx16_pose_affine2d_k4_sram_surface;
  localparam integer POSE_W = 2;
  localparam integer SENSOR_W = 4;
  localparam integer RESULT_W = 8;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer FRAC_W = 14;
  localparam integer TIMESTAMP_W = 8;
  localparam integer FIFO_DEPTH = 4;
  localparam integer GUARD_COUNT_W = 6;
  localparam integer GRID_W = 8;
  localparam integer GRID_H = 4;
  localparam integer BANK_GRID_W = GRID_W / 4;
  localparam integer BANK_CELLS = BANK_GRID_W * GRID_H;
  localparam integer ADDR_W = $clog2(BANK_CELLS);
  localparam integer TARGET_ADDR = 2 * BANK_GRID_W;
  localparam integer UNKNOWN_ADDR = 1 * BANK_GRID_W;
  localparam integer Q = (1 << FRAC_W);

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

  wire [3:0] world_valid;
  wire [3:0] world_ready;
  wire [3:0] mapped_valid;
  wire [3:0] pose_found;
  wire [3:0] in_range;
  wire [4*SENSOR_W-1:0] sensor_x_out_flat;
  wire [4*SENSOR_W-1:0] sensor_y_out_flat;
  wire [3:0] polarity_out;
  wire [4*POSE_W-1:0] pose_version_out_flat;
  wire [4*TIMESTAMP_W-1:0] occurrence_timestamp_out_flat;
  wire [4*RESULT_W-1:0] world_x_out_flat;
  wire [4*RESULT_W-1:0] world_y_out_flat;

  wire [3:0] surface_update_applied;
  wire [3:0] surface_equal_time_merged;
  wire [3:0] surface_stale_ignored;
  wire [3:0] surface_range_error;
  wire [3:0] mem_rd_req_valid;
  reg [3:0] mem_rd_req_ready;
  wire [4*ADDR_W-1:0] mem_rd_req_addr_flat;
  wire [3:0] mem_rd_rsp_valid;
  wire [3:0] mem_rd_rsp_ready;
  wire [3:0] mem_rd_rsp_cell_valid;
  wire [4*TIMESTAMP_W-1:0] mem_rd_rsp_timestamp_flat;
  wire [7:0] mem_rd_rsp_polarity_seen_flat;
  wire [3:0] mem_wr_req_valid;
  reg [3:0] mem_wr_req_ready;
  wire [4*ADDR_W-1:0] mem_wr_req_addr_flat;
  wire [3:0] mem_wr_req_cell_valid;
  wire [4*TIMESTAMP_W-1:0] mem_wr_req_timestamp_flat;
  wire [7:0] mem_wr_req_polarity_seen_flat;

  aer_tx16_pose_affine2d_k4_sram_surface #(
    .FIFO_DEPTH(FIFO_DEPTH), .POSE_W(POSE_W),
    .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .TIMESTAMP_W(TIMESTAMP_W), .GUARD_COUNT_W(GUARD_COUNT_W),
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
    .in_range(in_range), .sensor_x_out_flat(sensor_x_out_flat),
    .sensor_y_out_flat(sensor_y_out_flat),
    .polarity_out(polarity_out),
    .pose_version_out_flat(pose_version_out_flat),
    .occurrence_timestamp_out_flat(occurrence_timestamp_out_flat),
    .world_x_out_flat(world_x_out_flat),
    .world_y_out_flat(world_y_out_flat),
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

  always #5 clk = ~clk;

  reg memory_valid [0:4*BANK_CELLS-1];
  reg [TIMESTAMP_W-1:0] memory_timestamp [0:4*BANK_CELLS-1];
  reg [1:0] memory_polarity [0:4*BANK_CELLS-1];
  reg [3:0] response_pending;
  reg [ADDR_W-1:0] response_addr [0:3];

  integer read_count [0:3];
  integer write_count [0:3];
  integer update_count [0:3];
  integer equal_count [0:3];
  integer stale_count [0:3];
  integer world_count;
  integer invalid_world_count;
  integer input_count;
  integer error_count;
  integer cycle_count;
  integer initial_world_count;
  integer time20_pol0_count;
  integer time20_pol1_count;
  integer bank_i;
  integer memory_bank;
  integer monitor_bank;
  integer cell_i;
  integer source_i;
  reg [3:0] initial_seen;
  reg saw_four_world;
  reg saw_four_reads;
  reg saw_four_writes;
  reg overrun_seen;
  reg fifo_overflow_seen;

  genvar bank;
  generate
    for (bank = 0; bank < 4; bank = bank + 1) begin: memory_response
      assign mem_rd_rsp_valid[bank] = response_pending[bank];
      assign mem_rd_rsp_cell_valid[bank] =
        memory_valid[bank*BANK_CELLS + response_addr[bank]];
      assign mem_rd_rsp_timestamp_flat[bank*TIMESTAMP_W +: TIMESTAMP_W] =
        memory_timestamp[bank*BANK_CELLS + response_addr[bank]];
      assign mem_rd_rsp_polarity_seen_flat[bank*2 +: 2] =
        memory_polarity[bank*BANK_CELLS + response_addr[bank]];
    end
  endgenerate

  task automatic fail;
    input [1023:0] message;
    begin
      error_count = error_count + 1;
      $display("FAIL cycle=%0d: %0s", cycle_count, message);
    end
  endtask

  function integer total_reads;
    integer b;
    begin
      total_reads = 0;
      for (b = 0; b < 4; b = b + 1)
        total_reads = total_reads + read_count[b];
    end
  endfunction

  function integer total_writes;
    integer b;
    begin
      total_writes = 0;
      for (b = 0; b < 4; b = b + 1)
        total_writes = total_writes + write_count[b];
    end
  endfunction

  function integer total_updates;
    integer b;
    begin
      total_updates = 0;
      for (b = 0; b < 4; b = b + 1)
        total_updates = total_updates + update_count[b];
    end
  endfunction

  function integer total_equal;
    integer b;
    begin
      total_equal = 0;
      for (b = 0; b < 4; b = b + 1)
        total_equal = total_equal + equal_count[b];
    end
  endfunction

  function integer total_stale;
    integer b;
    begin
      total_stale = 0;
      for (b = 0; b < 4; b = b + 1)
        total_stale = total_stale + stale_count[b];
    end
  endfunction

  task automatic check_world;
    input integer bank_in;
    integer got_x;
    integer got_y;
    integer got_pol;
    integer got_pose;
    integer got_time;
    integer got_wx;
    integer got_wy;
    begin
      got_x = sensor_x_out_flat[bank_in*SENSOR_W +: SENSOR_W];
      got_y = sensor_y_out_flat[bank_in*SENSOR_W +: SENSOR_W];
      got_pol = polarity_out[bank_in];
      got_pose = pose_version_out_flat[bank_in*POSE_W +: POSE_W];
      got_time = occurrence_timestamp_out_flat[
        bank_in*TIMESTAMP_W +: TIMESTAMP_W];
      got_wx = $signed(world_x_out_flat[
        bank_in*RESULT_W +: RESULT_W]);
      got_wy = $signed(world_y_out_flat[
        bank_in*RESULT_W +: RESULT_W]);

      case (got_time)
        10: begin
          if (bank_in != got_x || got_y != 2 ||
              got_pol != (bank_in & 1) || got_pose != 0 ||
              !mapped_valid[bank_in] || !pose_found[bank_in] ||
              !in_range[bank_in] || got_wx != got_x || got_wy != got_y)
            fail("four-column identity world metadata mismatch");
          if (initial_seen[bank_in])
            fail("four-column event appeared twice on one transform bank");
          initial_seen[bank_in] = 1'b1;
          initial_world_count = initial_world_count + 1;
        end
        20: begin
          if (bank_in != 1 || got_x != 1 || got_y != 2 ||
              got_pose != 0 || !mapped_valid[bank_in] ||
              !pose_found[bank_in] || !in_range[bank_in] ||
              got_wx != 1 || got_wy != 2)
            fail("newer/equal identity world metadata mismatch");
          if (got_pol == 0)
            time20_pol0_count = time20_pol0_count + 1;
          else
            time20_pol1_count = time20_pol1_count + 1;
        end
        19: begin
          if (bank_in != 1 || got_x != 1 || got_y != 2 || got_pol != 0 ||
              got_pose != 0 || !mapped_valid[bank_in] ||
              !pose_found[bank_in] || !in_range[bank_in] ||
              got_wx != 1 || got_wy != 2)
            fail("stale identity world metadata mismatch");
        end
        30: begin
          if (bank_in != 2 || got_x != 2 || got_y != 1 || got_pol != 1 ||
              got_pose != 1 || mapped_valid[bank_in] ||
              pose_found[bank_in] || in_range[bank_in] ||
              got_wx != 0 || got_wy != 0)
            fail("unknown-pose world metadata mismatch");
        end
        default: fail("unexpected world event timestamp");
      endcase
    end
  endtask

  task automatic check_write;
    input integer bank_in;
    input integer ordinal_in;
    input [ADDR_W-1:0] address_in;
    input [TIMESTAMP_W-1:0] timestamp_in;
    input [1:0] polarity_seen_in;
    begin
      if (address_in != TARGET_ADDR)
        fail("write used the wrong bank-local address");
      if (!mem_wr_req_cell_valid[bank_in])
        fail("write cleared cell_valid");
      case (bank_in)
        0: if (ordinal_in != 0 || timestamp_in != 10 ||
               polarity_seen_in != 2'b01)
             fail("bank 0 write payload mismatch");
        1: begin
          case (ordinal_in)
            0: if (timestamp_in != 10 || polarity_seen_in != 2'b10)
                 fail("bank 1 initial write payload mismatch");
            1: if (timestamp_in != 20 || polarity_seen_in != 2'b01)
                 fail("bank 1 newer write payload mismatch");
            2: if (timestamp_in != 20 || polarity_seen_in != 2'b11)
                 fail("bank 1 equal-time write payload mismatch");
            default: fail("bank 1 issued an extra write");
          endcase
        end
        2: if (ordinal_in != 0 || timestamp_in != 10 ||
               polarity_seen_in != 2'b01)
             fail("bank 2 write payload mismatch");
        3: if (ordinal_in != 0 || timestamp_in != 10 ||
               polarity_seen_in != 2'b10)
             fail("bank 3 write payload mismatch");
      endcase
    end
  endtask

  task automatic expect_cell;
    input integer bank_in;
    input integer address_in;
    input integer timestamp_in;
    input integer polarity_seen_in;
    integer index;
    begin
      index = bank_in*BANK_CELLS + address_in;
      if (!memory_valid[index] ||
          memory_timestamp[index] !== timestamp_in[TIMESTAMP_W-1:0] ||
          memory_polarity[index] !== polarity_seen_in[1:0]) begin
        $display("FAIL cell bank=%0d addr=%0d valid=%0b time=%0d pol=%0b expected_time=%0d expected_pol=%0b",
                 bank_in, address_in, memory_valid[index],
                 memory_timestamp[index], memory_polarity[index],
                 timestamp_in, polarity_seen_in[1:0]);
        error_count = error_count + 1;
      end
    end
  endtask

  always @(posedge clk) begin
    if (rst) begin
      response_pending <= 4'b0000;
      for (memory_bank = 0; memory_bank < 4;
           memory_bank = memory_bank + 1)
        response_addr[memory_bank] <= 0;
    end else begin
      for (memory_bank = 0; memory_bank < 4;
           memory_bank = memory_bank + 1) begin
        if (response_pending[memory_bank] &&
            mem_rd_rsp_ready[memory_bank])
          response_pending[memory_bank] <= 1'b0;
        if (mem_rd_req_valid[memory_bank] &&
            mem_rd_req_ready[memory_bank]) begin
          if (response_pending[memory_bank])
            fail("SRAM bank accepted a second outstanding read");
          response_pending[memory_bank] <= 1'b1;
          response_addr[memory_bank] <=
            mem_rd_req_addr_flat[memory_bank*ADDR_W +: ADDR_W];
        end
        if (mem_wr_req_valid[memory_bank] &&
            mem_wr_req_ready[memory_bank]) begin
          memory_valid[memory_bank*BANK_CELLS +
                       mem_wr_req_addr_flat[
                         memory_bank*ADDR_W +: ADDR_W]] <=
            mem_wr_req_cell_valid[memory_bank];
          memory_timestamp[memory_bank*BANK_CELLS +
                           mem_wr_req_addr_flat[
                             memory_bank*ADDR_W +: ADDR_W]] <=
            mem_wr_req_timestamp_flat[
              memory_bank*TIMESTAMP_W +: TIMESTAMP_W];
          memory_polarity[memory_bank*BANK_CELLS +
                          mem_wr_req_addr_flat[
                            memory_bank*ADDR_W +: ADDR_W]] <=
            mem_wr_req_polarity_seen_flat[memory_bank*2 +: 2];
        end
      end
    end
  end

  always @(posedge clk) begin
    if (!rst) begin
      cycle_count = cycle_count + 1;
      if (|aer_overrun)
        overrun_seen = 1'b1;
      if (|fifo_overflow)
        fifo_overflow_seen = 1'b1;
      if (pose_accounting_error)
        fail("pose accounting_error asserted");
      for (source_i = 0; source_i < 16; source_i = source_i + 1)
        if (arrival[source_i])
          input_count = input_count + 1;

      if ((world_valid & world_ready) == 4'b1111)
        saw_four_world = 1'b1;
      if ((mem_rd_req_valid & mem_rd_req_ready) == 4'b1111)
        saw_four_reads = 1'b1;
      if ((mem_wr_req_valid & mem_wr_req_ready) == 4'b1111)
        saw_four_writes = 1'b1;

      for (monitor_bank = 0; monitor_bank < 4;
           monitor_bank = monitor_bank + 1) begin
        if (world_valid[monitor_bank] && world_ready[monitor_bank]) begin
          check_world(monitor_bank);
          world_count = world_count + 1;
          if (!mapped_valid[monitor_bank])
            invalid_world_count = invalid_world_count + 1;
        end
        if (mem_rd_req_valid[monitor_bank] &&
            mem_rd_req_ready[monitor_bank]) begin
          if (mem_rd_req_addr_flat[monitor_bank*ADDR_W +: ADDR_W] !=
              TARGET_ADDR)
            fail("read used the wrong bank-local address");
          read_count[monitor_bank] = read_count[monitor_bank] + 1;
        end
        if (mem_wr_req_valid[monitor_bank] &&
            mem_wr_req_ready[monitor_bank]) begin
          check_write(
            monitor_bank, write_count[monitor_bank],
            mem_wr_req_addr_flat[monitor_bank*ADDR_W +: ADDR_W],
            mem_wr_req_timestamp_flat[
              monitor_bank*TIMESTAMP_W +: TIMESTAMP_W],
            mem_wr_req_polarity_seen_flat[monitor_bank*2 +: 2]);
          write_count[monitor_bank] = write_count[monitor_bank] + 1;
        end
        if (surface_update_applied[monitor_bank])
          update_count[monitor_bank] = update_count[monitor_bank] + 1;
        if (surface_equal_time_merged[monitor_bank])
          equal_count[monitor_bank] = equal_count[monitor_bank] + 1;
        if (surface_stale_ignored[monitor_bank])
          stale_count[monitor_bank] = stale_count[monitor_bank] + 1;
        if (surface_range_error[monitor_bank])
          fail("in-range identity traffic raised surface_range_error");
        if (surface_equal_time_merged[monitor_bank] &&
            !surface_update_applied[monitor_bank])
          fail("equal-time pulse lacked update pulse");
        if ((surface_update_applied[monitor_bank] &&
             surface_stale_ignored[monitor_bank]) ||
            (surface_update_applied[monitor_bank] &&
             surface_range_error[monitor_bank]) ||
            (surface_stale_ignored[monitor_bank] &&
             surface_range_error[monitor_bank]))
          fail("surface terminal status pulses overlapped");
      end
    end
  end

  task automatic program_identity_pose;
    begin
      @(negedge clk);
      pose_wr_id = 0;
      pose_wr_m00 = Q;
      pose_wr_m01 = 0;
      pose_wr_m10 = 0;
      pose_wr_m11 = Q;
      pose_wr_tx = 0;
      pose_wr_ty = 0;
      pose_wr_req = 1'b1;
      #1;
      if (!pose_wr_ready || !pose_wr_commit || pose_wr_rejected)
        fail("identity pose write did not commit");
      @(posedge clk);
      @(negedge clk);
      pose_wr_req = 1'b0;
      #1;
      if (!dut.u_tx.u_pose_history.valid_mem[0])
        fail("identity pose was not stored");
    end
  endtask

  task automatic send_events;
    input [15:0] arrival_in;
    input [15:0] polarity_in_value;
    input integer pose_in;
    input integer timestamp_in;
    begin
      @(negedge clk);
      arrival = arrival_in;
      polarity_in = polarity_in_value & arrival_in;
      occurrence_pose_version = pose_in[POSE_W-1:0];
      occurrence_timestamp = timestamp_in[TIMESTAMP_W-1:0];
      #1;
      if (|(aer_overrun & arrival_in))
        fail("directed input overran the source AER FIFO");
      @(posedge clk);
      @(negedge clk);
      arrival = 0;
      polarity_in = 0;
    end
  endtask

  task automatic wait_for_totals;
    input integer expected_world;
    input integer expected_updates;
    input integer expected_stale;
    input integer expected_invalid;
    integer wait_cycles;
    integer quiet_cycles;
    begin
      wait_cycles = 0;
      while ((world_count < expected_world ||
              total_updates() < expected_updates ||
              total_stale() < expected_stale ||
              invalid_world_count < expected_invalid) &&
             wait_cycles < 300) begin
        @(negedge clk);
        wait_cycles = wait_cycles + 1;
      end
      if (wait_cycles >= 300)
        $fatal(1, "directed transaction did not reach expected totals");

      quiet_cycles = 0;
      while (quiet_cycles < 2 && wait_cycles < 400) begin
        @(negedge clk);
        if (!(|world_valid) && !(|mem_rd_req_valid) &&
            !(|mem_rd_rsp_valid) && !(|mem_wr_req_valid) &&
            !(|response_pending) && !(|dut.u_tx.fifo_occupancy_flat))
          quiet_cycles = quiet_cycles + 1;
        else
          quiet_cycles = 0;
        wait_cycles = wait_cycles + 1;
      end
      if (quiet_cycles < 2)
        $fatal(1, "AER-to-SRAM pipeline did not drain");
    end
  endtask

  integer reads_before_unknown;
  integer writes_before_unknown;

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
    mem_rd_req_ready = 4'b1111;
    mem_wr_req_ready = 4'b1111;
    response_pending = 0;
    world_count = 0;
    invalid_world_count = 0;
    input_count = 0;
    error_count = 0;
    cycle_count = 0;
    initial_world_count = 0;
    time20_pol0_count = 0;
    time20_pol1_count = 0;
    initial_seen = 0;
    saw_four_world = 0;
    saw_four_reads = 0;
    saw_four_writes = 0;
    overrun_seen = 0;
    fifo_overflow_seen = 0;
    for (bank_i = 0; bank_i < 4; bank_i = bank_i + 1) begin
      response_addr[bank_i] = 0;
      read_count[bank_i] = 0;
      write_count[bank_i] = 0;
      update_count[bank_i] = 0;
      equal_count[bank_i] = 0;
      stale_count[bank_i] = 0;
    end
    for (cell_i = 0; cell_i < 4*BANK_CELLS; cell_i = cell_i + 1) begin
      memory_valid[cell_i] = 1'b0;
      memory_timestamp[cell_i] = 0;
      memory_polarity[cell_i] = 0;
    end

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    program_identity_pose;

    // Row 2, columns 0..3: K=4 transform lanes feed four map banks together.
    send_events(16'h0f00, 16'h0a00, 0, 10);
    wait_for_totals(4, 4, 0, 0);
    for (bank_i = 0; bank_i < 4; bank_i = bank_i + 1)
      expect_cell(bank_i, TARGET_ADDR, 10,
                  (bank_i & 1) ? 2'b10 : 2'b01);
    if (!saw_four_world || !saw_four_reads || !saw_four_writes ||
        initial_seen != 4'b1111 || initial_world_count != 4)
      fail("four-bank concurrent update coverage was not reached");

    // The same world cell first receives a newer sample, then equal-time
    // opposite polarity, then an older sample that must be ignored.
    send_events(16'h0200, 16'h0000, 0, 20);
    wait_for_totals(5, 5, 0, 0);
    expect_cell(1, TARGET_ADDR, 20, 2'b01);

    send_events(16'h0200, 16'h0200, 0, 20);
    wait_for_totals(6, 6, 0, 0);
    expect_cell(1, TARGET_ADDR, 20, 2'b11);
    if (total_equal() != 1)
      fail("equal-time update did not raise exactly one merge pulse");

    send_events(16'h0200, 16'h0000, 0, 19);
    wait_for_totals(7, 6, 1, 0);
    expect_cell(1, TARGET_ADDR, 20, 2'b11);
    if (total_writes() != 6)
      fail("stale event incorrectly issued an SRAM write");

    // Pose 1 was never programmed. The event must still retire on the world
    // interface, with deterministic invalid metadata and no memory request.
    reads_before_unknown = total_reads();
    writes_before_unknown = total_writes();
    send_events(16'h0040, 16'h0040, 1, 30);
    wait_for_totals(8, 6, 1, 1);
    if (total_reads() != reads_before_unknown ||
        total_writes() != writes_before_unknown)
      fail("unknown-pose event touched SRAM");
    if (memory_valid[2*BANK_CELLS + UNKNOWN_ADDR])
      fail("unknown-pose event modified its would-be world cell");

    if (input_count != 8 || world_count != 8 || invalid_world_count != 1)
      fail("end-to-end event accounting mismatch");
    if (overrun_seen || fifo_overflow_seen || pose_accounting_error)
      fail("loss/accounting error appeared in the directed test");
    if (time20_pol0_count != 1 || time20_pol1_count != 1)
      fail("newer/equal-time world events were not each observed once");
    if (total_reads() != 7 || total_writes() != 6 ||
        total_updates() != 6 || total_equal() != 1 ||
        total_stale() != 1)
      fail("final SRAM transaction/status totals mismatch");
    if (read_count[0] != 1 || read_count[1] != 4 ||
        read_count[2] != 1 || read_count[3] != 1 ||
        write_count[0] != 1 || write_count[1] != 3 ||
        write_count[2] != 1 || write_count[3] != 1)
      fail("per-bank SRAM transaction totals mismatch");
    if (|dut.u_tx.fifo_occupancy_flat || |world_valid)
      fail("transform pipeline remained occupied after drain");
    for (source_i = 0; source_i < 16; source_i = source_i + 1)
      if (dut.u_tx.u_aer.pending_cnt[source_i] != 0)
        fail("source-local AER FIFO did not drain");
    for (source_i = 0; source_i < (1 << POSE_W);
         source_i = source_i + 1)
      if (dut.u_tx.u_pose_guard.outstanding[source_i] != 0)
        fail("pose guard retained an outstanding event");

    $display("AER_K4_SRAM_SURFACE_COUNTS inputs=%0d world=%0d invalid=%0d reads=%0d writes=%0d updates=%0d equal=%0d stale=%0d cycles=%0d",
             input_count, world_count, invalid_world_count,
             total_reads(), total_writes(), total_updates(),
             total_equal(), total_stale(), cycle_count);
    if (error_count == 0) begin
      $display("AER_TX16_POSE_AFFINE2D_K4_SRAM_SURFACE_PASS");
      $finish;
    end else begin
      $fatal(1, "AER_TX16_POSE_AFFINE2D_K4_SRAM_SURFACE_FAIL errors=%0d",
             error_count);
    end
  end

  initial begin
    #20000;
    $fatal(1, "AER_TX16_POSE_AFFINE2D_K4_SRAM_SURFACE_TIMEOUT");
  end
endmodule
