// 적응형(A-FAER)의 최악 지연시간 원인 분석용 디버그 테스트벤치.
// 핫스팟(중심) 시나리오를 그대로 재현하면서, 특정 이벤트의 지연시간이 임계값을 넘으면
// 그 시점 전후로 activity 카운터/hot_mask 내부 상태를 계층 참조(tx.xxx)로 찍어본다.
module tb_debug_adaptive;
  parameter CYCLES = 3000;
  parameter QDEPTH = 64;
  parameter BG_PCT = 3;
  parameter HOT_PCT = 50;
  parameter LATENCY_THRESHOLD = 900; // 이 이상 걸린 이벤트만 자세히 로그

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire       valid, addr_type;
  wire [1:0] addr;
  wire       event_valid;
  wire [1:0] event_row, event_col;

  aer_tx16_adaptive tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx16 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  always #5 clk = ~clk;

  integer rng_seed = 1;
  event_scoreboard #(.N(16), .QDEPTH(QDEPTH)) score();
  integer cyc, i, idx, latency;

  function is_hotspot(input integer idx_);
    is_hotspot = (idx_==5 || idx_==6 || idx_==9 || idx_==10);
  endfunction

  initial begin
    rst = 1; req = 16'd0;
    score.init;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < 16; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < (is_hotspot(i) ? HOT_PCT : BG_PCT)) begin
          score.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < 16; i = i + 1) req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      if (event_valid) begin
        idx = event_row*4+event_col;
        latency = score.record_departure(idx, cyc);
        if (latency >= 0) begin
          if (is_hotspot(idx) && latency > LATENCY_THRESHOLD) begin
            $display("cycle=%0d row=%0d col=%0d latency=%0d | activity=[%0d,%0d,%0d,%0d] hot_mask=%b round=%0d qcount(hotspot)=[%0d,%0d,%0d,%0d]",
              cyc, event_row, event_col, latency,
              tx.activity[0], tx.activity[1], tx.activity[2], tx.activity[3],
              tx.hot_mask, tx.round,
              score.qcount[5], score.qcount[6], score.qcount[9], score.qcount[10]);
          end
        end
      end
    end
    $display("done");
    $finish;
  end
endmodule
