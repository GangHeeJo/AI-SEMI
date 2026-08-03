// v2(STD만)와 v3(STD+DS)를 완전히 동일한 무작위(균일, 핫스팟 없음) 트래픽으로
// 동시에 구동해 평균/최악 지연시간과 공정성(Jain fairness index)을 직접 비교.
// v2의 알려진 트레이드오프(균일 트래픽에서 평균지연 악화)를 v3의 DS(강제 냉각)가
// 완화하는지, 혹은 오히려 hot 추적 성능을 깎아먹기만 하는지 확인하는 게 목적.
// 큐/지연시간/공정성 추적은 event_scoreboard(공용 채점기)로 통일함.
`ifndef PCT_VAL
`define PCT_VAL 15
`endif
module tb_v2_vs_v3_uniform;
  parameter QDEPTH = 64;
  parameter PCT = `PCT_VAL;
  parameter CYCLES = 3000;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  reg [15:0] new_event;

  wire v2_valid, v2_addr_type; wire [1:0] v2_addr;
  wire v3_valid, v3_addr_type; wire [1:0] v3_addr;
  wire v2_ev, v3_ev; wire [1:0] v2_row, v2_col, v3_row, v3_col;

  aer_tx16_adaptive_v2 tx2(.clk(clk), .rst(rst), .req(req), .new_event(new_event), .valid(v2_valid), .addr_type(v2_addr_type), .addr(v2_addr));
  aer_rx16 rx2(.clk(clk), .rst(rst), .valid(v2_valid), .addr_type(v2_addr_type), .addr(v2_addr), .event_valid(v2_ev), .event_row(v2_row), .event_col(v2_col));

  aer_tx16_adaptive_v3 tx3(.clk(clk), .rst(rst), .req(req), .new_event(new_event), .valid(v3_valid), .addr_type(v3_addr_type), .addr(v3_addr));
  aer_rx16 rx3(.clk(clk), .rst(rst), .valid(v3_valid), .addr_type(v3_addr_type), .addr(v3_addr), .event_valid(v3_ev), .event_row(v3_row), .event_col(v3_col));

  event_scoreboard #(.N(16), .QDEPTH(QDEPTH)) score2();
  event_scoreboard #(.N(16), .QDEPTH(QDEPTH)) score3();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, idx, latency;

  initial begin
    rst = 1; req = 16'd0; new_event = 16'd0;
    score2.init; score3.init;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      new_event = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < PCT) begin
          new_event[i] = 1'b1;
          score2.record_arrival(i, cyc);
          score3.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < 16; i = i + 1) req[i] = (score2.qcount[i] > 0) || (score3.qcount[i] > 0);
      // 주의: req는 v2/v3 공통 입력이라 OR로 묶되, 실제 소비는 각자 own 스코어보드로 판단.
      // 한쪽 큐가 먼저 비면 그 셀의 req는 다른쪽 큐 때문에 계속 1일 수 있으나,
      // record_departure가 qcount==0이면 phantom(-1) 처리하므로 통계엔 영향 없음.

      @(posedge clk); #1;

      if (v2_ev) begin
        idx = v2_row*4+v2_col;
        latency = score2.record_departure(idx, cyc);
      end
      if (v3_ev) begin
        idx = v3_row*4+v3_col;
        latency = score3.record_departure(idx, cyc);
      end
    end

    $display("=== 균일 트래픽(PCT=%0d%%) v2 vs v3 ===", PCT);
    $display("v2: 평균지연=%0d 최악지연=%0d Jain fairness=%0d/1000", score2.avg_latency(0), score2.max_lat, score2.jain_fairness_x1000(0));
    $display("v3: 평균지연=%0d 최악지연=%0d Jain fairness=%0d/1000", score3.avg_latency(0), score3.max_lat, score3.jain_fairness_x1000(0));
    $finish;
  end
endmodule
