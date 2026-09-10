`timescale 1ns/1ps
module tb_world_time_surface_random;
  localparam GRID_W = 7;
  localparam GRID_H = 6;
  localparam COORD_W = 8;
  localparam TIMESTAMP_W = 12;
  localparam CELLS = GRID_W * GRID_H;
  localparam RANDOM_CYCLES = 10000;

  reg clk = 0;
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
  reg [$clog2(GRID_W)-1:0] read_x;
  reg [$clog2(GRID_H)-1:0] read_y;
  wire read_valid;
  wire [TIMESTAMP_W-1:0] read_timestamp;
  wire [1:0] read_polarity_seen;

  reg model_valid [0:CELLS-1];
  reg [TIMESTAMP_W-1:0] model_timestamp [0:CELLS-1];
  reg [1:0] model_polarity [0:CELLS-1];

  integer errors;
  integer status_errors;
  integer read_errors;
  integer invalid_read_errors;
  integer ready_errors;
  integer update_count;
  integer equal_count;
  integer stale_count;
  integer range_count;
  integer mapped_invalid_count;
  integer polarity0_count;
  integer polarity1_count;
  integer valid_read_count;
  integer invalid_read_count;
  integer reset_count;
  integer rng_seed;
  integer cycle;
  integer i;
  integer x_choice;
  integer y_choice;
  integer address;
  integer draw;

  world_time_surface #(
    .GRID_W(GRID_W), .GRID_H(GRID_H),
    .COORD_W(COORD_W), .TIMESTAMP_W(TIMESTAMP_W)
  ) dut (
    .clk(clk), .rst(rst),
    .event_valid(event_valid), .event_ready(event_ready),
    .mapped_valid(mapped_valid), .world_x(world_x), .world_y(world_y),
    .polarity(polarity), .occurrence_timestamp(occurrence_timestamp),
    .update_applied(update_applied),
    .equal_time_merged(equal_time_merged),
    .stale_ignored(stale_ignored), .range_error(range_error),
    .read_x(read_x), .read_y(read_y), .read_valid(read_valid),
    .read_timestamp(read_timestamp),
    .read_polarity_seen(read_polarity_seen)
  );

  always #5 clk = ~clk;

  task automatic clear_model;
    begin
      for (i = 0; i < CELLS; i = i + 1) begin
        model_valid[i] = 1'b0;
        model_timestamp[i] = 0;
        model_polarity[i] = 0;
      end
    end
  endtask

  task automatic check_readback;
    integer read_address;
    reg want_valid;
    reg [TIMESTAMP_W-1:0] want_timestamp;
    reg [1:0] want_polarity;
    begin
      if (read_x < GRID_W && read_y < GRID_H) begin
        read_address = read_y * GRID_W + read_x;
        want_valid = model_valid[read_address];
        want_timestamp = want_valid ? model_timestamp[read_address] : 0;
        want_polarity = want_valid ? model_polarity[read_address] : 0;
        valid_read_count = valid_read_count + 1;
      end else begin
        want_valid = 1'b0;
        want_timestamp = 0;
        want_polarity = 0;
        invalid_read_count = invalid_read_count + 1;
      end
      if (read_valid !== want_valid ||
          read_timestamp !== want_timestamp ||
          read_polarity_seen !== want_polarity) begin
        errors = errors + 1;
        read_errors = read_errors + 1;
        if (!(read_x < GRID_W && read_y < GRID_H))
          invalid_read_errors = invalid_read_errors + 1;
        if (read_errors <= 20)
          $display("READ_MISMATCH x=%0d y=%0d got=(%b,%0d,%b) expected=(%b,%0d,%b)",
                   read_x, read_y,
                   read_valid, read_timestamp, read_polarity_seen,
                   want_valid, want_timestamp, want_polarity);
      end
    end
  endtask

  task automatic apply_reset_and_check;
    integer reset_address;
    begin
      rst = 1'b1;
      event_valid = 1'b1;
      mapped_valid = 1'b1;
      world_x = 0;
      world_y = 0;
      polarity = 1'b1;
      occurrence_timestamp = 12'hfff;
      #1;
      if (event_ready !== 1'b0) begin
        errors = errors + 1;
        ready_errors = ready_errors + 1;
        $display("RESET_READY_MISMATCH got=%b", event_ready);
      end
      @(posedge clk);
      #1;
      clear_model;
      reset_count = reset_count + 1;
      if (update_applied !== 1'b0 || equal_time_merged !== 1'b0 ||
          stale_ignored !== 1'b0 || range_error !== 1'b0) begin
        errors = errors + 1;
        status_errors = status_errors + 1;
        $display("RESET_STATUS_MISMATCH update=%b equal=%b stale=%b range=%b",
                 update_applied, equal_time_merged,
                 stale_ignored, range_error);
      end
      for (reset_address = 0;
           reset_address < CELLS;
           reset_address = reset_address + 1) begin
        read_x = reset_address % GRID_W;
        read_y = reset_address / GRID_W;
        #1;
        check_readback;
      end
      rst = 1'b0;
      event_valid = 1'b0;
      mapped_valid = 1'b0;
      #1;
      if (event_ready !== 1'b1) begin
        errors = errors + 1;
        ready_errors = ready_errors + 1;
        $display("POST_RESET_READY_MISMATCH got=%b", event_ready);
      end
    end
  endtask

  task automatic step_event;
    integer event_address;
    reg [$clog2(GRID_W)-1:0] saved_read_x;
    reg [$clog2(GRID_H)-1:0] saved_read_y;
    reg expected_update;
    reg expected_equal;
    reg expected_stale;
    reg expected_range;
    reg apply_update;
    reg [TIMESTAMP_W-1:0] next_timestamp;
    reg [1:0] next_polarity;
    reg [1:0] incoming_polarity;
    begin
      #1;
      if (event_ready !== 1'b1) begin
        errors = errors + 1;
        ready_errors = ready_errors + 1;
        if (ready_errors <= 20)
          $display("EVENT_READY_MISMATCH cycle=%0d got=%b", cycle, event_ready);
      end
      check_readback;

      expected_update = 1'b0;
      expected_equal = 1'b0;
      expected_stale = 1'b0;
      expected_range = 1'b0;
      apply_update = 1'b0;
      event_address = 0;
      next_timestamp = occurrence_timestamp;
      incoming_polarity = polarity ? 2'b10 : 2'b01;
      next_polarity = incoming_polarity;

      if (event_valid && mapped_valid) begin
        if ($signed(world_x) < 0 || $signed(world_x) >= GRID_W ||
            $signed(world_y) < 0 || $signed(world_y) >= GRID_H) begin
          expected_range = 1'b1;
        end else begin
          event_address = $signed(world_y) * GRID_W + $signed(world_x);
          if (!model_valid[event_address] ||
              occurrence_timestamp > model_timestamp[event_address]) begin
            expected_update = 1'b1;
            apply_update = 1'b1;
          end else if (occurrence_timestamp ==
                       model_timestamp[event_address]) begin
            expected_update = 1'b1;
            expected_equal = 1'b1;
            apply_update = 1'b1;
            next_timestamp = model_timestamp[event_address];
            next_polarity =
              model_polarity[event_address] | incoming_polarity;
          end else begin
            expected_stale = 1'b1;
          end
        end
      end else if (event_valid && !mapped_valid) begin
        mapped_invalid_count = mapped_invalid_count + 1;
      end

      @(posedge clk);
      #1;
      if (apply_update) begin
        model_valid[event_address] = 1'b1;
        model_timestamp[event_address] = next_timestamp;
        model_polarity[event_address] = next_polarity;
      end
      if (update_applied !== expected_update ||
          equal_time_merged !== expected_equal ||
          stale_ignored !== expected_stale ||
          range_error !== expected_range) begin
        errors = errors + 1;
        status_errors = status_errors + 1;
        if (status_errors <= 20)
          $display("STATUS_MISMATCH cycle=%0d got=(%b,%b,%b,%b) expected=(%b,%b,%b,%b)",
                   cycle,
                   update_applied, equal_time_merged,
                   stale_ignored, range_error,
                   expected_update, expected_equal,
                   expected_stale, expected_range);
      end
      if (expected_update) update_count = update_count + 1;
      if (expected_equal) equal_count = equal_count + 1;
      if (expected_stale) stale_count = stale_count + 1;
      if (expected_range) range_count = range_count + 1;
      if (event_valid && mapped_valid && polarity)
        polarity1_count = polarity1_count + 1;
      if (event_valid && mapped_valid && !polarity)
        polarity0_count = polarity0_count + 1;
      check_readback;

      // Independently read every addressed cell after its event, so a write,
      // equal merge, or stale ignore is checked immediately against the model.
      if (event_valid && mapped_valid && !expected_range) begin
        saved_read_x = read_x;
        saved_read_y = read_y;
        read_x = world_x;
        read_y = world_y;
        #1;
        check_readback;
        read_x = saved_read_x;
        read_y = saved_read_y;
      end
    end
  endtask

  initial begin
    errors = 0;
    status_errors = 0;
    read_errors = 0;
    invalid_read_errors = 0;
    ready_errors = 0;
    update_count = 0;
    equal_count = 0;
    stale_count = 0;
    range_count = 0;
    mapped_invalid_count = 0;
    polarity0_count = 0;
    polarity1_count = 0;
    valid_read_count = 0;
    invalid_read_count = 0;
    reset_count = 0;
    rng_seed = 32'h76face;
    rst = 1'b0;
    event_valid = 1'b0;
    mapped_valid = 1'b0;
    world_x = 0;
    world_y = 0;
    polarity = 1'b0;
    occurrence_timestamp = 0;
    read_x = 0;
    read_y = 0;

    apply_reset_and_check;

    // Directed timestamp and polarity rules before the randomized run.
    read_x = 0; read_y = 0;
    event_valid = 1; mapped_valid = 1;
    world_x = 0; world_y = 0; polarity = 0; occurrence_timestamp = 100;
    step_event;
    polarity = 1; occurrence_timestamp = 100;
    step_event;
    polarity = 0; occurrence_timestamp = 90;
    step_event;
    mapped_valid = 0; occurrence_timestamp = 200;
    step_event;
    mapped_valid = 1; world_x = -1; occurrence_timestamp = 300;
    step_event;

    for (cycle = 0; cycle < RANDOM_CYCLES; cycle = cycle + 1) begin
      if (cycle == RANDOM_CYCLES/2)
        apply_reset_and_check;

      draw = (($random(rng_seed) % 100) + 100) % 100;
      x_choice = draw % GRID_W;
      draw = (($random(rng_seed) % 100) + 100) % 100;
      y_choice = draw % GRID_H;
      address = y_choice * GRID_W + x_choice;

      event_valid = 1'b1;
      mapped_valid = 1'b1;
      world_x = x_choice;
      world_y = y_choice;
      polarity = $random(rng_seed);
      case (cycle % 9)
        0: mapped_valid = 1'b0;
        1: world_x = -1;
        2: world_y = -3;
        3: world_x = GRID_W;
        4: world_y = GRID_H;
        5: begin
          if (model_valid[address])
            occurrence_timestamp = model_timestamp[address] + 1 +
                                   (($random(rng_seed) & 3));
          else
            occurrence_timestamp = 1 + (($random(rng_seed) & 12'h1ff));
        end
        6: begin
          if (model_valid[address])
            occurrence_timestamp = model_timestamp[address];
          else
            occurrence_timestamp = 1 + (($random(rng_seed) & 12'h1ff));
        end
        7: begin
          if (model_valid[address] && model_timestamp[address] != 0)
            occurrence_timestamp = model_timestamp[address] - 1;
          else
            occurrence_timestamp = 0;
        end
        default: begin
          event_valid = 1'b0;
          mapped_valid = $random(rng_seed);
          occurrence_timestamp = $random(rng_seed);
        end
      endcase

      if ((cycle % 11) == 0) begin
        read_x = GRID_W;
        read_y = y_choice;
      end else if ((cycle % 13) == 0) begin
        read_x = x_choice;
        read_y = GRID_H;
      end else begin
        read_x = (($random(rng_seed) % GRID_W) + GRID_W) % GRID_W;
        read_y = (($random(rng_seed) % GRID_H) + GRID_H) % GRID_H;
      end
      step_event;
    end

    if (update_count == 0 || equal_count == 0 || stale_count == 0 ||
        range_count == 0 || mapped_invalid_count == 0 ||
        polarity0_count == 0 || polarity1_count == 0 ||
        valid_read_count == 0 || invalid_read_count == 0 ||
        reset_count < 2) begin
      errors = errors + 1;
      $display("COVERAGE_FAIL updates=%0d equal=%0d stale=%0d range=%0d mapped_invalid=%0d pol0=%0d pol1=%0d valid_reads=%0d invalid_reads=%0d resets=%0d",
               update_count, equal_count, stale_count, range_count,
               mapped_invalid_count, polarity0_count, polarity1_count,
               valid_read_count, invalid_read_count, reset_count);
    end

    $display("WORLD_TIME_SURFACE_RANDOM_COUNTS cycles=%0d updates=%0d equal=%0d stale=%0d range=%0d mapped_invalid=%0d valid_reads=%0d invalid_reads=%0d resets=%0d",
             RANDOM_CYCLES, update_count, equal_count, stale_count,
             range_count, mapped_invalid_count,
             valid_read_count, invalid_read_count, reset_count);
    $display("WORLD_TIME_SURFACE_RANDOM_ERRORS status=%0d reads=%0d invalid_reads=%0d ready=%0d",
             status_errors, read_errors, invalid_read_errors, ready_errors);
    if (errors == 0) begin
      $display("WORLD_TIME_SURFACE_RANDOM_PASS");
      $finish;
    end else begin
      $fatal(1, "WORLD_TIME_SURFACE_RANDOM_FAIL errors=%0d", errors);
    end
  end
endmodule
