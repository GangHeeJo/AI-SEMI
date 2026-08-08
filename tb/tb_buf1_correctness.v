// cluster_buf1(1-deep) 일반 정확성 검증 -- tb_buf_correctness.v와 동일 구조,
// shadow 최대값만 2->1로 낮춤(1-deep이므로).
`timescale 1ns/1ps
module tb_buf1_correctness;
  parameter N = 16;
  parameter CYCLES = 20000;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid; wire [1:0] row; wire [3:0] col_mask;

  aer_tx16_trad_rowcol_fovea_cluster_buf1 #(.WEIGHT(5)) dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid(valid), .row(row), .col_mask(col_mask));

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, c, draw, idx;
  integer generated, delivered, dropped_overrun, phantom_count, error_count;

  reg shadow_cnt [0:15]; // 회로랑 별개로 직접 계산한 "진짜 있어야 할" 상태(0/1)

  initial begin
    rst = 1; arrival = 16'd0;
    generated = 0; delivered = 0; dropped_overrun = 0; phantom_count = 0; error_count = 0;
    for (i = 0; i < 16; i = i + 1) shadow_cnt[i] = 1'b0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      arrival = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < ARRIVAL_PCT) begin
          generated = generated + 1;
          arrival[i] = 1'b1;
        end
      end
      #1;
      for (i = 0; i < 16; i = i + 1) begin
        if (overrun_w[i]) begin
          dropped_overrun = dropped_overrun + 1;
          if (shadow_cnt[i] != 1'b1) begin
            error_count = error_count + 1;
            $display("BAD_OVERRUN_REPORT src=%0d shadow=%0d cyc=%0d", i, shadow_cnt[i], cyc);
          end
        end
      end

      @(posedge clk); #1;

      if (valid) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask[c]) begin
            idx = row*4 + c;
            if (shadow_cnt[idx] == 1'b0) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
              $display("PHANTOM src=%0d cyc=%0d", idx, cyc);
            end else begin
              delivered = delivered + 1;
            end
          end
        end
      end

      for (i = 0; i < 16; i = i + 1) begin
        if (arrival[i] && (shadow_cnt[i] != 1'b1))
          shadow_cnt[i] = 1'b1;
      end
      if (valid) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask[c]) begin
            idx = row*4 + c;
            if (shadow_cnt[idx] != 1'b0) shadow_cnt[idx] = 1'b0;
          end
        end
      end
    end

    arrival = 16'd0;
    for (cyc = CYCLES; cyc < CYCLES + 100; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (valid) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask[c]) begin
            idx = row*4 + c;
            if (shadow_cnt[idx] == 1'b0) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
            end else begin
              delivered = delivered + 1;
              shadow_cnt[idx] = 1'b0;
            end
          end
        end
      end
    end

    $display("generated=%0d delivered=%0d dropped_overrun=%0d phantom=%0d",
      generated, delivered, dropped_overrun, phantom_count);
    if ((delivered + dropped_overrun) != generated) begin
      error_count = error_count + 1;
      $display("COUNT_MISMATCH delivered+dropped=%0d generated=%0d", delivered+dropped_overrun, generated);
    end

    if (error_count == 0) $display("CLUSTER_BUF1_CORRECTNESS_PASS");
    else $display("CLUSTER_BUF1_CORRECTNESS_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
