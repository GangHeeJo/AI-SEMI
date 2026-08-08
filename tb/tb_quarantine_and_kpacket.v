// 두 실험을 한 테스트벤치에서: (A) quarantine buffer 실현성 -- 재발화 충돌이 같은
// 사이클에 몇 개 소스에서 동시에 나는지(멀티라이트포트 필요 여부 판단용), (B) K-패킷
// 생존확률 -- 같은 소스의 연속 K개 이벤트가 중간에 하나도 안 떨어지고 다 살아남을
// 확률(문헌조사가 찾은 "다중패킷 분산 의미의 손실 취약성" gap을 정량화).
//
// cluster2(현재 선두 후보, 버퍼 없음)를 그대로 씀 -- pending은 레벨 신호라 이미
// req[i]=1로 "대기중"을 표현하고 있고, arrival(펄스)이 그 레벨이 1인 상태로 다시
// 오면 재발화 충돌(=드롭)임. 이 판정 자체는 새 회로가 필요 없고 테스트벤치의 shadow
// 모델로 충분(§44부터 쓰던 패턴 그대로).
`timescale 1ns/1ps
module tb_quarantine_and_kpacket;
  parameter N = 16;
  parameter CYCLES = 50000;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  reg [15:0] req; // cluster2에 실제로 먹이는 레벨 신호(=pending)
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2 dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;

  integer rng_seed = 21;
  integer cyc, i, c, draw, idx, collide_this_cycle;

  reg pending [0:15];

  // (A) quarantine 동시충돌 히스토그램: 한 사이클에 충돌(arrival & pending)한 소스 수 분포
  integer collide_hist [0:16]; // collide_hist[k] = "이번 사이클 k개 소스 동시충돌"이었던 사이클 수
  integer total_collisions;    // 전체 충돌 이벤트 수(=드롭되는 이벤트 총수)

  // (B) K-패킷 생존확률: 소스별 "최근 시도 K번(성공/실패 무관) 슬라이딩 윈도우가 전부
  // 성공이었는가"를 직접 셈 -- 스트릭 방식(연속 성공 길이)이 아니라 매 시도마다
  // "최근 K개 시도"를 갱신하는 진짜 슬라이딩 윈도우.
  parameter KMAX = 4;
  reg outcome_hist [0:15][0:KMAX-1]; // 소스별 최근 KMAX개 시도의 성공(1)/드롭(0) 기록
  integer attempt_cnt [0:15];        // 소스별 총 시도 횟수(윈도우가 찼는지 판단용)
  integer window_total [2:KMAX];     // K별 시행 수(그 시점까지 시도 K번 이상 쌓인 경우만)
  integer window_survive [2:KMAX];   // K별 "최근 K개 전부 성공"이었던 횟수

  initial begin
    rst = 1; arrival = 16'd0; req = 16'd0;
    total_collisions = 0;
    for (i = 0; i <= 16; i = i + 1) collide_hist[i] = 0;
    for (i = 0; i < 16; i = i + 1) begin
      pending[i] = 1'b0; attempt_cnt[i] = 0;
      for (c = 0; c < KMAX; c = c + 1) outcome_hist[i][c] = 1'b0;
    end
    for (i = 2; i <= KMAX; i = i + 1) begin window_total[i] = 0; window_survive[i] = 0; end
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      arrival = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < ARRIVAL_PCT) arrival[i] = 1'b1;
      end

      // 이번 사이클 충돌(재발화 드롭) 판정: arrival[i] && pending[i].
      collide_this_cycle = 0;
      for (i = 0; i < 16; i = i + 1) begin
        if (arrival[i] && pending[i]) begin
          collide_this_cycle = collide_this_cycle + 1;
        end
      end
      collide_hist[collide_this_cycle] = collide_hist[collide_this_cycle] + 1;
      total_collisions = total_collisions + collide_this_cycle;

      // K-패킷 생존: 이번 시도의 성공/드롭을 소스별 최근 KMAX개 슬라이딩 윈도우에 기록.
      for (i = 0; i < 16; i = i + 1) begin
        if (arrival[i]) begin
          for (c = KMAX - 1; c > 0; c = c - 1) outcome_hist[i][c] = outcome_hist[i][c-1];
          if (pending[i]) begin
            outcome_hist[i][0] = 1'b0; // 드롭
          end else begin
            pending[i] = 1'b1;
            outcome_hist[i][0] = 1'b1; // 성공
          end
          attempt_cnt[i] = attempt_cnt[i] + 1;
          if (attempt_cnt[i] >= 2) begin
            for (c = 2; c <= KMAX; c = c + 1) begin
              if (attempt_cnt[i] >= c) begin
                window_total[c] = window_total[c] + 1;
                if (window_all_ok(i, c)) window_survive[c] = window_survive[c] + 1;
              end
            end
          end
        end
      end

      req = pending_bits(1'b0);

      @(posedge clk); #1;

      // grant된 소스는 pending 해제(다음 사이클부터 재발화해도 충돌 아님).
      if (valid0) begin
        for (c = 0; c < 4; c = c + 1)
          if (col_mask0[c]) pending[row0*4+c] = 1'b0;
      end
      if (valid1) begin
        for (c = 0; c < 4; c = c + 1)
          if (col_mask1[c]) pending[row1*4+c] = 1'b0;
      end
    end

    $display("=== (A) Quarantine 동시충돌 히스토그램(총 %0d cycles, 충돌 총 %0d건) ===", CYCLES, total_collisions);
    for (i = 0; i <= 4; i = i + 1)
      $display("  %0d개 소스 동시충돌: %0d cycles (%0d.%0d%%)", i, collide_hist[i],
        (collide_hist[i]*100)/CYCLES, (collide_hist[i]*1000/CYCLES)%10);
    $display("  (5개 이상 동시충돌 총합: %0d cycles)",
      CYCLES - collide_hist[0] - collide_hist[1] - collide_hist[2] - collide_hist[3] - collide_hist[4]);

    $display("=== (B) K-패킷 생존확률 ===");
    for (c = 2; c <= KMAX; c = c + 1) begin
      $display("  K=%0d: 시행 %0d건 중 %0d건 생존 (%0d.%0d%%)", c, window_total[c], window_survive[c],
        (window_survive[c]*100)/window_total[c], (window_survive[c]*1000/window_total[c])%10);
    end

    $display("KPACKET_QUARANTINE_DONE");
    $finish;
  end

  function window_all_ok;
    input integer src;
    input integer k;
    integer j;
    begin
      window_all_ok = 1'b1;
      for (j = 0; j < k; j = j + 1)
        if (!outcome_hist[src][j]) window_all_ok = 1'b0;
    end
  endfunction

  function [15:0] pending_bits;
    input dummy;
    integer k;
    begin
      pending_bits = 16'd0;
      for (k = 0; k < 16; k = k + 1) pending_bits[k] = pending[k];
    end
  endfunction
endmodule
