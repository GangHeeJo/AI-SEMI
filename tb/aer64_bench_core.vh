// aer_tx64 계열 공용 성능 측정 코어 (8x8=64셀). `TX / `TX_NAME 매크로로 송신기 지정.
// 큐/지연시간/공정성 추적은 event_scoreboard(공용 채점기)로 통일함.
module tb_aer64_bench;
  `ifndef SEED_VAL
  `define SEED_VAL 1
  `endif
  `ifndef ARRIVAL_PCT_VAL
  `define ARRIVAL_PCT_VAL 3
  `endif
  parameter N = 64;
  parameter CYCLES = 6000;
  parameter QDEPTH = 64;
  parameter ARRIVAL_PCT = `ARRIVAL_PCT_VAL;

  reg clk = 0;
  reg rst;
  reg [63:0] req;
  wire       valid, addr_type;
  wire [2:0] addr;
  wire       event_valid;
  wire [2:0] event_row, event_col;

  integer rng_seed = `SEED_VAL;

  `ifndef TX_PARAMS
  `define TX_PARAMS
  `endif
  `TX `TX_PARAMS tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx64 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer cyc, i, latency, idx;
  integer phantom_errors;

  // 8x8에서 가운데 4x4(row,col 둘다 2~5)를 "center", 나머지를 "periphery"로
  function integer group_of(input integer idx_);
    integer r, c;
    begin
      r = idx_ / 8; c = idx_ % 8;
      group_of = (r >= 2 && r <= 5 && c >= 2 && c <= 5) ? 0 : 1;
    end
  endfunction

  initial begin
    rst = 1; req = 64'd0; phantom_errors = 0;
    score.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < N; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < ARRIVAL_PCT) begin
          score.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < N; i = i + 1) req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      if (event_valid) begin
        idx = event_row*8 + event_col;
        latency = score.record_departure(idx, cyc);
        if (latency < 0) begin
          $display("PHANTOM ERROR: cycle=%0d row=%0d col=%0d 인데 대기 이벤트가 없었음", cyc, event_row, event_col);
          phantom_errors = phantom_errors + 1;
        end
      end
    end

    print_report;
    if (phantom_errors > 0)
      $display("=== 검증 실패: phantom 이벤트 %0d건 발생 ===", phantom_errors);
    else
      $display("=== 검증 통과: %0d 사이클 동안 phantom/오류 이벤트 0건 ===", CYCLES);
    $finish;
  end

  task print_report;
    integer g_sum_lat [0:1], g_sum_grants [0:1];
    integer min_gc, max_gc;
    begin
      g_sum_lat[0]=0; g_sum_lat[1]=0; g_sum_grants[0]=0; g_sum_grants[1]=0;
      min_gc = score.visits[0]; max_gc = score.visits[0];
      for (i = 0; i < N; i = i + 1) begin
        g_sum_lat[group_of(i)] = g_sum_lat[group_of(i)] + score.lat_sum_by_idx[i];
        g_sum_grants[group_of(i)] = g_sum_grants[group_of(i)] + score.visits[i];
        if (score.visits[i] < min_gc) min_gc = score.visits[i];
        if (score.visits[i] > max_gc) max_gc = score.visits[i];
      end
      $display("=== AER64[%s] BENCH REPORT (CYCLES=%0d, ARRIVAL_PCT=%0d%%) ===", `TX_NAME, CYCLES, ARRIVAL_PCT);
      $display("[1] 평균 지연시간: %0d cycles (total_grants=%0d)", score.avg_latency(0), score.count);
      $display("[2] 최악 지연시간: %0d cycles", score.max_lat);
      $display("[3] 공정성: max-min grant 차이 = %0d (min=%0d, max=%0d), Jain fairness index = %0d/1000", max_gc-min_gc, min_gc, max_gc, score.jain_fairness_x1000(0));
      $display("[4] 처리량: %0d grants / %0d cycles = %0d.%0d grants per 100cycles", score.count, CYCLES, (score.count*100)/CYCLES, ((score.count*10000)/CYCLES)%100);
      $display("[5] 그룹간 평균 지연시간: center(4x4)=%0d cycles, periphery=%0d cycles",
        (g_sum_grants[0]>0)?g_sum_lat[0]/g_sum_grants[0]:0,
        (g_sum_grants[1]>0)?g_sum_lat[1]/g_sum_grants[1]:0);
      if (score.overflow_count > 0)
        $display("WARNING: 큐 오버플로우 %0d회", score.overflow_count);
    end
  endtask
endmodule
