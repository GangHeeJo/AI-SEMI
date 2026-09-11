`timescale 1ns/1ps
module tb_rr_stream_merge16;
  parameter DATA_W = 20;
  localparam RANDOM_CYCLES = 8000;

  reg clk = 0;
  reg rst;
  reg [15:0] in_valid;
  reg [16*DATA_W-1:0] in_data_flat;
  wire [15:0] in_ready;
  wire out_valid;
  wire [DATA_W-1:0] out_data;
  wire [3:0] out_source;
  reg out_ready;

  reg previous_stall;
  reg [3:0] previous_source;
  reg [DATA_W-1:0] previous_data;
  integer errors;
  integer fairness_errors;
  integer stability_errors;
  integer protocol_errors;
  integer order_errors;
  integer phantom_errors;
  integer total_produced;
  integer total_consumed;
  integer produced_seq [0:15];
  integer consumed_seq [0:15];
  integer source_grants [0:15];
  integer last_grant [0:15];
  integer max_gap [0:15];
  integer rng_seed;
  integer cycle;
  integer source;
  integer draw;
  integer expected_source;
  integer last_handshake;
  integer last_source;
  reg [DATA_W-1:0] last_data;

  rr_stream_merge16 #(.DATA_W(DATA_W)) dut (
    .clk(clk),
    .rst(rst),
    .in_valid(in_valid),
    .in_data_flat(in_data_flat),
    .in_ready(in_ready),
    .out_valid(out_valid),
    .out_data(out_data),
    .out_source(out_source),
    .out_ready(out_ready)
  );

  always #5 clk = ~clk;

  function [DATA_W-1:0] event_word;
    input integer source_in;
    input integer sequence_in;
    begin
      event_word = ((source_in & 15) << 16) |
                   (sequence_in & 16'hffff);
    end
  endfunction

  task set_source_data;
    input integer source_in;
    input [DATA_W-1:0] data_in;
    begin
      in_data_flat[source_in*DATA_W +: DATA_W] = data_in;
    end
  endtask

  task reset_dut;
    begin
      rst = 1'b1;
      in_valid = 16'h0000;
      in_data_flat = 0;
      out_ready = 1'b0;
      previous_stall = 1'b0;
      repeat (3) @(posedge clk);
      #1;
      if (out_valid !== 1'b0 || in_ready !== 16'h0000) begin
        errors = errors + 1;
        protocol_errors = protocol_errors + 1;
        $display("RESET_OUTPUT_FAIL valid=%b ready=%h", out_valid, in_ready);
      end
      rst = 1'b0;
    end
  endtask

  task check_and_step;
    reg sampled_stall;
    reg [3:0] sampled_source;
    reg [DATA_W-1:0] sampled_data;
    reg [15:0] expected_ready;
    begin
      #1;
      if (previous_stall &&
          (out_valid !== 1'b1 || out_source !== previous_source ||
           out_data !== previous_data)) begin
        errors = errors + 1;
        stability_errors = stability_errors + 1;
        $display("STALLED_OUTPUT_CHANGED got=(%b,%0d,%h) expected=(1,%0d,%h)",
                 out_valid, out_source, out_data,
                 previous_source, previous_data);
      end

      if (out_valid && !in_valid[out_source]) begin
        errors = errors + 1;
        phantom_errors = phantom_errors + 1;
        $display("PHANTOM_OUTPUT source=%0d data=%h", out_source, out_data);
      end
      if (out_valid &&
          out_data !== in_data_flat[out_source*DATA_W +: DATA_W]) begin
        errors = errors + 1;
        protocol_errors = protocol_errors + 1;
        $display("OUTPUT_INPUT_MISMATCH source=%0d output=%h input=%h",
                 out_source, out_data,
                 in_data_flat[out_source*DATA_W +: DATA_W]);
      end

      expected_ready = 16'h0000;
      if (out_valid && out_ready)
        expected_ready = 16'h0001 << out_source;
      if (in_ready !== expected_ready) begin
        errors = errors + 1;
        protocol_errors = protocol_errors + 1;
        $display("READY_MISMATCH got=%h expected=%h", in_ready, expected_ready);
      end
      if (out_ready && (|in_valid) && !out_valid) begin
        errors = errors + 1;
        protocol_errors = protocol_errors + 1;
        $display("NOT_WORK_CONSERVING valid=%h", in_valid);
      end

      last_handshake = out_valid && out_ready;
      last_source = out_source;
      last_data = out_data;
      sampled_stall = out_valid && !out_ready;
      sampled_source = out_source;
      sampled_data = out_data;

      @(posedge clk);
      #1;
      previous_stall = sampled_stall;
      previous_source = sampled_source;
      previous_data = sampled_data;
    end
  endtask

  task consume_last_random;
    begin
      if (last_handshake) begin
        if (last_data !== event_word(last_source, consumed_seq[last_source])) begin
          errors = errors + 1;
          order_errors = order_errors + 1;
          $display("SOURCE_ORDER_FAIL source=%0d expected_seq=%0d got=%h",
                   last_source, consumed_seq[last_source], last_data);
        end
        consumed_seq[last_source] = consumed_seq[last_source] + 1;
        total_consumed = total_consumed + 1;
        in_valid[last_source] = 1'b0;
      end
    end
  endtask

  initial begin
    errors = 0;
    fairness_errors = 0;
    stability_errors = 0;
    protocol_errors = 0;
    order_errors = 0;
    phantom_errors = 0;
    total_produced = 0;
    total_consumed = 0;
    rng_seed = 32'h16a4b17e;
    for (source = 0; source < 16; source = source + 1) begin
      produced_seq[source] = 0;
      consumed_seq[source] = 0;
      source_grants[source] = 0;
      last_grant[source] = -1;
      max_gap[source] = 0;
    end

    // Once source 15 is presented, later contenders cannot replace it while
    // the output is stalled.
    reset_dut;
    in_valid[15] = 1'b1;
    set_source_data(15, event_word(15, 16'h1234));
    out_ready = 1'b0;
    check_and_step;
    for (source = 0; source < 15; source = source + 1) begin
      in_valid[source] = 1'b1;
      set_source_data(source, event_word(source, source));
    end
    repeat (4) check_and_step;
    out_ready = 1'b1;
    check_and_step;
    if (!last_handshake || last_source != 15 ||
        last_data !== event_word(15, 16'h1234)) begin
      errors = errors + 1;
      stability_errors = stability_errors + 1;
      $display("DIRECTED_STALL_RELEASE_FAIL source=%0d data=%h",
               last_source, last_data);
    end

    // Under full contention the root rotates across groups and every leaf
    // rotates locally.  Every source is served once per sixteen handshakes.
    reset_dut;
    in_valid = 16'hffff;
    out_ready = 1'b1;
    for (source = 0; source < 16; source = source + 1)
      set_source_data(source, event_word(source, 0));
    for (cycle = 0; cycle < 256; cycle = cycle + 1) begin
      check_and_step;
      expected_source = ((cycle & 3) << 2) | ((cycle >> 2) & 3);
      if (!last_handshake || last_source != expected_source) begin
        errors = errors + 1;
        fairness_errors = fairness_errors + 1;
        $display("FAIRNESS_SEQUENCE_FAIL cycle=%0d got=%0d expected=%0d",
                 cycle, last_source, expected_source);
      end
      if (last_grant[last_source] >= 0 &&
          cycle - last_grant[last_source] > max_gap[last_source])
        max_gap[last_source] = cycle - last_grant[last_source];
      last_grant[last_source] = cycle;
      source_grants[last_source] = source_grants[last_source] + 1;
      set_source_data(last_source,
                      event_word(last_source, source_grants[last_source]));
    end
    for (source = 0; source < 16; source = source + 1) begin
      if (source_grants[source] != 16 || max_gap[source] > 16) begin
        errors = errors + 1;
        fairness_errors = fairness_errors + 1;
        $display("FAIRNESS_COUNT_FAIL source=%0d grants=%0d max_gap=%0d",
                 source, source_grants[source], max_gap[source]);
      end
    end

    // Random compliant producers hold one token per input until handshake.
    reset_dut;
    total_produced = 0;
    total_consumed = 0;
    for (source = 0; source < 16; source = source + 1) begin
      produced_seq[source] = 0;
      consumed_seq[source] = 0;
    end
    for (cycle = 0; cycle < RANDOM_CYCLES; cycle = cycle + 1) begin
      for (source = 0; source < 16; source = source + 1) begin
        if (!in_valid[source]) begin
          draw = (($random(rng_seed) % 100) + 100) % 100;
          if (draw < 35) begin
            in_valid[source] = 1'b1;
            set_source_data(source,
                            event_word(source, produced_seq[source]));
            produced_seq[source] = produced_seq[source] + 1;
            total_produced = total_produced + 1;
          end
        end
      end
      draw = (($random(rng_seed) % 100) + 100) % 100;
      out_ready = (draw < 60);
      check_and_step;
      consume_last_random;
    end

    out_ready = 1'b1;
    while (in_valid != 16'h0000) begin
      check_and_step;
      consume_last_random;
    end
    repeat (4) check_and_step;

    for (source = 0; source < 16; source = source + 1) begin
      if (produced_seq[source] != consumed_seq[source]) begin
        errors = errors + 1;
        order_errors = order_errors + 1;
        $display("SOURCE_CONSERVATION_FAIL source=%0d produced=%0d consumed=%0d",
                 source, produced_seq[source], consumed_seq[source]);
      end
    end
    if (total_produced != total_consumed) begin
      errors = errors + 1;
      order_errors = order_errors + 1;
      $display("TOTAL_CONSERVATION_FAIL produced=%0d consumed=%0d",
               total_produced, total_consumed);
    end

    $display("RR_STREAM_MERGE16_COUNTS random_produced=%0d random_consumed=%0d",
             total_produced, total_consumed);
    $display("RR_STREAM_MERGE16_ERRORS fairness=%0d stability=%0d protocol=%0d order=%0d phantom=%0d",
             fairness_errors, stability_errors, protocol_errors,
             order_errors, phantom_errors);
    if (errors == 0) begin
      $display("RR_STREAM_MERGE16_PASS");
      $finish;
    end else begin
      $fatal(1, "RR_STREAM_MERGE16_FAIL errors=%0d", errors);
    end
  end
endmodule
