// aer_tx64 계열 공용 성능 측정 코어 (8x8=64셀). `TX / `TX_NAME 매크로로 송신기 지정.
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

  always #5 clk = ~clk;

  integer queue [0:N-1][0:QDEPTH-1];
  integer qhead [0:N-1];
  integer qcount [0:N-1];

  integer cyc, i, latency, idx;
  integer total_latency [0:N-1];
  integer max_latency   [0:N-1];
  integer grant_count   [0:N-1];
  integer total_grants;
  integer overflow_warns;
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
    rst = 1; req = 64'd0; total_grants = 0; overflow_warns = 0; phantom_errors = 0;
    for (i = 0; i < N; i = i + 1) begin
      qhead[i] = 0; qcount[i] = 0;
      total_latency[i] = 0; max_latency[i] = 0; grant_count[i] = 0;
    end
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < N; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < ARRIVAL_PCT) begin
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

      if (event_valid) begin
        idx = event_row*8 + event_col;
        if (qcount[idx] == 0) begin
          $display("PHANTOM ERROR: cycle=%0d row=%0d col=%0d 인데 대기 이벤트가 없었음", cyc, event_row, event_col);
          phantom_errors = phantom_errors + 1;
        end else begin
          latency = cyc - queue[idx][qhead[idx]];
          total_latency[idx] = total_latency[idx] + latency;
          if (latency > max_latency[idx]) max_latency[idx] = latency;
          grant_count[idx] = grant_count[idx] + 1;
          total_grants = total_grants + 1;
          qhead[idx] = (qhead[idx] + 1) % QDEPTH;
          qcount[idx] = qcount[idx] - 1;
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
    integer sum_lat, max_lat_all, min_gc, max_gc;
    integer g_sum_lat [0:1], g_sum_grants [0:1];
    begin
      sum_lat = 0; max_lat_all = 0; min_gc = grant_count[0]; max_gc = grant_count[0];
      g_sum_lat[0]=0; g_sum_lat[1]=0; g_sum_grants[0]=0; g_sum_grants[1]=0;
      for (i = 0; i < N; i = i + 1) begin
        sum_lat = sum_lat + total_latency[i];
        if (max_latency[i] > max_lat_all) max_lat_all = max_latency[i];
        if (grant_count[i] < min_gc) min_gc = grant_count[i];
        if (grant_count[i] > max_gc) max_gc = grant_count[i];
        g_sum_lat[group_of(i)] = g_sum_lat[group_of(i)] + total_latency[i];
        g_sum_grants[group_of(i)] = g_sum_grants[group_of(i)] + grant_count[i];
      end
      $display("=== AER64[%s] BENCH REPORT (CYCLES=%0d, ARRIVAL_PCT=%0d%%) ===", `TX_NAME, CYCLES, ARRIVAL_PCT);
      $display("[1] 평균 지연시간: %0d cycles (total_grants=%0d)", (total_grants>0)?sum_lat/total_grants:0, total_grants);
      $display("[2] 최악 지연시간: %0d cycles", max_lat_all);
      $display("[3] 공정성: max-min grant 차이 = %0d (min=%0d, max=%0d)", max_gc-min_gc, min_gc, max_gc);
      $display("[4] 처리량: %0d grants / %0d cycles = %0d.%0d grants per 100cycles", total_grants, CYCLES, (total_grants*100)/CYCLES, ((total_grants*10000)/CYCLES)%100);
      $display("[5] 그룹간 평균 지연시간: center(4x4)=%0d cycles, periphery=%0d cycles",
        (g_sum_grants[0]>0)?g_sum_lat[0]/g_sum_grants[0]:0,
        (g_sum_grants[1]>0)?g_sum_lat[1]/g_sum_grants[1]:0);
      if (overflow_warns > 0)
        $display("WARNING: 큐 오버플로우 %0d회", overflow_warns);
    end
  endtask
endmodule
