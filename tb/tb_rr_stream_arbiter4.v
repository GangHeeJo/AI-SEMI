`timescale 1ns/1ps
module tb_rr_stream_arbiter4;
  parameter DATA_W = 16;
  localparam RANDOM_CYCLES = 5000;

  reg clk = 0;
  reg rst;
  reg [3:0] in_valid;
  reg [4*DATA_W-1:0] in_data_flat;
  wire [3:0] in_ready;
  wire out_valid;
  wire [DATA_W-1:0] out_data;
  wire [1:0] out_source;
  reg out_ready;

  reg [1:0] model_rr_ptr;
  reg model_lock_valid;
  reg [1:0] model_lock_source;
  reg [DATA_W-1:0] model_lock_data;
  reg previous_stall;
  reg [1:0] previous_source;
  reg [DATA_W-1:0] previous_data;

  integer errors;
  integer select_errors;
  integer ready_errors;
  integer stability_errors;
  integer order_errors;
  integer handshakes;
  integer last_handshake;
  integer last_source;
  integer last_data;
  integer source_grants [0:3];
  integer produced_seq [0:3];
  integer consumed_seq [0:3];
  integer rng_seed;
  integer cycle;
  integer source;
  integer draw;

  rr_stream_arbiter4 #(.DATA_W(DATA_W)) dut (
    .clk(clk), .rst(rst),
    .in_valid(in_valid), .in_data_flat(in_data_flat), .in_ready(in_ready),
    .out_valid(out_valid), .out_data(out_data), .out_source(out_source),
    .out_ready(out_ready)
  );

  always #5 clk = ~clk;

  function [DATA_W-1:0] event_word;
    input integer source_in;
    input integer sequence_in;
    begin
      event_word = ((source_in & 3) << 14) | (sequence_in & 16'h3fff);
    end
  endfunction

  task automatic set_source_data;
    input integer source_in;
    input [DATA_W-1:0] data_in;
    begin
      in_data_flat[source_in*DATA_W +: DATA_W] = data_in;
    end
  endtask

  task automatic reset_dut_and_model;
    begin
      rst = 1'b1;
      in_valid = 4'b0000;
      in_data_flat = 0;
      out_ready = 1'b0;
      model_rr_ptr = 2'd0;
      model_lock_valid = 1'b0;
      model_lock_source = 2'd0;
      model_lock_data = 0;
      previous_stall = 1'b0;
      repeat (2) @(posedge clk);
      #1;
      if (out_valid !== 1'b0 || in_ready !== 4'b0000) begin
        errors = errors + 1;
        select_errors = select_errors + 1;
        $display("RESET_OUTPUT_FAIL valid=%b ready=%b", out_valid, in_ready);
      end
      rst = 1'b0;
    end
  endtask

  task automatic check_and_step;
    reg expected_valid;
    reg [1:0] expected_source;
    reg [DATA_W-1:0] expected_data;
    reg [3:0] expected_ready;
    integer offset_i;
    integer candidate;
    integer handshake_expected;
    begin
      #1;
      expected_valid = 1'b0;
      expected_source = model_rr_ptr;
      expected_data = 0;
      if (model_lock_valid) begin
        expected_valid = 1'b1;
        expected_source = model_lock_source;
        expected_data = model_lock_data;
      end else begin
        for (offset_i = 0; offset_i < 4; offset_i = offset_i + 1) begin
          candidate = (model_rr_ptr + offset_i) & 3;
          if (!expected_valid && in_valid[candidate]) begin
            expected_valid = 1'b1;
            expected_source = candidate;
            expected_data = in_data_flat[candidate*DATA_W +: DATA_W];
          end
        end
      end

      expected_ready = 4'b0000;
      if (expected_valid)
        expected_ready[expected_source] = out_ready;

      if (out_valid !== expected_valid ||
          (expected_valid &&
           (out_source !== expected_source || out_data !== expected_data))) begin
        errors = errors + 1;
        select_errors = select_errors + 1;
        $display("SELECT_MISMATCH ptr=%0d lock=%b valid=%b source=%0d data=%0d expected_valid=%b expected_source=%0d expected_data=%0d",
                 model_rr_ptr, model_lock_valid,
                 out_valid, out_source, out_data,
                 expected_valid, expected_source, expected_data);
      end
      if (in_ready !== expected_ready) begin
        errors = errors + 1;
        ready_errors = ready_errors + 1;
        $display("READY_MISMATCH got=%b expected=%b", in_ready, expected_ready);
      end
      if (previous_stall &&
          (out_valid !== 1'b1 ||
           out_source !== previous_source || out_data !== previous_data)) begin
        errors = errors + 1;
        stability_errors = stability_errors + 1;
        $display("STALLED_OUTPUT_CHANGED got=(%b,%0d,%0d) expected=(1,%0d,%0d)",
                 out_valid, out_source, out_data, previous_source, previous_data);
      end

      handshake_expected = expected_valid && out_ready;
      last_handshake = handshake_expected;
      last_source = expected_source;
      last_data = expected_data;
      previous_stall = expected_valid && !out_ready;
      previous_source = expected_source;
      previous_data = expected_data;

      @(posedge clk);
      #1;
      if (model_lock_valid) begin
        if (handshake_expected) begin
          model_rr_ptr = model_lock_source + 2'd1;
          model_lock_valid = 1'b0;
        end
      end else if (expected_valid) begin
        if (handshake_expected) begin
          model_rr_ptr = expected_source + 2'd1;
        end else begin
          model_lock_valid = 1'b1;
          model_lock_source = expected_source;
          model_lock_data = expected_data;
        end
      end
      if (handshake_expected)
        handshakes = handshakes + 1;
    end
  endtask

  initial begin
    errors = 0;
    select_errors = 0;
    ready_errors = 0;
    stability_errors = 0;
    order_errors = 0;
    handshakes = 0;
    rng_seed = 32'h41b17e;
    for (source = 0; source < 4; source = source + 1) begin
      source_grants[source] = 0;
      produced_seq[source] = 0;
      consumed_seq[source] = 0;
    end

    // Reset and a lone source: an inactive input is never reported ready.
    reset_dut_and_model;
    in_valid = 4'b0100;
    set_source_data(2, event_word(2, 0));
    out_ready = 1'b1;
    for (cycle = 0; cycle < 5; cycle = cycle + 1) begin
      check_and_step;
      if (!last_handshake || last_source != 2) begin
        errors = errors + 1;
        select_errors = select_errors + 1;
      end
      set_source_data(2, event_word(2, cycle + 1));
    end

    // A stalled source 3 remains selected when newer source 0/1 inputs appear.
    reset_dut_and_model;
    in_valid = 4'b1000;
    set_source_data(3, 16'hc123);
    out_ready = 1'b0;
    check_and_step;
    in_valid = 4'b1011;
    set_source_data(0, 16'h0001);
    set_source_data(1, 16'h4001);
    check_and_step;
    check_and_step;
    out_ready = 1'b1;
    check_and_step;
    if (!last_handshake || last_source != 3 || last_data != 16'hc123) begin
      errors = errors + 1;
      stability_errors = stability_errors + 1;
    end

    // Four continuously active sources must receive an exact 0,1,2,3 rotation.
    reset_dut_and_model;
    in_valid = 4'b1111;
    out_ready = 1'b1;
    for (source = 0; source < 4; source = source + 1) begin
      source_grants[source] = 0;
      set_source_data(source, event_word(source, 0));
    end
    for (cycle = 0; cycle < 64; cycle = cycle + 1) begin
      check_and_step;
      if (!last_handshake || last_source != (cycle & 3)) begin
        errors = errors + 1;
        select_errors = select_errors + 1;
        $display("FAIRNESS_SEQUENCE_FAIL cycle=%0d source=%0d", cycle, last_source);
      end
      source_grants[last_source] = source_grants[last_source] + 1;
      set_source_data(last_source,
                      event_word(last_source, source_grants[last_source]));
    end
    for (source = 0; source < 4; source = source + 1) begin
      if (source_grants[source] != 16) begin
        errors = errors + 1;
        select_errors = select_errors + 1;
        $display("FAIRNESS_COUNT_FAIL source=%0d grants=%0d",
                 source, source_grants[source]);
      end
    end

    // Random compliant producers hold valid/data until their own handshake.
    reset_dut_and_model;
    in_valid = 4'b0000;
    for (source = 0; source < 4; source = source + 1) begin
      produced_seq[source] = 0;
      consumed_seq[source] = 0;
    end
    for (cycle = 0; cycle < RANDOM_CYCLES; cycle = cycle + 1) begin
      for (source = 0; source < 4; source = source + 1) begin
        if (!in_valid[source]) begin
          draw = (($random(rng_seed) % 100) + 100) % 100;
          if (draw < 35) begin
            in_valid[source] = 1'b1;
            set_source_data(source,
                            event_word(source, produced_seq[source]));
            produced_seq[source] = produced_seq[source] + 1;
          end
        end
      end
      draw = (($random(rng_seed) % 100) + 100) % 100;
      out_ready = (draw < 55);
      check_and_step;
      if (last_handshake) begin
        if (last_data !== event_word(last_source,
                                     consumed_seq[last_source])) begin
          errors = errors + 1;
          order_errors = order_errors + 1;
          $display("SOURCE_ORDER_FAIL source=%0d expected_seq=%0d got_data=%0d",
                   last_source, consumed_seq[last_source], last_data);
        end
        consumed_seq[last_source] = consumed_seq[last_source] + 1;
        in_valid[last_source] = 1'b0;
      end
    end

    out_ready = 1'b1;
    while (in_valid != 0 || model_lock_valid) begin
      check_and_step;
      if (last_handshake) begin
        if (last_data !== event_word(last_source,
                                     consumed_seq[last_source])) begin
          errors = errors + 1;
          order_errors = order_errors + 1;
        end
        consumed_seq[last_source] = consumed_seq[last_source] + 1;
        in_valid[last_source] = 1'b0;
      end
    end
    check_and_step;

    for (source = 0; source < 4; source = source + 1) begin
      if (produced_seq[source] != consumed_seq[source]) begin
        errors = errors + 1;
        order_errors = order_errors + 1;
        $display("SOURCE_CONSERVATION_FAIL source=%0d produced=%0d consumed=%0d",
                 source, produced_seq[source], consumed_seq[source]);
      end
    end

    $display("RR_STREAM_ARBITER4_COUNTS handshakes=%0d random_consumed=[%0d,%0d,%0d,%0d]",
             handshakes,
             consumed_seq[0], consumed_seq[1],
             consumed_seq[2], consumed_seq[3]);
    $display("RR_STREAM_ARBITER4_ERRORS select=%0d ready=%0d stability=%0d order=%0d",
             select_errors, ready_errors, stability_errors, order_errors);
    if (errors == 0) begin
      $display("RR_STREAM_ARBITER4_PASS");
      $finish;
    end else begin
      $fatal(1, "RR_STREAM_ARBITER4_FAIL errors=%0d", errors);
    end
  end
endmodule
