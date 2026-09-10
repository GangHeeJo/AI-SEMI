`timescale 1ns/1ps

module tb_world_time_surface;
  localparam GRID_W = 7;
  localparam GRID_H = 6;
  localparam COORD_W = 16;
  localparam TIMESTAMP_W = 16;

  reg clk = 1'b0;
  reg rst;
  reg event_valid;
  reg mapped_valid;
  reg signed [COORD_W-1:0] world_x, world_y;
  reg polarity;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp;
  reg [$clog2(GRID_W)-1:0] read_x;
  reg [$clog2(GRID_H)-1:0] read_y;

  wire event_ready;
  wire update_applied, equal_time_merged, stale_ignored, range_error;
  wire read_valid;
  wire [TIMESTAMP_W-1:0] read_timestamp;
  wire [1:0] read_polarity_seen;
  integer errors;

  world_time_surface #(
    .GRID_W(GRID_W), .GRID_H(GRID_H), .COORD_W(COORD_W),
    .TIMESTAMP_W(TIMESTAMP_W)
  ) dut (
    .clk(clk), .rst(rst), .event_valid(event_valid), .event_ready(event_ready),
    .mapped_valid(mapped_valid), .world_x(world_x), .world_y(world_y),
    .polarity(polarity), .occurrence_timestamp(occurrence_timestamp),
    .update_applied(update_applied), .equal_time_merged(equal_time_merged),
    .stale_ignored(stale_ignored), .range_error(range_error),
    .read_x(read_x), .read_y(read_y), .read_valid(read_valid),
    .read_timestamp(read_timestamp), .read_polarity_seen(read_polarity_seen)
  );

  always #5 clk = ~clk;

  task send_event;
    input integer x;
    input integer y;
    input integer time_value;
    input integer pol_value;
    input integer map_value;
    begin
      @(negedge clk);
      event_valid = 1'b1;
      mapped_valid = map_value[0];
      world_x = x;
      world_y = y;
      occurrence_timestamp = time_value[TIMESTAMP_W-1:0];
      polarity = pol_value[0];
      @(posedge clk); #1;
      event_valid = 1'b0;
    end
  endtask

  task check_read;
    input integer x;
    input integer y;
    input integer want_valid;
    input integer want_time;
    input [1:0] want_polarity;
    begin
      read_x = x[$clog2(GRID_W)-1:0];
      read_y = y[$clog2(GRID_H)-1:0];
      #1;
      if (read_valid !== want_valid[0] ||
          read_timestamp !== want_time[TIMESTAMP_W-1:0] ||
          read_polarity_seen !== want_polarity) begin
        errors = errors + 1;
        $display("READ_MISMATCH xy=(%0d,%0d) got=%b/%0d/%b want=%0d/%0d/%b",
          x, y, read_valid, read_timestamp, read_polarity_seen,
          want_valid, want_time, want_polarity);
      end
    end
  endtask

  initial begin
    errors = 0;
    rst = 1'b1;
    event_valid = 1'b0;
    mapped_valid = 1'b0;
    world_x = 0;
    world_y = 0;
    polarity = 1'b0;
    occurrence_timestamp = 0;
    read_x = 0;
    read_y = 0;

    repeat (2) @(posedge clk);
    #1;
    if (event_ready !== 1'b0 || read_valid !== 1'b0) begin
      errors = errors + 1;
      $display("RESET_STATE_FAIL");
    end
    @(negedge clk);
    rst = 1'b0;
    #1;
    if (event_ready !== 1'b1) begin
      errors = errors + 1;
      $display("READY_LOW_AFTER_RESET");
    end

    // Status-invalid events are consumed but do not touch memory.
    send_event(2, 3, 50, 1, 0);
    if (update_applied || stale_ignored || range_error) begin
      errors = errors + 1;
      $display("INVALID_EVENT_STATUS_FAIL");
    end
    check_read(2, 3, 0, 0, 2'b00);

    // A claimed mapped event outside this memory's configured grid is explicit.
    send_event(-1, 3, 60, 0, 1);
    if (!range_error || update_applied || stale_ignored) begin
      errors = errors + 1;
      $display("RANGE_STATUS_FAIL");
    end

    send_event(2, 3, 100, 0, 1);
    if (!update_applied || equal_time_merged || stale_ignored || range_error)
      errors = errors + 1;
    check_read(2, 3, 1, 100, 2'b01);

    // Equal timestamp merges ON/OFF without depending on retirement order.
    send_event(2, 3, 100, 1, 1);
    if (!update_applied || !equal_time_merged || stale_ignored || range_error)
      errors = errors + 1;
    check_read(2, 3, 1, 100, 2'b11);

    // An older occurrence arriving later cannot roll the cell back.
    send_event(2, 3, 90, 1, 1);
    if (update_applied || equal_time_merged || !stale_ignored || range_error)
      errors = errors + 1;
    check_read(2, 3, 1, 100, 2'b11);

    // A newer occurrence replaces both timestamp and polarity set.
    send_event(2, 3, 110, 1, 1);
    if (!update_applied || equal_time_merged || stale_ignored || range_error)
      errors = errors + 1;
    check_read(2, 3, 1, 110, 2'b10);

    // Other cells remain independent.
    send_event(6, 5, 77, 0, 1);
    check_read(6, 5, 1, 77, 2'b01);
    check_read(2, 3, 1, 110, 2'b10);

    // Counter wrap preserves occurrence order within the half-range window.
    send_event(5, 4, 16'hfffe, 0, 1);
    send_event(5, 4, 16'h0002, 1, 1);
    if (!update_applied || equal_time_merged || stale_ignored || range_error)
      errors = errors + 1;
    check_read(5, 4, 1, 16'h0002, 2'b10);
    send_event(5, 4, 16'hfffd, 0, 1);
    if (update_applied || equal_time_merged || !stale_ignored || range_error)
      errors = errors + 1;
    check_read(5, 4, 1, 16'h0002, 2'b10);

    // Exactly half the counter range has no unique modular ordering.
    send_event(5, 4, 16'h8002, 0, 1);
    if (update_applied || equal_time_merged || !stale_ignored || range_error)
      errors = errors + 1;
    check_read(5, 4, 1, 16'h0002, 2'b10);

    check_read(0, 0, 0, 0, 2'b00);
    check_read(7, 7, 0, 0, 2'b00);

    @(negedge clk);
    rst = 1'b1;
    @(posedge clk); #1;
    check_read(2, 3, 0, 0, 2'b00);
    check_read(6, 5, 0, 0, 2'b00);

    $display("WORLD_TIME_SURFACE_ERRORS=%0d", errors);
    if (errors == 0)
      $display("WORLD_TIME_SURFACE_PASS");
    else
      $fatal(1, "WORLD_TIME_SURFACE_FAIL");
    $finish;
  end
endmodule
