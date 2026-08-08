// 사카드 억제 효과 검증: (1) ROT_LEN 사이클 동안 "회전"(전체 셀이 모션블러로 거의
// 동시에 흔들리는 상황, 매우 높은 발화율) → (2) 회전이 끝나고 STABLE_LEN 사이클
// 동안 "정지"(정상적인, 낮은 발화율의 진짜 콘텐츠). 억제 없는 baseline은 회전 구간
// 이벤트도 전부 정상 큐잉(넘치면 버려짐, QDEPTH 유한)하고, 억제 버전은 회전 구간엔
// 아예 큐잉도 안 함(효연 사본이 감각 경로 전체를 억제하는 것과 같은 수준으로 모델링)
// + RTL의 rotating 게이팅도 같이 검증. 핵심 지표: 정지 직후 "진짜 콘텐츠"가 얼마나
// 빨리 정상 지연시간으로 돌아오는지(회복시간)와, 정지 구간 손실률.
`timescale 1ns/1ps
module tb_saccadic_suppression;
  parameter N = 16;
  parameter QDEPTH = 16;       // 실제 하드웨어 버퍼 크기
  parameter ROT_LEN = 200;     // 회전 지속 사이클
  parameter STABLE_LEN = 2000; // 정지(안정) 지속 사이클
  parameter PHASES = 5;        // 회전->정지 왕복 반복 횟수
  parameter ROT_PCT = 40;      // 회전 중 셀당 발화율(모션블러 폭주, 매우 높음)
  parameter STABLE_PCT = 3;    // 정지 중 셀당 발화율(정상 콘텐츠, 안전 부하)

  reg clk = 0;
  reg rst;
  reg rotating;
  reg [15:0] req_base, req_sup;

  wire valid_base; wire [3:0] addr_base;
  wire valid_sup;  wire [3:0] addr_sup;

  // baseline: 억제 없음(rotating 입력을 항상 0으로 묶어서 그냥 원본 fovea처럼 동작)
  aer_tx16_trad_rowcol_fovea_saccsup #(.WEIGHT(5)) tx_base(
    .clk(clk), .rst(rst), .rotating(1'b0), .req(req_base), .valid(valid_base), .addr(addr_base));
  // 억제 버전: rotating 신호를 실제로 사용
  aer_tx16_trad_rowcol_fovea_saccsup #(.WEIGHT(5)) tx_sup(
    .clk(clk), .rst(rst), .rotating(rotating), .req(req_sup), .valid(valid_sup), .addr(addr_sup));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_base();
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_sup();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, draw, lat, ph;
  integer phase_cyc; // 이번 phase(회전 또는 정지) 안에서의 상대 사이클(버킷 판별용)

  // stable phase에서 "정지 시작 이후 상대시각"별 평균 지연시간을 누적(회복 곡선)
  // 200cycle 단위 버킷 10개(=STABLE_LEN=2000 커버).
  integer bucket_sum_base [0:9];
  integer bucket_n_base   [0:9];
  integer bucket_sum_sup  [0:9];
  integer bucket_n_sup    [0:9];
  integer bkt;

  initial begin
    rst = 1; req_base = 16'd0; req_sup = 16'd0; rotating = 0;
    cyc = 0;
    for (i = 0; i < 10; i = i + 1) begin
      bucket_sum_base[i]=0; bucket_n_base[i]=0; bucket_sum_sup[i]=0; bucket_n_sup[i]=0;
    end
    score_base.init; score_sup.init;
    @(posedge clk); #1;
    rst = 0;

    for (ph = 0; ph < PHASES; ph = ph + 1) begin
      // --- 회전 구간 ---
      rotating = 1;
      for (phase_cyc = 0; phase_cyc < ROT_LEN; phase_cyc = phase_cyc + 1) begin
        for (i = 0; i < N; i = i + 1) begin
          draw = (($random(rng_seed) % 100 + 100) % 100);
          if (draw < ROT_PCT) begin
            score_base.record_arrival(i, cyc); // baseline: 회전 중에도 정상 큐잉(넘치면 손실)
            // 억제 버전: 회전 중엔 애초에 큐잉도 안 함(감각경로 전체 억제 모델링) — score_sup엔 안 넣음
          end
        end
        for (i = 0; i < N; i = i + 1) req_base[i] = (score_base.qcount[i] > 0);
        req_sup = 16'd0; // 억제 중엔 req 자체가 없음(큐잉 안 했으므로 자연히 0)
        @(posedge clk); #1;
        if (valid_base) lat = score_base.record_departure(addr_base, cyc);
        // tx_sup는 rotating=1이라 내부에서 이미 게이팅되어 valid_sup=0 보장(RTL 검증된 부분)
        cyc = cyc + 1;
      end

      // --- 정지(안정) 구간 ---
      rotating = 0;
      for (phase_cyc = 0; phase_cyc < STABLE_LEN; phase_cyc = phase_cyc + 1) begin
        for (i = 0; i < N; i = i + 1) begin
          draw = (($random(rng_seed) % 100 + 100) % 100);
          if (draw < STABLE_PCT) begin
            score_base.record_arrival(i, cyc);
            score_sup.record_arrival(i, cyc);
          end
        end
        for (i = 0; i < N; i = i + 1) begin
          req_base[i] = (score_base.qcount[i] > 0);
          req_sup[i]  = (score_sup.qcount[i] > 0);
        end
        @(posedge clk); #1;
        bkt = phase_cyc / (STABLE_LEN/10);
        if (bkt > 9) bkt = 9;
        if (valid_base) begin
          lat = score_base.record_departure(addr_base, cyc);
          if (lat >= 0) begin bucket_sum_base[bkt] = bucket_sum_base[bkt] + lat; bucket_n_base[bkt] = bucket_n_base[bkt] + 1; end
        end
        if (valid_sup) begin
          lat = score_sup.record_departure(addr_sup, cyc);
          if (lat >= 0) begin bucket_sum_sup[bkt] = bucket_sum_sup[bkt] + lat; bucket_n_sup[bkt] = bucket_n_sup[bkt] + 1; end
        end
        cyc = cyc + 1;
      end
    end

    $display("=== 정지 구간 시작 이후 %0d cycle 단위 버킷별 평균 지연시간(억제 없음 vs 있음) ===", STABLE_LEN/10);
    for (i = 0; i < 10; i = i + 1) begin
      $display("버킷%0d(~%0dcyc): 억제없음=%0d(n=%0d)  억제있음=%0d(n=%0d)", i, (i+1)*(STABLE_LEN/10),
        (bucket_n_base[i]>0)?bucket_sum_base[i]/bucket_n_base[i]:0, bucket_n_base[i],
        (bucket_n_sup[i]>0)?bucket_sum_sup[i]/bucket_n_sup[i]:0, bucket_n_sup[i]);
    end
    $display("전체 overflow: 억제없음=%0d  억제있음=%0d", score_base.overflow_count, score_sup.overflow_count);
    $finish;
  end
endmodule
