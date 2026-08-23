// N=64로 3단 적응형(raw/EF/bitmap) 재검증 -- §78에서 N=16일 때 EF가 한 번도
// 안 뽑혔던 게 스케일 문제였는지 확인. a6_tristate_raw_ef_bitmap는 이미 N을
// 파라미터로 뒀으므로 그대로 재사용.
`timescale 1ns/1ps
module tb_tristate_bitcost_sweep_n64;
  parameter NUM_SOURCES = 64;
  parameter MAX_BATCH = 64;
  parameter ADDRESS_WIDTH = 6;
  parameter COUNT_WIDTH = 7;

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

  integer rng_seed = 17;
  integer trial, k, s, tries, n_sorted, idx, draw;
  reg [63:0] chosen;
  integer sorted_list [0:63];
  integer sum_tri, sum_bitmap_only, sum_2way, count_trials;
  integer mode_count [0:2];
  integer two_way_bits;

  task automatic build_batch;
    input integer kcount;
    begin
      chosen = 64'd0; n_sorted = 0; tries = 0;
      while (n_sorted < kcount && tries < 4000) begin
        draw = (($random(rng_seed) % 64 + 64) % 64);
        if (!chosen[draw]) begin chosen[draw]=1'b1; n_sorted=n_sorted+1; end
        tries = tries + 1;
      end
      idx = 0;
      for (s = 0; s < 64; s = s + 1)
        if (chosen[s]) begin sorted_list[idx] = s; idx = idx + 1; end
      batch_count = kcount;
      batch_sources = {(MAX_BATCH*ADDRESS_WIDTH){1'b0}};
      for (s = 0; s < kcount; s = s + 1)
        batch_sources[s*ADDRESS_WIDTH +: ADDRESS_WIDTH] = sorted_list[s][5:0];
    end
  endtask

  initial begin
    for (k = 1; k <= 64; k = k * 2) begin
      sum_tri = 0; sum_bitmap_only = 0; sum_2way = 0; count_trials = 0;
      mode_count[0]=0; mode_count[1]=0; mode_count[2]=0;
      for (trial = 0; trial < 30; trial = trial + 1) begin
        build_batch(k);
        #1;
        if (!input_error) begin
          sum_tri = sum_tri + total_bits_out;
          sum_bitmap_only = sum_bitmap_only + NUM_SOURCES;
          two_way_bits = (raw_bits_dbg < ef_bits_dbg) ? raw_bits_dbg : ef_bits_dbg;
          sum_2way = sum_2way + two_way_bits;
          mode_count[mode_out] = mode_count[mode_out] + 1;
          count_trials = count_trials + 1;
        end
      end
      $display("K=%0d tristate_avg=%0d.%0d bitmap_only_avg=%0d 2way_avg=%0d.%0d modes(raw=%0d,ef=%0d,bitmap=%0d)",
        k, sum_tri/count_trials, (sum_tri*10/count_trials)%10,
        sum_bitmap_only/count_trials,
        sum_2way/count_trials, (sum_2way*10/count_trials)%10,
        mode_count[0], mode_count[1], mode_count[2]);
    end
    $display("TRISTATE_N64_SWEEP_DONE");
    $finish;
  end
endmodule
