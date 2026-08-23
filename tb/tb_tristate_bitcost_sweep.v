// 3단 적응형(raw/EF/bitmap) vs 2단(raw/EF만, 준영 a6 원본) vs bitmap단독 비교.
`timescale 1ns/1ps
module tb_tristate_bitcost_sweep;
  parameter MAX_BATCH = 16;
  parameter ADDRESS_WIDTH = 4;
  parameter COUNT_WIDTH = 5;

  reg [COUNT_WIDTH-1:0] batch_count;
  reg [MAX_BATCH*ADDRESS_WIDTH-1:0] batch_sources;
  wire [1:0] mode_out;
  wire [31:0] total_bits_out;
  wire input_error;
  wire [31:0] raw_bits_dbg, ef_bits_dbg;

  a6_tristate_raw_ef_bitmap dut(
    .batch_count(batch_count), .batch_sources(batch_sources),
    .mode_out(mode_out), .total_bits_out(total_bits_out), .input_error(input_error),
    .raw_bits_dbg(raw_bits_dbg), .ef_bits_dbg(ef_bits_dbg));

  integer rng_seed = 11;
  integer trial, k, s, tries, n_sorted, idx, draw;
  reg [15:0] chosen;
  integer sorted_list [0:15];
  integer sum_tri, sum_bitmap_only, sum_2way, count_trials;
  integer mode_count [0:2];

  task automatic build_batch;
    input integer kcount;
    begin
      chosen = 16'd0; n_sorted = 0; tries = 0;
      while (n_sorted < kcount && tries < 1000) begin
        draw = (($random(rng_seed) % 16 + 16) % 16);
        if (!chosen[draw]) begin chosen[draw]=1'b1; n_sorted=n_sorted+1; end
        tries = tries + 1;
      end
      idx = 0;
      for (s = 0; s < 16; s = s + 1)
        if (chosen[s]) begin sorted_list[idx] = s; idx = idx + 1; end
      batch_count = kcount;
      batch_sources = {(MAX_BATCH*ADDRESS_WIDTH){1'b0}};
      for (s = 0; s < kcount; s = s + 1)
        batch_sources[s*ADDRESS_WIDTH +: ADDRESS_WIDTH] = sorted_list[s][3:0];
    end
  endtask

  integer raw_len, ef_len_2way, two_way_bits;

  initial begin
    for (k = 1; k <= 16; k = k * 2) begin
      sum_tri = 0; sum_bitmap_only = 0; sum_2way = 0; count_trials = 0;
      mode_count[0]=0; mode_count[1]=0; mode_count[2]=0;
      for (trial = 0; trial < 30; trial = trial + 1) begin
        build_batch(k);
        #1;
        if (!input_error) begin
          sum_tri = sum_tri + total_bits_out;
          sum_bitmap_only = sum_bitmap_only + 16;
          // 2단(raw/EF만, bitmap 옵션 없음, 준영 원본과 동등): 둘 중 실제 최소값.
          two_way_bits = (raw_bits_dbg < ef_bits_dbg) ? raw_bits_dbg : ef_bits_dbg;
          sum_2way = sum_2way + two_way_bits;
          mode_count[mode_out] = mode_count[mode_out] + 1;
          count_trials = count_trials + 1;
        end
      end
      $display("K=%0d tristate_avg=%0d.%0d bitmap_only_avg=%0d 2way(raw/EF-cap)_avg=%0d.%0d modes(raw=%0d,ef=%0d,bitmap=%0d)",
        k, sum_tri/count_trials, (sum_tri*10/count_trials)%10,
        sum_bitmap_only/count_trials,
        sum_2way/count_trials, (sum_2way*10/count_trials)%10,
        mode_count[0], mode_count[1], mode_count[2]);
    end
    $display("TRISTATE_SWEEP_DONE");
    $finish;
  end
endmodule
