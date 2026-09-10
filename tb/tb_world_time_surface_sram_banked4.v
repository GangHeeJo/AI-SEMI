`timescale 1ns/1ps

module tb_world_time_surface_sram_banked4;
  localparam integer GRID_W = 12;
  localparam integer GRID_H = 4;
  localparam integer BANK_GRID_W = GRID_W / 4;
  localparam integer BANK_CELLS = BANK_GRID_W * GRID_H;
  localparam integer COORD_W = 8;
  localparam integer TIMESTAMP_W = 8;
  localparam integer ADDR_W = $clog2(BANK_CELLS);

  reg clk = 1'b0;
  reg rst;
  reg [3:0] event_valid;
  wire [3:0] event_ready;
  reg [3:0] mapped_valid;
  reg [4*COORD_W-1:0] world_x_flat;
  reg [4*COORD_W-1:0] world_y_flat;
  reg [3:0] polarity;
  reg [4*TIMESTAMP_W-1:0] occurrence_timestamp_flat;

  wire [3:0] update_applied;
  wire [3:0] equal_time_merged;
  wire [3:0] stale_ignored;
  wire [3:0] range_error;
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

  world_time_surface_sram_banked4 #(
    .GRID_W(GRID_W), .GRID_H(GRID_H), .COORD_W(COORD_W),
    .TIMESTAMP_W(TIMESTAMP_W), .ADDR_W(ADDR_W)
  ) dut (
    .clk(clk), .rst(rst),
    .event_valid(event_valid), .event_ready(event_ready),
    .mapped_valid(mapped_valid), .world_x_flat(world_x_flat),
    .world_y_flat(world_y_flat), .polarity(polarity),
    .occurrence_timestamp_flat(occurrence_timestamp_flat),
    .update_applied(update_applied),
    .equal_time_merged(equal_time_merged),
    .stale_ignored(stale_ignored), .range_error(range_error),
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
  integer range_count [0:3];
  integer accepted_count;
  integer error_count;
  integer cycle_count;
  integer bank_i;
  integer cell_i;

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

  always @(posedge clk) begin
    if (rst) begin
      response_pending <= 4'b0000;
      for (bank_i = 0; bank_i < 4; bank_i = bank_i + 1)
        response_addr[bank_i] <= 0;
    end else begin
      for (bank_i = 0; bank_i < 4; bank_i = bank_i + 1) begin
        if (response_pending[bank_i] && mem_rd_rsp_ready[bank_i])
          response_pending[bank_i] <= 1'b0;

        if (mem_rd_req_valid[bank_i] && mem_rd_req_ready[bank_i]) begin
          if (response_pending[bank_i])
            $fatal(1, "bank %0d accepted a second outstanding read", bank_i);
          if (mem_rd_req_addr_flat[bank_i*ADDR_W +: ADDR_W] >= BANK_CELLS)
            $fatal(1, "bank %0d read address out of range", bank_i);
          response_pending[bank_i] <= 1'b1;
          response_addr[bank_i] <=
            mem_rd_req_addr_flat[bank_i*ADDR_W +: ADDR_W];
          read_count[bank_i] = read_count[bank_i] + 1;
        end

        if (mem_wr_req_valid[bank_i] && mem_wr_req_ready[bank_i]) begin
          if (mem_wr_req_addr_flat[bank_i*ADDR_W +: ADDR_W] >= BANK_CELLS)
            $fatal(1, "bank %0d write address out of range", bank_i);
          memory_valid[bank_i*BANK_CELLS +
                       mem_wr_req_addr_flat[bank_i*ADDR_W +: ADDR_W]] <=
            mem_wr_req_cell_valid[bank_i];
          memory_timestamp[bank_i*BANK_CELLS +
                           mem_wr_req_addr_flat[bank_i*ADDR_W +: ADDR_W]] <=
            mem_wr_req_timestamp_flat[
              bank_i*TIMESTAMP_W +: TIMESTAMP_W];
          memory_polarity[bank_i*BANK_CELLS +
                          mem_wr_req_addr_flat[bank_i*ADDR_W +: ADDR_W]] <=
            mem_wr_req_polarity_seen_flat[bank_i*2 +: 2];
          write_count[bank_i] = write_count[bank_i] + 1;
        end
      end
    end
  end

  always @(negedge clk) begin
    if (!rst) begin
      cycle_count = cycle_count + 1;
      for (bank_i = 0; bank_i < 4; bank_i = bank_i + 1) begin
        if (update_applied[bank_i])
          update_count[bank_i] = update_count[bank_i] + 1;
        if (equal_time_merged[bank_i])
          equal_count[bank_i] = equal_count[bank_i] + 1;
        if (stale_ignored[bank_i])
          stale_count[bank_i] = stale_count[bank_i] + 1;
        if (range_error[bank_i])
          range_count[bank_i] = range_count[bank_i] + 1;
        if (equal_time_merged[bank_i] && !update_applied[bank_i]) begin
          $display("FAIL: bank %0d equal pulse without update", bank_i);
          error_count = error_count + 1;
        end
        if ((update_applied[bank_i] && stale_ignored[bank_i]) ||
            (update_applied[bank_i] && range_error[bank_i]) ||
            (stale_ignored[bank_i] && range_error[bank_i])) begin
          $display("FAIL: bank %0d conflicting status pulses", bank_i);
          error_count = error_count + 1;
        end
      end
    end
  end

  function automatic integer popcount4;
    input [3:0] value;
    integer bit_i;
    begin
      popcount4 = 0;
      for (bit_i = 0; bit_i < 4; bit_i = bit_i + 1)
        popcount4 = popcount4 + value[bit_i];
    end
  endfunction

  task automatic fail;
    input [1023:0] message;
    begin
      error_count = error_count + 1;
      $display("FAIL: %0s", message);
    end
  endtask

  task automatic set_event;
    input integer lane_in;
    input integer mapped_in;
    input integer x_in;
    input integer y_in;
    input integer polarity_in;
    input integer timestamp_in;
    begin
      mapped_valid[lane_in] = mapped_in[0];
      world_x_flat[lane_in*COORD_W +: COORD_W] = x_in;
      world_y_flat[lane_in*COORD_W +: COORD_W] = y_in;
      polarity[lane_in] = polarity_in[0];
      occurrence_timestamp_flat[
        lane_in*TIMESTAMP_W +: TIMESTAMP_W] = timestamp_in;
    end
  endtask

  // Producers hold every lane until its individual ready handshake.
  task automatic send_pending;
    input [3:0] pending_mask;
    reg [3:0] fire;
    integer wait_cycles;
    begin
      @(negedge clk);
      event_valid = pending_mask;
      wait_cycles = 0;
      #1;
      while (|event_valid) begin
        fire = event_valid & event_ready;
        @(posedge clk);
        @(negedge clk);
        event_valid = event_valid & ~fire;
        accepted_count = accepted_count + popcount4(fire);
        wait_cycles = wait_cycles + 1;
        if (wait_cycles > 200)
          $fatal(1, "input batch did not make progress");
        #1;
      end
    end
  endtask

  task automatic wait_for_quiet;
    integer quiet_cycles;
    integer wait_cycles;
    begin
      quiet_cycles = 0;
      wait_cycles = 0;
      while (quiet_cycles < 2 && wait_cycles < 300) begin
        @(negedge clk);
        if (!(|event_valid) && !(|mem_rd_req_valid) &&
            !(|mem_rd_rsp_valid) && !(|mem_wr_req_valid))
          quiet_cycles = quiet_cycles + 1;
        else
          quiet_cycles = 0;
        wait_cycles = wait_cycles + 1;
      end
      if (quiet_cycles < 2)
        $fatal(1, "banked surface did not drain");
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
        $display("FAIL: cell bank=%0d addr=%0d got valid=%0b time=%0d pol=%0b expected time=%0d pol=%0b",
                 bank_in, address_in, memory_valid[index],
                 memory_timestamp[index], memory_polarity[index],
                 timestamp_in, polarity_seen_in[1:0]);
        error_count = error_count + 1;
      end
    end
  endtask

  integer reads_before;
  integer writes_before;
  integer ranges_before;
  integer total_reads;
  integer total_writes;
  integer total_updates;
  integer total_equal;
  integer total_stale;
  integer total_range;

  initial begin
    rst = 1'b1;
    event_valid = 4'b0000;
    mapped_valid = 4'b0000;
    world_x_flat = 0;
    world_y_flat = 0;
    polarity = 0;
    occurrence_timestamp_flat = 0;
    mem_rd_req_ready = 4'b1111;
    mem_wr_req_ready = 4'b1111;
    response_pending = 4'b0000;
    accepted_count = 0;
    error_count = 0;
    cycle_count = 0;
    for (bank_i = 0; bank_i < 4; bank_i = bank_i + 1) begin
      response_addr[bank_i] = 0;
      read_count[bank_i] = 0;
      write_count[bank_i] = 0;
      update_count[bank_i] = 0;
      equal_count[bank_i] = 0;
      stale_count[bank_i] = 0;
      range_count[bank_i] = 0;
    end
    for (cell_i = 0; cell_i < 4*BANK_CELLS; cell_i = cell_i + 1) begin
      memory_valid[cell_i] = 1'b0;
      memory_timestamp[cell_i] = 0;
      memory_polarity[cell_i] = 0;
    end

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    #1;
    if (event_ready !== 4'b1111)
      fail("unmapped idle inputs were not ready after reset");

    // Four distinct banks must accept and update concurrently.  Expected
    // address is y*(GRID_W/4) + floor(x/4), inside the selected x-mod-4 bank.
    set_event(0, 1, 0, 1, 0, 10);   // bank 0, local address 3
    set_event(1, 1, 5, 2, 1, 20);   // bank 1, local address 7
    set_event(2, 1, 10, 3, 0, 30);  // bank 2, local address 11
    set_event(3, 1, 7, 0, 1, 40);   // bank 3, local address 1
    send_pending(4'b1111);
    wait_for_quiet;
    expect_cell(0, 3, 10, 2'b01);
    expect_cell(1, 7, 20, 2'b10);
    expect_cell(2, 11, 30, 2'b01);
    expect_cell(3, 1, 40, 2'b10);

    // A stopped read port and a stopped write port must not block bank 1.
    mem_rd_req_ready = 4'b1110;
    mem_wr_req_ready = 4'b0111;
    set_event(0, 1, 4, 0, 1, 50);  // bank 0 stalls at read request
    set_event(1, 1, 1, 3, 0, 51);  // bank 1 completes independently
    set_event(3, 1, 3, 2, 1, 52);  // bank 3 stalls at write request
    send_pending(4'b1011);
    repeat (8) @(negedge clk);
    if (!mem_rd_req_valid[0])
      fail("bank 0 read request was not held while stalled");
    if (!mem_wr_req_valid[3])
      fail("bank 3 write request was not held while stalled");
    expect_cell(1, 9, 51, 2'b01);
    if (memory_valid[0*BANK_CELLS + 1] ||
        memory_valid[3*BANK_CELLS + 6])
      fail("a stalled bank updated memory before its handshake");

    // mapped_valid=0 is consumed directly even while other banks are blocked.
    reads_before = read_count[0] + read_count[1] +
                   read_count[2] + read_count[3];
    writes_before = write_count[0] + write_count[1] +
                    write_count[2] + write_count[3];
    ranges_before = range_count[0] + range_count[1] +
                    range_count[2] + range_count[3];
    set_event(2, 0, -7, GRID_H + 2, 1, 77);
    send_pending(4'b0100);
    repeat (2) @(negedge clk);
    if (read_count[0] + read_count[1] + read_count[2] + read_count[3]
        != reads_before ||
        write_count[0] + write_count[1] + write_count[2] + write_count[3]
        != writes_before ||
        range_count[0] + range_count[1] + range_count[2] + range_count[3]
        != ranges_before)
      fail("unmapped event touched memory or raised a range error");

    mem_rd_req_ready = 4'b1111;
    mem_wr_req_ready = 4'b1111;
    wait_for_quiet;
    expect_cell(0, 1, 50, 2'b10);
    expect_cell(3, 6, 52, 2'b10);

    // All four lanes targeting one bank are serialized fairly without loss.
    set_event(0, 1, 2, 0, 0, 60);
    set_event(1, 1, 6, 0, 1, 61);
    set_event(2, 1, 10, 0, 0, 62);
    set_event(3, 1, 2, 1, 1, 63);
    send_pending(4'b1111);
    wait_for_quiet;
    expect_cell(2, 0, 60, 2'b01);
    expect_cell(2, 1, 61, 2'b10);
    expect_cell(2, 2, 62, 2'b01);
    expect_cell(2, 3, 63, 2'b10);

    // Existing writer semantics survive banking: newer writes, equal time ORs
    // polarity, and stale time leaves the cell unchanged.
    set_event(3, 1, 9, 1, 0, 100);
    send_pending(4'b1000);
    wait_for_quiet;
    set_event(0, 1, 9, 1, 1, 100);
    send_pending(4'b0001);
    wait_for_quiet;
    set_event(2, 1, 9, 1, 0, 99);
    send_pending(4'b0100);
    wait_for_quiet;
    expect_cell(1, 5, 100, 2'b11);

    // A mapped out-of-range event is consumed by bank 0 with no SRAM access.
    reads_before = read_count[0] + read_count[1] +
                   read_count[2] + read_count[3];
    writes_before = write_count[0] + write_count[1] +
                    write_count[2] + write_count[3];
    set_event(2, 1, GRID_W, 0, 0, 70);
    send_pending(4'b0100);
    wait_for_quiet;
    if (read_count[0] + read_count[1] + read_count[2] + read_count[3]
        != reads_before ||
        write_count[0] + write_count[1] + write_count[2] + write_count[3]
        != writes_before)
      fail("mapped range failure touched SRAM");

    total_reads = 0;
    total_writes = 0;
    total_updates = 0;
    total_equal = 0;
    total_stale = 0;
    total_range = 0;
    for (bank_i = 0; bank_i < 4; bank_i = bank_i + 1) begin
      total_reads = total_reads + read_count[bank_i];
      total_writes = total_writes + write_count[bank_i];
      total_updates = total_updates + update_count[bank_i];
      total_equal = total_equal + equal_count[bank_i];
      total_stale = total_stale + stale_count[bank_i];
      total_range = total_range + range_count[bank_i];
    end
    if (accepted_count != 16)
      fail("accepted input count mismatch");
    if (total_reads != 14 || total_writes != 13 ||
        total_updates != 13 || total_equal != 1 ||
        total_stale != 1 || total_range != 1)
      fail("final transaction/status counts mismatch");
    if (update_count[0] != 2 || update_count[1] != 4 ||
        update_count[2] != 5 || update_count[3] != 2)
      fail("per-bank update distribution mismatch");

    $display("WORLD_TIME_SURFACE_SRAM_BANKED4_COUNTS accepted=%0d reads=%0d writes=%0d updates=%0d equal=%0d stale=%0d range=%0d cycles=%0d",
             accepted_count, total_reads, total_writes, total_updates,
             total_equal, total_stale, total_range, cycle_count);
    if (error_count == 0) begin
      $display("WORLD_TIME_SURFACE_SRAM_BANKED4_PASS");
      $finish;
    end else begin
      $fatal(1, "WORLD_TIME_SURFACE_SRAM_BANKED4_FAIL errors=%0d",
             error_count);
    end
  end

  initial begin
    #20000;
    $fatal(1, "WORLD_TIME_SURFACE_SRAM_BANKED4_TIMEOUT");
  end
endmodule
