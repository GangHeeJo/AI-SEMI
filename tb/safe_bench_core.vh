// "안전 부하" 표준 벤치 코어 — 큐 오버플로우(QDEPTH 캡에 의한 지연시간 편향)를 항상
// 검사하고, ρ<1(채널 용량 이하)인 안정적 부하에서만 신뢰 가능한 평균/최악 지연시간을
// 보고한다. addr[3:0](flat index 0..15) 한 사이클 직접 응답 인터페이스(naive,
// true_traditional 계열)에만 씀 — burst 상태기계(aer_tx16 base 등)는 event_valid까지
// 기다리면 grant와 큐 소거 사이에 지연이 생겨(레이스) 이 코어로 정확히 못 잼.
// `TX/`TX_NAME 매크로로 DUT 지정. overflow>0이면 결과를 신뢰할 수 없다고 명시 경고.
module tb_safe_bench;
  `ifndef SEED_VAL
  `define SEED_VAL 1
  `endif
  parameter N = 16;
  parameter CYCLES = 3000;
  parameter QDEPTH = 200000; // 실질적으로 무한(안정 부하에서는 절대 안 참) — 오버플로우로 검증
  `ifndef ARRIVAL_PCT_VAL
  `define ARRIVAL_PCT_VAL 4
  `endif
  parameter ARRIVAL_PCT = `ARRIVAL_PCT_VAL;

  integer rng_seed = `SEED_VAL;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid;
  wire [3:0] addr;

  `ifndef TX_PARAMS
  `define TX_PARAMS
  `endif
  `TX `TX_PARAMS tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr(addr));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer cyc, i, latency;
  integer phantom_errors;

  function integer group_of(input integer idx_);
    integer r, c;
    begin
      r = idx_ / 4; c = idx_ % 4;
      group_of = (r >= 1 && r <= 2 && c >= 1 && c <= 2) ? 0 : 1;
    end
  endfunction

  initial begin
    rst = 1; req = 16'd0; phantom_errors = 0;
    score.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < N; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < ARRIVAL_PCT)
          score.record_arrival(i, cyc);
      end
      for (i = 0; i < N; i = i + 1) req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      if (valid) begin
        latency = score.record_departure(addr, cyc);
        if (latency < 0) begin
          $display("PHANTOM ERROR: cycle=%0d addr=%0d", cyc, addr);
          phantom_errors = phantom_errors + 1;
        end
      end
    end

    $display("=== [%s] SAFE BENCH (CYCLES=%0d, ARRIVAL_PCT=%0d%%) ===", `TX_NAME, CYCLES, ARRIVAL_PCT);
    $display("[1] 평균 지연시간: %0d cycles (total_grants=%0d)", score.avg_latency(0), score.count);
    $display("[2] 최악 지연시간: %0d cycles", score.max_lat);
    $display("[3] Jain fairness index = %0d/1000", score.jain_fairness_x1000(0));
    $display("[4] 처리량: %0d.%0d%%", (score.count*100)/CYCLES, ((score.count*1000)/CYCLES)%10);
    $display("[5] phantom=%0d overflow=%0d", phantom_errors, score.overflow_count);
    if (score.overflow_count > 0)
      $display(">>> 신뢰 불가: 이 부하는 채널 용량을 넘어섬(ρ>=1) — ARRIVAL_PCT를 낮추세요 <<<");
    else if (phantom_errors == 0)
      $display(">>> 검증 통과, 결과 신뢰 가능(overflow 0, phantom 0) <<<");
    $finish;
  end
endmodule
