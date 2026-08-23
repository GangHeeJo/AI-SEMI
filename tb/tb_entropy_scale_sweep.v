// 1번 조건①(N이 커져도 bits/event가 안 터짐)을 정밀 검증.
// 순진한 raw 주소지정은 bits/event=log2(N)로 N에 비례해 무한정 커지는 반면,
// 3단 적응형(a6_tristate_raw_ef_bitmap)이 실제 정보이론 하한(log2 C(N,K), 조합론적
// 최소 비트수)에 얼마나 가깝게 붙어있는지를 N=16,64,256,1024 전 구간에서 비율로 비교.
// "완벽히 해결"의 기준: adaptive/entropy 비율은 N이 커져도 거의 안 커지고,
// raw/entropy 비율은 N이 커질수록 계속 커져야(발산) 조건①이 입증된 것.
`timescale 1ns/1ps
`ifndef NSRC
`define NSRC 16
`endif

module tb_entropy_scale_sweep;
  parameter NUM_SOURCES = `NSRC;
  localparam ADDRESS_WIDTH = $clog2(NUM_SOURCES);
  localparam COUNT_WIDTH = $clog2(NUM_SOURCES + 1);
  localparam MAX_BATCH = NUM_SOURCES;

  reg [COUNT_WIDTH-1:0] batch_count;
  reg [MAX_BATCH*ADDRESS_WIDTH-1:0] batch_sources;
  wire [1:0] mode_out;
  wire [31:0] total_bits_out;
  wire input_error;
  wire [31:0] raw_bits_dbg, ef_bits_dbg;

  a6_tristate_raw_ef_bitmap #(
    .NUM_SOURCES(NUM_SOURCES), .MAX_BATCH(MAX_BATCH),
    .ADDRESS_WIDTH(ADDRESS_WIDTH), .COUNT_WIDTH(COUNT_WIDTH)
  ) dut(
    .batch_count(batch_count), .batch_sources(batch_sources),
    .mode_out(mode_out), .total_bits_out(total_bits_out), .input_error(input_error),
    .raw_bits_dbg(raw_bits_dbg), .ef_bits_dbg(ef_bits_dbg));

  integer rng_seed = 29;
  integer trial, k, s, tries, n_sorted, idx, draw;
  reg [NUM_SOURCES-1:0] chosen;
  integer sorted_list [0:NUM_SOURCES-1];
  integer count_trials;
  real sum_tri, sum_raw, sum_entropy;

  task automatic build_batch;
    input integer kcount;
    begin
      if (kcount == NUM_SOURCES) begin
        for (s = 0; s < NUM_SOURCES; s = s + 1) sorted_list[s] = s;
      end else begin
        chosen = {NUM_SOURCES{1'b0}}; n_sorted = 0; tries = 0;
        while (n_sorted < kcount && tries < NUM_SOURCES * 50) begin
          draw = (($random(rng_seed) % NUM_SOURCES + NUM_SOURCES) % NUM_SOURCES);
          if (!chosen[draw]) begin chosen[draw] = 1'b1; n_sorted = n_sorted + 1; end
          tries = tries + 1;
        end
        idx = 0;
        for (s = 0; s < NUM_SOURCES; s = s + 1)
          if (chosen[s]) begin sorted_list[idx] = s; idx = idx + 1; end
      end
      batch_count = kcount;
      batch_sources = {(MAX_BATCH*ADDRESS_WIDTH){1'b0}};
      for (s = 0; s < kcount; s = s + 1)
        batch_sources[s*ADDRESS_WIDTH +: ADDRESS_WIDTH] = sorted_list[s];
    end
  endtask

  // 정보이론 하한: log2 C(N,K) = sum_{i=0}^{K-1} log2(N-i) - log2(i+1)
  function real log2c_nk;
    input integer n, kk;
    real acc;
    integer i;
    begin
      acc = 0.0;
      for (i = 0; i < kk; i = i + 1)
        acc = acc + ($ln(n - i * 1.0) - $ln(i + 1.0)) / $ln(2.0);
      log2c_nk = acc;
    end
  endfunction

  initial begin
    for (k = 1; k <= NUM_SOURCES; k = k * 2) begin
      sum_tri = 0.0; sum_raw = 0.0; sum_entropy = 0.0; count_trials = 0;
      for (trial = 0; trial < 30; trial = trial + 1) begin
        build_batch(k);
        #1;
        if (!input_error) begin
          sum_tri = sum_tri + total_bits_out * 1.0;
          sum_raw = sum_raw + raw_bits_dbg * 1.0;
          sum_entropy = sum_entropy + log2c_nk(NUM_SOURCES, k);
          count_trials = count_trials + 1;
        end
      end
      $display("N=%0d K=%0d adaptive_avg=%0.1f raw_avg=%0.1f entropy_bound=%0.1f adaptive/entropy=%0.2f raw/entropy=%0.2f",
        NUM_SOURCES, k,
        sum_tri/count_trials, sum_raw/count_trials, sum_entropy/count_trials,
        sum_tri/sum_entropy, sum_raw/sum_entropy);
    end
    $display("ENTROPY_SCALE_SWEEP_DONE N=%0d", NUM_SOURCES);
    $finish;
  end
endmodule
