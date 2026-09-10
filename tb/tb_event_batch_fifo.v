`timescale 1ns/1ps
module tb_event_batch_fifo;
  localparam DATA_W = 16;
  localparam IN_LANES = 8;
  parameter DEPTH = 8;
  localparam MAX_EVENTS = 50000;

  reg clk = 0;
  reg rst;
  reg [IN_LANES-1:0] in_valid;
  reg [IN_LANES*DATA_W-1:0] in_data_flat;
  wire [IN_LANES-1:0] in_overflow;
  wire out_valid;
  wire [DATA_W-1:0] out_data;
  reg out_ready;
  wire [$clog2(DEPTH+1)-1:0] occupancy;

  integer oracle [0:MAX_EVENTS-1];
  integer oracle_head;
  integer oracle_tail;
  integer oracle_count;
  integer presented;
  integer accepted;
  integer retired;
  integer overflowed;
  integer order_errors;
  integer overflow_errors;
  integer stability_errors;
  integer state_errors;
  integer errors;
  integer next_word;
  integer rng_seed;
  integer cycle;
  integer lane;
  integer draw;
  integer arrival_pct;
  reg [IN_LANES-1:0] random_mask;
  reg random_ready;

  event_batch_fifo #(
    .DATA_W(DATA_W), .IN_LANES(IN_LANES), .DEPTH(DEPTH)
  ) dut (
    .clk(clk), .rst(rst),
    .in_valid(in_valid), .in_data_flat(in_data_flat),
    .in_overflow(in_overflow),
    .out_valid(out_valid), .out_data(out_data), .out_ready(out_ready),
    .occupancy(occupancy)
  );

  always #5 clk = ~clk;

  task automatic drive_and_step;
    input [IN_LANES-1:0] valid_mask;
    input integer ready_value;
    integer lane_i;
    integer free_slots;
    integer accepted_in_batch;
    integer pop_expected;
    integer hold_expected;
    reg [DATA_W-1:0] held_data;
    reg [IN_LANES-1:0] accept_expected;
    reg [IN_LANES-1:0] overflow_expected;
    begin
      in_valid = valid_mask;
      out_ready = ready_value[0];
      for (lane_i = 0; lane_i < IN_LANES; lane_i = lane_i + 1) begin
        in_data_flat[lane_i*DATA_W +: DATA_W] = next_word;
        next_word = next_word + 1;
      end

      #1;
      if (out_valid !== (oracle_count != 0)) begin
        state_errors = state_errors + 1;
        errors = errors + 1;
        $display("OUT_VALID_MISMATCH count=%0d got=%b", oracle_count, out_valid);
      end
      if (oracle_count != 0 && out_data !== oracle[oracle_head][DATA_W-1:0]) begin
        order_errors = order_errors + 1;
        errors = errors + 1;
        $display("ORDER_MISMATCH expected=%0d got=%0d",
                 oracle[oracle_head], out_data);
      end

      pop_expected = (oracle_count != 0) && ready_value;
      free_slots = DEPTH - oracle_count + pop_expected;
      accepted_in_batch = 0;
      accept_expected = {IN_LANES{1'b0}};
      overflow_expected = {IN_LANES{1'b0}};
      for (lane_i = 0; lane_i < IN_LANES; lane_i = lane_i + 1) begin
        if (valid_mask[lane_i]) begin
          presented = presented + 1;
          if (accepted_in_batch < free_slots) begin
            accept_expected[lane_i] = 1'b1;
            accepted_in_batch = accepted_in_batch + 1;
          end else begin
            overflow_expected[lane_i] = 1'b1;
          end
        end
      end
      if (in_overflow !== overflow_expected) begin
        overflow_errors = overflow_errors + 1;
        errors = errors + 1;
        $display("OVERFLOW_MISMATCH count=%0d ready=%0d valid=%b got=%b expected=%b",
                 oracle_count, ready_value, valid_mask,
                 in_overflow, overflow_expected);
      end

      hold_expected = (oracle_count != 0) && !ready_value;
      held_data = out_data;
      @(posedge clk);
      #1;

      if (pop_expected) begin
        oracle_head = oracle_head + 1;
        oracle_count = oracle_count - 1;
        retired = retired + 1;
      end
      for (lane_i = 0; lane_i < IN_LANES; lane_i = lane_i + 1) begin
        if (accept_expected[lane_i]) begin
          if (oracle_tail >= MAX_EVENTS) begin
            errors = errors + 1;
            $fatal(1, "TB oracle capacity exceeded");
          end
          oracle[oracle_tail] = in_data_flat[lane_i*DATA_W +: DATA_W];
          oracle_tail = oracle_tail + 1;
          oracle_count = oracle_count + 1;
          accepted = accepted + 1;
        end
        if (overflow_expected[lane_i])
          overflowed = overflowed + 1;
      end

      if (hold_expected &&
          (out_valid !== 1'b1 || out_data !== held_data)) begin
        stability_errors = stability_errors + 1;
        errors = errors + 1;
        $display("OUTPUT_CHANGED_WHILE_BLOCKED before=%0d after=%0d valid=%b",
                 held_data, out_data, out_valid);
      end
      if (occupancy !== oracle_count) begin
        state_errors = state_errors + 1;
        errors = errors + 1;
        $display("OCCUPANCY_MISMATCH expected=%0d got=%0d",
                 oracle_count, occupancy);
      end
      if (out_valid !== (oracle_count != 0)) begin
        state_errors = state_errors + 1;
        errors = errors + 1;
        $display("POST_EDGE_VALID_MISMATCH count=%0d got=%b",
                 oracle_count, out_valid);
      end
      if (oracle_count != 0 && out_data !== oracle[oracle_head][DATA_W-1:0]) begin
        order_errors = order_errors + 1;
        errors = errors + 1;
        $display("POST_EDGE_ORDER_MISMATCH expected=%0d got=%0d",
                 oracle[oracle_head], out_data);
      end
    end
  endtask

  initial begin
    rst = 1'b1;
    in_valid = 0;
    in_data_flat = 0;
    out_ready = 1'b0;
    oracle_head = 0;
    oracle_tail = 0;
    oracle_count = 0;
    presented = 0;
    accepted = 0;
    retired = 0;
    overflowed = 0;
    order_errors = 0;
    overflow_errors = 0;
    stability_errors = 0;
    state_errors = 0;
    errors = 0;
    next_word = 1;
    rng_seed = 32'h0badcafe;

    repeat (2) @(posedge clk);
    #1;
    if (out_valid !== 1'b0 || occupancy !== 0) begin
      errors = errors + 1;
      state_errors = state_errors + 1;
      $display("RESET_STATE_FAIL valid=%b occupancy=%0d", out_valid, occupancy);
    end
    in_valid = {IN_LANES{1'b1}};
    #1;
    if (in_overflow !== {IN_LANES{1'b1}}) begin
      errors = errors + 1;
      overflow_errors = overflow_errors + 1;
      $display("RESET_OVERFLOW_FAIL got=%b", in_overflow);
    end
    in_valid = 0;
    rst = 1'b0;

    // Sparse batches prove lane compaction and ascending-lane order.
    drive_and_step(8'b0010_0101, 0);
    drive_and_step(8'b1001_0010, 0);

    // Only two slots remain: lanes 0 and 1 fit; higher valid lanes overflow.
    drive_and_step(8'hff, 0);
    // No pop means a full FIFO rejects the complete batch and holds its head.
    drive_and_step(8'hff, 0);
    // A same-cycle pop opens exactly one slot, which the lowest lane uses.
    drive_and_step(8'hff, 1);

    // Drain the directed sequence before randomized backpressure.
    while (oracle_count != 0)
      drive_and_step(0, 1);

    for (cycle = 0; cycle < 3000; cycle = cycle + 1) begin
      random_mask = 0;
      arrival_pct = (cycle < 500) ? 5 : 25;
      for (lane = 0; lane < IN_LANES; lane = lane + 1) begin
        draw = (($random(rng_seed) % 100) + 100) % 100;
        if (draw < arrival_pct)
          random_mask[lane] = 1'b1;
      end
      draw = (($random(rng_seed) % 100) + 100) % 100;
      random_ready = (draw < 65);
      drive_and_step(random_mask, random_ready);
    end

    while (oracle_count != 0)
      drive_and_step(0, 1);
    drive_and_step(0, 1);

    if (presented !== accepted + overflowed) begin
      errors = errors + 1;
      state_errors = state_errors + 1;
      $display("INPUT_ACCOUNTING_FAIL presented=%0d accepted=%0d overflowed=%0d",
               presented, accepted, overflowed);
    end
    if (accepted !== retired + oracle_count) begin
      errors = errors + 1;
      state_errors = state_errors + 1;
      $display("CONSERVATION_FAIL accepted=%0d retired=%0d pending=%0d",
               accepted, retired, oracle_count);
    end

    $display("EVENT_BATCH_FIFO_COUNTS presented=%0d accepted=%0d retired=%0d overflowed=%0d pending=%0d",
             presented, accepted, retired, overflowed, oracle_count);
    $display("EVENT_BATCH_FIFO_ERRORS ordering=%0d overflow=%0d stability=%0d state=%0d",
             order_errors, overflow_errors, stability_errors, state_errors);
    if (errors == 0) begin
      $display("EVENT_BATCH_FIFO_PASS");
      $finish;
    end else begin
      $fatal(1, "EVENT_BATCH_FIFO_FAIL errors=%0d", errors);
    end
  end
endmodule
