// [실험 A] Temporal Fidelity -- 같은 소스의 연속된 두 이벤트 사이, "원래 발생 간격"과
// "실제 도착 간격"이 얼마나 다른지 측정. event_scoreboard의 record_departure가 이벤트별
// latency를 바로 리턴하므로, 같은 소스의 연속 latency 차이 = ISI 왜곡(수신간격-원래간격)과
// 수학적으로 같음: r2-r1 = (t2+lat2)-(t1+lat1) = (t2-t1)+(lat2-lat1) 이므로
// ISI_error = |수신간격-원래간격| = |lat2-lat1|.
// cluster(1레인) / cluster2(2레인) / cluster2_steal(work-conserving) 세 설계를 같은
// 자극으로 동시에 비교 -- "레인을 늘리면 event를 더 많이 나르는 것"뿐 아니라
// "원래 spike timing도 더 잘 보존하는지"까지 확인하는 게 목적.
`timescale 1ns/1ps
module tb_temporal_fidelity;
  parameter N = 16;
  parameter CYCLES = 20000;
  parameter QDEPTH = 200000;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] req;

  // --- cluster(1레인) ---
  wire valid_a; wire [1:0] row_a; wire [3:0] col_mask_a;
  aer_tx16_trad_rowcol_fovea_cluster #(.WEIGHT(5)) dut_a(
    .clk(clk), .rst(rst), .req(req), .valid(valid_a), .row(row_a), .col_mask(col_mask_a));
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_a();

  // --- cluster2(2레인) ---
  wire valid0_b; wire [1:0] row0_b; wire [3:0] col_mask0_b;
  wire valid1_b; wire [1:0] row1_b; wire [3:0] col_mask1_b;
  aer_tx16_trad_rowcol_fovea_cluster2 dut_b(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_b), .row0(row0_b), .col_mask0(col_mask0_b),
    .valid1(valid1_b), .row1(row1_b), .col_mask1(col_mask1_b));
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_b();

  // --- cluster2_steal ---
  wire valid0_c; wire [1:0] row0_c; wire [3:0] col_mask0_c;
  wire valid1_c; wire [1:0] row1_c; wire [3:0] col_mask1_c;
  aer_tx16_trad_rowcol_fovea_cluster2_steal dut_c(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_c), .row0(row0_c), .col_mask0(col_mask0_c),
    .valid1(valid1_c), .row1(row1_c), .col_mask1(col_mask1_c));
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_c();

  always #5 clk = ~clk;

  integer rng_seed = 5;
  integer cyc, i, c, draw, idx, lat;

  // 소스별 "직전 latency"(ISI 왜곡 계산용) + 누적 통계(설계 3개 각각)
  integer prev_lat_a [0:15]; integer prev_lat_b [0:15]; integer prev_lat_c [0:15];
  integer have_prev_a [0:15]; integer have_prev_b [0:15]; integer have_prev_c [0:15];
  integer isi_err_sum_a, isi_err_cnt_a, isi_err_max_a;
  integer isi_err_sum_b, isi_err_cnt_b, isi_err_max_b;
  integer isi_err_sum_c, isi_err_cnt_c, isi_err_max_c;

  task automatic record_and_track(
    input integer which, // 0=a,1=b,2=c
    input integer idx_in, input integer lat_in);
    integer d;
    begin
      case (which)
        0: begin
          if (have_prev_a[idx_in]) begin
            d = lat_in - prev_lat_a[idx_in];
            if (d < 0) d = -d;
            isi_err_sum_a = isi_err_sum_a + d;
            isi_err_cnt_a = isi_err_cnt_a + 1;
            if (d > isi_err_max_a) isi_err_max_a = d;
          end
          prev_lat_a[idx_in] = lat_in; have_prev_a[idx_in] = 1;
        end
        1: begin
          if (have_prev_b[idx_in]) begin
            d = lat_in - prev_lat_b[idx_in];
            if (d < 0) d = -d;
            isi_err_sum_b = isi_err_sum_b + d;
            isi_err_cnt_b = isi_err_cnt_b + 1;
            if (d > isi_err_max_b) isi_err_max_b = d;
          end
          prev_lat_b[idx_in] = lat_in; have_prev_b[idx_in] = 1;
        end
        2: begin
          if (have_prev_c[idx_in]) begin
            d = lat_in - prev_lat_c[idx_in];
            if (d < 0) d = -d;
            isi_err_sum_c = isi_err_sum_c + d;
            isi_err_cnt_c = isi_err_cnt_c + 1;
            if (d > isi_err_max_c) isi_err_max_c = d;
          end
          prev_lat_c[idx_in] = lat_in; have_prev_c[idx_in] = 1;
        end
      endcase
    end
  endtask

  initial begin
    rst = 1; req = 16'd0;
    isi_err_sum_a = 0; isi_err_cnt_a = 0; isi_err_max_a = 0;
    isi_err_sum_b = 0; isi_err_cnt_b = 0; isi_err_max_b = 0;
    isi_err_sum_c = 0; isi_err_cnt_c = 0; isi_err_max_c = 0;
    for (i = 0; i < 16; i = i + 1) begin
      have_prev_a[i] = 0; have_prev_b[i] = 0; have_prev_c[i] = 0;
    end
    score_a.init; score_b.init; score_c.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < 16; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < ARRIVAL_PCT) begin
          score_a.record_arrival(i, cyc);
          score_b.record_arrival(i, cyc);
          score_c.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < 16; i = i + 1)
        req[i] = (score_a.qcount[i] > 0); // 세 스코어보드가 같은 도착 이력을 공유하므로 a 기준으로 req 생성(동일 자극)

      @(posedge clk); #1;

      // cluster(1레인)
      if (valid_a) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask_a[c]) begin
            idx = row_a*4 + c;
            lat = score_a.record_departure(idx, cyc);
            if (lat >= 0) record_and_track(0, idx, lat);
          end
        end
      end
      // cluster2(2레인)
      if (valid0_b) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask0_b[c]) begin
            idx = row0_b*4 + c;
            lat = score_b.record_departure(idx, cyc);
            if (lat >= 0) record_and_track(1, idx, lat);
          end
        end
      end
      if (valid1_b) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask1_b[c]) begin
            idx = row1_b*4 + c;
            lat = score_b.record_departure(idx, cyc);
            if (lat >= 0) record_and_track(1, idx, lat);
          end
        end
      end
      // cluster2_steal
      if (valid0_c) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask0_c[c]) begin
            idx = row0_c*4 + c;
            lat = score_c.record_departure(idx, cyc);
            if (lat >= 0) record_and_track(2, idx, lat);
          end
        end
      end
      if (valid1_c) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask1_c[c]) begin
            idx = row1_c*4 + c;
            lat = score_c.record_departure(idx, cyc);
            if (lat >= 0) record_and_track(2, idx, lat);
          end
        end
      end
    end

    $display("[cluster   ] avg_latency=%0d max_latency=%0d ISI_MAE=%0d ISI_MAX=%0d (n=%0d)",
      score_a.avg_latency(0), score_a.max_lat,
      (isi_err_cnt_a>0)?(isi_err_sum_a/isi_err_cnt_a):0, isi_err_max_a, isi_err_cnt_a);
    $display("[cluster2  ] avg_latency=%0d max_latency=%0d ISI_MAE=%0d ISI_MAX=%0d (n=%0d)",
      score_b.avg_latency(0), score_b.max_lat,
      (isi_err_cnt_b>0)?(isi_err_sum_b/isi_err_cnt_b):0, isi_err_max_b, isi_err_cnt_b);
    $display("[c2_steal  ] avg_latency=%0d max_latency=%0d ISI_MAE=%0d ISI_MAX=%0d (n=%0d)",
      score_c.avg_latency(0), score_c.max_lat,
      (isi_err_cnt_c>0)?(isi_err_sum_c/isi_err_cnt_c):0, isi_err_max_c, isi_err_cnt_c);
    $display("TEMPORAL_FIDELITY_DONE");
    $finish;
  end
endmodule
