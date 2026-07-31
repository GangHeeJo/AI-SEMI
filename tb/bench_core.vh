// 공용 성능 측정 하니스 코어. `DUT 매크로로 지정된 중재기 모듈을 측정한다.
// tb_bench_*.v 래퍼가 `define DUT <모듈명> 한 뒤 이 파일을 `include 해서 쓴다.
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

  always #5 clk = ~clk;

  // 요청자별 대기 이벤트 큐(도착 사이클을 기록해두는 FIFO)
  integer queue [0:N-1][0:QDEPTH-1];
  integer qhead [0:N-1];
  integer qcount [0:N-1];

  integer cyc, i, latency;
  integer total_latency [0:N-1];
  integer max_latency   [0:N-1];
  integer grant_count   [0:N-1];
  integer total_grants;
  integer overflow_warns;

  function integer group_of(input integer idx);
    group_of = (idx < 2) ? 0 : 1; // 0=center, 1=periphery
  endfunction

  initial begin
    rst = 1; req = 0; total_grants = 0; overflow_warns = 0;
    for (i = 0; i < N; i = i + 1) begin
      qhead[i] = 0; qcount[i] = 0;
      total_latency[i] = 0; max_latency[i] = 0; grant_count[i] = 0;
    end
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      // 랜덤 이벤트 도착
      for (i = 0; i < N; i = i + 1) begin
        if (($urandom % 100) < ARRIVAL_PCT) begin
          if (qcount[i] < QDEPTH) begin
            queue[i][(qhead[i] + qcount[i]) % QDEPTH] = cyc;
            qcount[i] = qcount[i] + 1;
          end else begin
            overflow_warns = overflow_warns + 1;
          end
        end
      end

      for (i = 0; i < N; i = i + 1) req[i] = (qcount[i] > 0);

      @(posedge clk); #1;

      for (i = 0; i < N; i = i + 1) begin
        if (gnt[i]) begin
          latency = cyc - queue[i][qhead[i]];
          total_latency[i] = total_latency[i] + latency;
          if (latency > max_latency[i]) max_latency[i] = latency;
          grant_count[i] = grant_count[i] + 1;
          total_grants = total_grants + 1;
          qhead[i] = (qhead[i] + 1) % QDEPTH;
          qcount[i] = qcount[i] - 1;
        end
      end
    end

    print_report;
    $finish;
  end

  task print_report;
    integer sum_lat, max_lat_all, min_gc, max_gc;
    integer g_sum_lat [0:1], g_sum_grants [0:1];
    begin
      sum_lat = 0; max_lat_all = 0; min_gc = grant_count[0]; max_gc = grant_count[0];
      g_sum_lat[0] = 0; g_sum_lat[1] = 0; g_sum_grants[0] = 0; g_sum_grants[1] = 0;
      for (i = 0; i < N; i = i + 1) begin
        sum_lat = sum_lat + total_latency[i];
        if (max_latency[i] > max_lat_all) max_lat_all = max_latency[i];
        if (grant_count[i] < min_gc) min_gc = grant_count[i];
        if (grant_count[i] > max_gc) max_gc = grant_count[i];
        g_sum_lat[group_of(i)]    = g_sum_lat[group_of(i)] + total_latency[i];
        g_sum_grants[group_of(i)] = g_sum_grants[group_of(i)] + grant_count[i];
      end

      $display("=== BENCH REPORT [%s] (CYCLES=%0d, ARRIVAL_PCT=%0d%%) ===", `DUT_NAME, CYCLES, ARRIVAL_PCT);
      $display("[1] 평균 지연시간: %0d cycles (total_grants=%0d)", (total_grants>0)?sum_lat / total_grants:0, total_grants);
      $display("[2] 최악 지연시간: %0d cycles", max_lat_all);
      $display("[3] 공정성 (grant count per requester): ");
      for (i = 0; i < N; i = i + 1)
        $display("     req%0d (group=%0d): %0d grants, avg latency %0d", i, group_of(i), grant_count[i], (grant_count[i] > 0) ? total_latency[i]/grant_count[i] : 0);
      $display("     max-min grant 차이: %0d", max_gc - min_gc);
      $display("[4] 처리량: %0d grants / %0d cycles = %0d.%0d grants per 100cycles", total_grants, CYCLES, (total_grants*100)/CYCLES, ((total_grants*10000)/CYCLES)%100);
      $display("[5] 그룹간 평균 지연시간: center(0,1)=%0d cycles, periphery(2,3)=%0d cycles",
        (g_sum_grants[0] > 0) ? g_sum_lat[0]/g_sum_grants[0] : 0,
        (g_sum_grants[1] > 0) ? g_sum_lat[1]/g_sum_grants[1] : 0);
      if (overflow_warns > 0)
        $display("WARNING: 큐 오버플로우 %0d회 발생 (ARRIVAL_PCT를 낮추거나 QDEPTH를 늘리세요)", overflow_warns);
    end
  endtask
endmodule
