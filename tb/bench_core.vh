// 공용 성능 측정 하니스 코어. `DUT 매크로로 지정된 중재기 모듈을 측정한다.
// tb_bench_*.v 래퍼가 `define DUT <모듈명> 한 뒤 이 파일을 `include 해서 쓴다.
// 큐/지연시간/공정성 추적은 event_scoreboard(공용 채점기)로 통일함.
module tb_bench;
  `ifndef ARRIVAL_PCT_VAL
  `define ARRIVAL_PCT_VAL 30
  `endif
  parameter N = 4;
  parameter CYCLES = 2000;
  parameter QDEPTH = 64;
  parameter ARRIVAL_PCT = `ARRIVAL_PCT_VAL; // 각 요청자가 한 사이클에 새 이벤트를 낼 확률(%) — -D로 오버라이드 가능

  reg clk = 0;
  reg rst;
  reg [N-1:0] req;
  wire [N-1:0] gnt;

  `DUT dut(.clk(clk), .rst(rst), .req(req), .gnt(gnt));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer cyc, i, latency;

  function integer group_of(input integer idx);
    group_of = (idx < 2) ? 0 : 1; // 0=center, 1=periphery
  endfunction

  initial begin
    rst = 1; req = 0;
    score.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      // 랜덤 이벤트 도착
      for (i = 0; i < N; i = i + 1) begin
        if (($urandom % 100) < ARRIVAL_PCT) begin
          score.record_arrival(i, cyc);
        end
      end

      for (i = 0; i < N; i = i + 1) req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      for (i = 0; i < N; i = i + 1) begin
        if (gnt[i]) begin
          latency = score.record_departure(i, cyc);
        end
      end
    end

    print_report;
    $finish;
  end

  task print_report;
    integer g_sum_lat [0:1], g_sum_grants [0:1];
    integer min_gc, max_gc;
    begin
      g_sum_lat[0] = 0; g_sum_lat[1] = 0; g_sum_grants[0] = 0; g_sum_grants[1] = 0;
      min_gc = score.visits[0]; max_gc = score.visits[0];
      for (i = 0; i < N; i = i + 1) begin
        g_sum_lat[group_of(i)]    = g_sum_lat[group_of(i)] + score.lat_sum_by_idx[i];
        g_sum_grants[group_of(i)] = g_sum_grants[group_of(i)] + score.visits[i];
        if (score.visits[i] < min_gc) min_gc = score.visits[i];
        if (score.visits[i] > max_gc) max_gc = score.visits[i];
      end

      $display("=== BENCH REPORT [%s] (CYCLES=%0d, ARRIVAL_PCT=%0d%%) ===", `DUT_NAME, CYCLES, ARRIVAL_PCT);
      $display("[1] 평균 지연시간: %0d cycles (total_grants=%0d)", score.avg_latency(0), score.count);
      $display("[2] 최악 지연시간: %0d cycles", score.max_lat);
      $display("[3] 공정성 (grant count per requester): ");
      for (i = 0; i < N; i = i + 1)
        $display("     req%0d (group=%0d): %0d grants, avg latency %0d", i, group_of(i), score.visits[i], (score.visits[i] > 0) ? score.lat_sum_by_idx[i]/score.visits[i] : 0);
      $display("     max-min grant 차이: %0d, Jain fairness index = %0d/1000", max_gc - min_gc, score.jain_fairness_x1000(0));
      $display("[4] 처리량: %0d grants / %0d cycles = %0d.%0d grants per 100cycles", score.count, CYCLES, (score.count*100)/CYCLES, ((score.count*10000)/CYCLES)%100);
      $display("[5] 그룹간 평균 지연시간: center(0,1)=%0d cycles, periphery(2,3)=%0d cycles",
        (g_sum_grants[0] > 0) ? g_sum_lat[0]/g_sum_grants[0] : 0,
        (g_sum_grants[1] > 0) ? g_sum_lat[1]/g_sum_grants[1] : 0);
      if (score.overflow_count > 0)
        $display("WARNING: 큐 오버플로우 %0d회 발생 (ARRIVAL_PCT를 낮추거나 QDEPTH를 늘리세요)", score.overflow_count);
    end
  endtask
endmodule
