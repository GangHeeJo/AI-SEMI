// Boahen(2000)의 "N이 커질수록(같은 총 부하 기준) 큐잉 지연의 상대적 타이밍 오차가
// 오히려 작아진다"는 스케일링 주장을 true_traditional의 N=16 vs N=64 버전으로 검증.
// 두 경우 다 채널 용량은 1 event/cycle로 동일하므로, "총 offered load"(N x
// ARRIVAL_PCT)를 같게 맞추고 평균 지연시간을 비교한다.
`timescale 1ns/1ps
module tb_trad_scaling;
  parameter CYCLES = 3000;
  parameter QDEPTH = 64;

  // ---- N=16 인스턴스 ----
  reg clk16 = 0; reg rst16; reg [15:0] req16;
  wire valid16; wire [3:0] addr16;
  aer_tx16_trad_rowcol dut16(.clk(clk16), .rst(rst16), .req(req16), .valid(valid16), .addr(addr16));
  event_scoreboard #(.N(16), .QDEPTH(QDEPTH)) score16();
  always #5 clk16 = ~clk16;

  // ---- N=64 인스턴스 ----
  reg clk64 = 0; reg rst64; reg [63:0] req64;
  wire valid64; wire [5:0] addr64;
  aer_tx64_trad_rowcol dut64(.clk(clk64), .rst(rst64), .req(req64), .valid(valid64), .addr(addr64));
  event_scoreboard #(.N(64), .QDEPTH(QDEPTH)) score64();
  always #5 clk64 = ~clk64;

  integer cyc, i, lat, err16, err64;
  integer pct16, pct64;

  initial begin
    // 총 offered load를 맞춤: 16 x pct16 = 64 x pct64 (약 64% 이용률)
    pct16 = 4;  // 16 x 4% = 0.64 events/cycle
    pct64 = 1;  // 64 x 1% = 0.64 events/cycle
    err16 = 0; err64 = 0;

    rst16 = 1; req16 = 16'd0; score16.init;
    rst64 = 1; req64 = 64'd0; score64.init;
    @(posedge clk16); #1; rst16 = 0; rst64 = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < 16; i = i + 1)
        if ((($random % 100) + 100) % 100 < pct16) score16.record_arrival(i, cyc);
      for (i = 0; i < 16; i = i + 1) req16[i] = (score16.qcount[i] > 0);

      for (i = 0; i < 64; i = i + 1)
        if ((($random % 100) + 100) % 100 < pct64) score64.record_arrival(i, cyc);
      for (i = 0; i < 64; i = i + 1) req64[i] = (score64.qcount[i] > 0);

      @(posedge clk16); #1;

      if (valid16) begin
        lat = score16.record_departure(addr16, cyc);
        if (lat < 0) err16 = err16 + 1;
      end
      if (valid64) begin
        lat = score64.record_departure(addr64, cyc);
        if (lat < 0) err64 = err64 + 1;
      end
    end

    $display("=== N=16 (ARRIVAL_PCT=%0d%%, 총부하=0.64 evt/cyc) ===", pct16);
    $display("  emitted=%0d avg_latency=%f cyc max_latency=%0d jain=%0d/1000 overflow=%0d errors=%0d",
              score16.count, score16.sum_lat * 1.0 / score16.count, score16.max_lat, score16.jain_fairness_x1000(0), score16.overflow_count, err16);
    $display("=== N=64 (ARRIVAL_PCT=%0d%%, 총부하=0.64 evt/cyc) ===", pct64);
    $display("  emitted=%0d avg_latency=%f cyc max_latency=%0d jain=%0d/1000 overflow=%0d errors=%0d",
              score64.count, score64.sum_lat * 1.0 / score64.count, score64.max_lat, score64.jain_fairness_x1000(0), score64.overflow_count, err64);
    $finish;
  end
endmodule
