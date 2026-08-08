// 각 행(row)이 실제로 몇 사이클 간격으로 선택되는지 측정 — 중심행(1,2) vs 주변행(0,3)의
// 방문 간격 평균/분산을 구해서, E[W]=E[T]/2 + Var(T)/(2E[T]) 공식을 검증하기 위한 도구.
// 여기선 이벤트별 지연시간이 아니라 "행 방문 간격"만 필요해서 event_scoreboard의
// 도착-큐(오버플로우 방지) 기능만 재사용하고, 방문 시 그 행 큐를 통째로 비우는 단순화는
// 그대로 유지함(원래 aer_rx16 없이 이 파일만으로 동작시키기 위한 단순화).
module tb_gap_measure;
  `ifndef SEED_VAL
  `define SEED_VAL 1
  `endif
  parameter CYCLES = 20000;
  parameter QDEPTH = 64;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire       valid, addr_type;
  wire [1:0] addr;

  `TX tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr));

  event_scoreboard #(.N(16), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer rng_seed;
  integer cyc, i;

  // 행별 마지막 방문 시각 및 간격 통계 (sum, sum of squares, count)
  integer last_visit [0:3];
  real    gap_sum   [0:3];
  real    gap_sumsq [0:3];
  integer gap_count [0:3];

  initial begin
    rng_seed = `SEED_VAL;
    rst = 1; req = 16'd0;
    score.init;
    for (i = 0; i < 4; i = i + 1) begin last_visit[i] = -1; gap_sum[i]=0.0; gap_sumsq[i]=0.0; gap_count[i]=0; end
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < 16; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < ARRIVAL_PCT) begin
          score.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < 16; i = i + 1) req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      if (valid && addr_type == 1'b0) begin // ROW 패킷 = 이 행이 지금 막 선택됨
        if (last_visit[addr] >= 0) begin
          gap_sum[addr]   = gap_sum[addr]   + (cyc - last_visit[addr]);
          gap_sumsq[addr] = gap_sumsq[addr] + (cyc - last_visit[addr]) * (cyc - last_visit[addr]);
          gap_count[addr] = gap_count[addr] + 1;
        end
        last_visit[addr] = cyc;

        // 이벤트가 실제로 서비스됐는지는 여기서 굳이 추적 안 함(행 방문 간격만 필요).
        // 대신 큐가 무한히 안 쌓이도록, 방문 시 해당 행의 열 요청들을 임의로 다 비워준다
        // (실제 burst와 동등한 효과).
        for (i = addr*4; i < addr*4+4; i = i + 1) begin
          score.qhead[i] = 0; score.qcount[i] = 0;
        end
      end
    end

    for (i = 0; i < 4; i = i + 1) begin
      if (gap_count[i] > 0) begin
        $display("row%0d: visits=%0d, mean_gap=%f, var_gap=%f", i, gap_count[i],
          gap_sum[i]/gap_count[i],
          (gap_sumsq[i]/gap_count[i]) - (gap_sum[i]/gap_count[i])*(gap_sum[i]/gap_count[i]));
      end
    end
    if (score.overflow_count > 0)
      $display("WARNING: 큐 오버플로우 %0d회 — row visit 사이 한 셀에 64개 넘게 밀림, gap 측정 전제(방문마다 리셋)가 깨졌을 수 있음", score.overflow_count);
    $finish;
  end
endmodule
