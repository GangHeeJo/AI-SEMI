// §77의 정확히 같은 부하모델(단일슬롯 admission, 2000사이클, 동일 부하점)로 진짜
// N=64 RTL(aer_tx64_cluster2_tree4, 리프 cluster2 4개)의 손실을 §77이 보고한 "고정
// 8개/cycle" 동작모델 기준선(N=64, 100%부하 overrun=111,944)과 직접 비교.
`timescale 1ns/1ps
module tb_cluster2_tree4_n64_scale;
  parameter N = 64;

  reg clk = 0;
  reg rst;
  reg [N-1:0] req;
  wire [3:0] valid0, valid1;
  wire [7:0] row0_flat, row1_flat;
  wire [15:0] col_mask0_flat, col_mask1_flat;

  aer_tx64_cluster2_tree4 dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0), .row0_flat(row0_flat), .col_mask0_flat(col_mask0_flat),
    .valid1(valid1), .row1_flat(row1_flat), .col_mask1_flat(col_mask1_flat));

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, s, g, c, idx;
  reg [N-1:0] pending;
  integer generated, delivered, overrun;

  task automatic run_load_point;
    input integer bg_pct;
    input integer total_cyc;
    integer draw;
    begin
      generated = 0; delivered = 0; overrun = 0;
      pending = {N{1'b0}};
      req = {N{1'b0}};
      for (cyc = 0; cyc < total_cyc; cyc = cyc + 1) begin
        for (s = 0; s < N; s = s + 1) begin
          draw = (($random(rng_seed) % 100 + 100) % 100);
          if (draw < bg_pct) begin
            if (!pending[s]) begin generated = generated + 1; pending[s] = 1'b1; end
            else overrun = overrun + 1;
          end
        end
        req = pending;
        @(posedge clk); #1;
        for (g = 0; g < 4; g = g + 1) begin
          if (valid0[g]) begin
            for (c = 0; c < 4; c = c + 1) begin
              if (col_mask0_flat[g*4+c]) begin
                idx = g*16 + row0_flat[g*2 +: 2]*4 + c;
                if (pending[idx]) begin pending[idx] = 1'b0; delivered = delivered + 1; end
              end
            end
          end
          if (valid1[g]) begin
            for (c = 0; c < 4; c = c + 1) begin
              if (col_mask1_flat[g*4+c]) begin
                idx = g*16 + row1_flat[g*2 +: 2]*4 + c;
                if (pending[idx]) begin pending[idx] = 1'b0; delivered = delivered + 1; end
              end
            end
          end
        end
      end
      $display("N=%0d LOAD=%0d%% TREE4: gen=%0d del=%0d overrun=%0d", N, bg_pct, generated, delivered, overrun);
    end
  endtask

  initial begin
    rst = 1; req = {N{1'b0}};
    @(posedge clk); #1; rst = 0;
    run_load_point(3, 2000);
    run_load_point(15, 2000);
    run_load_point(30, 2000);
    run_load_point(50, 2000);
    run_load_point(75, 2000);
    run_load_point(100, 2000);
    $display("TREE4_N64_SCALE_DONE");
    $finish;
  end
endmodule
