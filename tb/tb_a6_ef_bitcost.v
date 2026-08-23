// A6 Elias-Fano 배치 인코더의 실제 비트비용을 RTL 조합논리에서 직접 읽어서 측정.
// batch_valid를 세우면 ef_length_comb/raw_length_comb/input_error_comb이 그 사이클에
// 바로 계산되므로(SEND_MARKER/SEND_BITS의 다중사이클 전송까지 갈 필요 없이), 배치
// 하나당 "실제 인코더가 고른 비트수"를 그대로 읽는다. K(동시활성 소스 수)를
// 1,2,4,8,16으로 스윕하며 무작위 정렬집합을 여러 번 뽑아 평균/최선/최악 비교.
`timescale 1ns/1ps
module tb_a6_ef_bitcost;
  parameter NUM_SOURCES = 16;
  parameter MAX_BATCH = 16;
  parameter ADDRESS_WIDTH = 4;
  parameter COUNT_WIDTH = 5;

  reg clk = 0;
  reg rst_n;
  reg batch_valid;
  wire batch_ready;
  reg [COUNT_WIDTH-1:0] batch_count;
  reg [MAX_BATCH*ADDRESS_WIDTH-1:0] batch_sources;
  wire [1:0] link_count, link_data;
  reg link_ready;
  wire encode_error, encoded_ef_observe;

  a6_ef_batch_encoder #(.NUM_SOURCES(NUM_SOURCES), .MAX_BATCH(MAX_BATCH)) dut(
    .clk(clk), .rst_n(rst_n),
    .batch_valid(batch_valid), .batch_ready(batch_ready),
    .batch_count(batch_count), .batch_sources(batch_sources),
    .link_count(link_count), .link_data(link_data), .link_ready(link_ready),
    .encode_error(encode_error), .encoded_ef_observe(encoded_ef_observe));

  always #5 clk = ~clk;

  integer rng_seed = 11;
  integer trial, k, s, picked, tries;
  reg [15:0] chosen;
  integer sorted_list [0:15];
  integer n_sorted;
  integer ef_bits, raw_bits, chosen_bits;
  integer sum_ef, sum_raw, sum_chosen, count_trials;
  integer worst_chosen;

  task automatic build_batch;
    input integer kcount;
    integer draw, idx;
    begin
      chosen = 16'd0;
      n_sorted = 0;
      tries = 0;
      while (n_sorted < kcount && tries < 1000) begin
        draw = (($random(rng_seed) % 16 + 16) % 16);
        if (!chosen[draw]) begin
          chosen[draw] = 1'b1;
          n_sorted = n_sorted + 1;
        end
        tries = tries + 1;
      end
      idx = 0;
      for (s = 0; s < 16; s = s + 1) begin
        if (chosen[s]) begin
          sorted_list[idx] = s;
          idx = idx + 1;
        end
      end
      batch_count = kcount;
      batch_sources = {(MAX_BATCH*ADDRESS_WIDTH){1'b0}};
      for (s = 0; s < kcount; s = s + 1)
        batch_sources[s*ADDRESS_WIDTH +: ADDRESS_WIDTH] = sorted_list[s][3:0];
    end
  endtask

  initial begin
    rst_n = 0; batch_valid = 0; link_ready = 1; batch_count = 0;
    batch_sources = {(MAX_BATCH*ADDRESS_WIDTH){1'b0}};
    @(posedge clk); @(posedge clk);
    rst_n = 1;
    @(posedge clk); #1;

    for (k = 1; k <= 16; k = k * 2) begin
      sum_ef = 0; sum_raw = 0; sum_chosen = 0; count_trials = 0; worst_chosen = 0;
      for (trial = 0; trial < 30; trial = trial + 1) begin
        build_batch(k);
        batch_valid = 1;
        #1; // 조합논리 안정화
        ef_bits = 1 + dut.ef_length_comb;   // marker(1b) + EF 본문
        raw_bits = dut.raw_length_comb;      // marker 없음
        chosen_bits = (dut.ef_cycles_comb < dut.raw_cycles_comb) ? ef_bits : raw_bits;
        if (!dut.input_error_comb) begin
          sum_ef = sum_ef + ef_bits;
          sum_raw = sum_raw + raw_bits;
          sum_chosen = sum_chosen + chosen_bits;
          if (chosen_bits > worst_chosen) worst_chosen = chosen_bits;
          count_trials = count_trials + 1;
        end else begin
          $display("INPUT_ERROR k=%0d trial=%0d", k, trial);
        end
        @(posedge clk); #1;
        batch_valid = 0;
        @(posedge clk); #1;
      end
      $display("K=%0d avg_ef_bits=%0d.%0d avg_raw_bits=%0d.%0d avg_chosen_bits=%0d.%0d worst_chosen=%0d bitmap_bits=16 addr_bits(4*K)=%0d",
        k,
        sum_ef/count_trials, (sum_ef*10/count_trials)%10,
        sum_raw/count_trials, (sum_raw*10/count_trials)%10,
        sum_chosen/count_trials, (sum_chosen*10/count_trials)%10,
        worst_chosen, 4*k);
    end

    $display("A6_EF_BITCOST_DONE");
    $finish;
  end
endmodule
