// true_traditional(trad_rowcol) vs trad_rowcol_fovea 핫스팟 비교 — burst 없이도
// 중심와(fovea) 가중치 효과가 살아있는지 확인. 배경(BG_PCT)은 낮게, hotspot 4셀만
// 높게(HOT_PCT) 발화시켜 중심/모서리 위치별 hotspot 평균지연을 비교한다.
`timescale 1ns/1ps
module tb_trad_rowcol_fovea_hotspot;
  `ifndef WEIGHT_VAL
  `define WEIGHT_VAL 3
  `endif
  parameter N = 16;
  parameter CYCLES = 3000;
  parameter QDEPTH = 64;
  parameter BG_PCT  = 3;
  parameter HOT_PCT = 50;

  reg clk = 0;
  reg rst;
  reg [15:0] req_base;
  reg [15:0] req_fov;

  wire base_valid; wire [3:0] base_addr;
  wire fov_valid;  wire [3:0] fov_addr;

  aer_tx16_trad_rowcol base_tx(.clk(clk), .rst(rst), .req(req_base), .valid(base_valid), .addr(base_addr));
  aer_tx16_trad_rowcol_fovea #(.WEIGHT(`WEIGHT_VAL)) fov_tx(.clk(clk), .rst(rst), .req(req_fov), .valid(fov_valid), .addr(fov_addr));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) base_score();
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) fov_score();

  always #5 clk = ~clk;

  integer rng_seed = 1;

  function is_hotspot(input integer idx_);
`ifdef HOTSPOT_CORNER_SET
    is_hotspot = (idx_==0 || idx_==3 || idx_==12 || idx_==15); // 네 모서리
`else
    is_hotspot = (idx_==5 || idx_==6 || idx_==9 || idx_==10); // 중심 2x2 (기본값)
`endif
  endfunction

  integer cyc, i, lat_b, lat_f, idx;
  integer b_hot_sum, b_hot_n, b_hot_max, b_bg_sum, b_bg_n;
  integer f_hot_sum, f_hot_n, f_hot_max, f_bg_sum, f_bg_n;
  integer phantom_b, phantom_f;
  integer draw;
  integer center_sel_count, periph_sel_count;

  always @(posedge clk) begin
    if (!rst) begin
      if (fov_tx.use_center) center_sel_count <= center_sel_count + 1;
      if (fov_tx.use_periph) periph_sel_count <= periph_sel_count + 1;
    end
  end

  initial begin
    rst = 1; req_base = 16'd0; req_fov = 16'd0;
    b_hot_sum=0; b_hot_n=0; b_hot_max=0; b_bg_sum=0; b_bg_n=0;
    f_hot_sum=0; f_hot_n=0; f_hot_max=0; f_bg_sum=0; f_bg_n=0;
    phantom_b=0; phantom_f=0;
    center_sel_count=0; periph_sel_count=0;
    base_score.init; fov_score.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < N; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < (is_hotspot(i) ? HOT_PCT : BG_PCT)) begin
          base_score.record_arrival(i, cyc);
          fov_score.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < N; i = i + 1) begin
        req_base[i] = (base_score.qcount[i] > 0);
        req_fov[i]  = (fov_score.qcount[i] > 0);
      end

      @(posedge clk); #1;

      if (base_valid) begin
        idx = base_addr;
        lat_b = base_score.record_departure(idx, cyc);
        if (lat_b < 0) phantom_b = phantom_b + 1;
        if (lat_b >= 0) begin
          if (is_hotspot(idx)) begin
            b_hot_sum = b_hot_sum + lat_b; b_hot_n = b_hot_n + 1;
            if (lat_b > b_hot_max) b_hot_max = lat_b;
          end else begin
            b_bg_sum = b_bg_sum + lat_b; b_bg_n = b_bg_n + 1;
          end
        end
      end
      if (fov_valid) begin
        idx = fov_addr;
        lat_f = fov_score.record_departure(idx, cyc);
        if (lat_f < 0) phantom_f = phantom_f + 1;
        if (lat_f >= 0) begin
          if (is_hotspot(idx)) begin
            f_hot_sum = f_hot_sum + lat_f; f_hot_n = f_hot_n + 1;
            if (lat_f > f_hot_max) f_hot_max = lat_f;
          end else begin
            f_bg_sum = f_bg_sum + lat_f; f_bg_n = f_bg_n + 1;
          end
        end
      end
    end

    $display("[base/true_traditional] phantom=%0d overflow=%0d hotspot 평균=%0d(최악=%0d,n=%0d) 배경 평균=%0d(n=%0d)",
      phantom_b, base_score.overflow_count, (b_hot_n>0)?b_hot_sum/b_hot_n:0, b_hot_max, b_hot_n, (b_bg_n>0)?b_bg_sum/b_bg_n:0, b_bg_n);
    $display("[fovea, WEIGHT=%0d]        phantom=%0d overflow=%0d hotspot 평균=%0d(최악=%0d,n=%0d) 배경 평균=%0d(n=%0d)",
      `WEIGHT_VAL, phantom_f, fov_score.overflow_count, (f_hot_n>0)?f_hot_sum/f_hot_n:0, f_hot_max, f_hot_n, (f_bg_n>0)?f_bg_sum/f_bg_n:0, f_bg_n);
    $display("[fovea row selection] center=%0d periph=%0d (ratio=%0d.%0d:1)",
      center_sel_count, periph_sel_count,
      (periph_sel_count>0)?center_sel_count/periph_sel_count:0,
      (periph_sel_count>0)?((center_sel_count*10)/periph_sel_count)%10:0);
    $finish;
  end
endmodule
