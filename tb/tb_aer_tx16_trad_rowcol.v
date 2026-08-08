// aer_tx16_trad_rowcol 정확성 검증: 3000사이클 무작위 트래픽, phantom/유령이벤트 0건 확인.
`timescale 1ns/1ps
module tb_aer_tx16_trad_rowcol;
  parameter N = 16;
  parameter CYCLES = 3000;
  parameter QDEPTH = 32;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid;
  wire [3:0] addr;

  aer_tx16_trad_rowcol tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr(addr));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer cyc, i, latency;
  integer phantom_errors;

  initial begin
    rst = 1; req = 16'd0; phantom_errors = 0;
    score.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < N; i = i + 1) begin
        if ((($random % 100) + 100) % 100 < ARRIVAL_PCT)
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

    $display("=== trad_rowcol: %0d 사이클, ARRIVAL_PCT=%0d%%, phantom=%0d, emitted=%0d, avg_latency=%0d, max_latency=%0d, jain=%0d/1000 ===",
              CYCLES, ARRIVAL_PCT, phantom_errors, score.count, score.avg_latency(0), score.max_lat, score.jain_fairness_x1000(0));
    if (phantom_errors == 0) $display("=== 검증 통과 ===");
    else $display("=== 검증 실패 ===");
    $finish;
  end
endmodule
