// base(aer_tx16, burst) 전용 안전-부하 벤치 — event_valid(RX 이후)가 아니라
// captured_row/captured_cols(그랜트된 바로 그 사이클의 확정 신호, progress.md #11/#14
// ack갭 수정)로 큐를 소거해서 레이스 없이 정확한 지연시간을 잰다.
// safe_bench_core.vh와 같은 원칙(큰 QDEPTH로 오버플로우 검사)을 쓰되, addr_type/addr[1:0]
// 인터페이스+burst라 별도 TB로 분리.
`timescale 1ns/1ps
module tb_aer_tx16_base_safe;
  `ifndef ARRIVAL_PCT_VAL
  `define ARRIVAL_PCT_VAL 4
  `endif
  parameter N = 16;
  parameter CYCLES = 3000;
  parameter QDEPTH = 200000;
  parameter ARRIVAL_PCT = `ARRIVAL_PCT_VAL;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid, addr_type;
  wire [1:0] addr;
  wire [1:0] captured_row;
  wire [3:0] captured_cols;

  aer_tx16 tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr),
              .captured_row(captured_row), .captured_cols(captured_cols));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, j, latency, idx;
  integer phantom_errors;

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

      if (captured_cols != 4'd0) begin
        for (j = 0; j < 4; j = j + 1) begin
          if (captured_cols[j]) begin
            idx = captured_row * 4 + j;
            latency = score.record_departure(idx, cyc);
            if (latency < 0) begin
              $display("PHANTOM ERROR: cycle=%0d idx=%0d", cyc, idx);
              phantom_errors = phantom_errors + 1;
            end
          end
        end
      end
    end

    $display("=== [base] SAFE BENCH (CYCLES=%0d, ARRIVAL_PCT=%0d%%) ===", CYCLES, ARRIVAL_PCT);
    $display("[1] 평균 지연시간: %0d cycles (total_grants=%0d)", score.avg_latency(0), score.count);
    $display("[2] 최악 지연시간: %0d cycles", score.max_lat);
    $display("[3] Jain fairness index = %0d/1000", score.jain_fairness_x1000(0));
    $display("[4] 처리량: %0d.%0d%%", (score.count*100)/CYCLES, ((score.count*1000)/CYCLES)%10);
    $display("[5] phantom=%0d overflow=%0d", phantom_errors, score.overflow_count);
    if (score.overflow_count > 0)
      $display(">>> 신뢰 불가: 이 부하는 채널 용량을 넘어섬(rho>=1) <<<");
    else if (phantom_errors == 0)
      $display(">>> 검증 통과, 결과 신뢰 가능(overflow 0, phantom 0) <<<");
    $finish;
  end
endmodule
