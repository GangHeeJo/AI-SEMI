// "움직이는 물체" 시나리오 — 배경은 낮은 빈도(BG_PCT)로 조용히 발화하고,
// 특정 4개 셀("hotspot", 물체가 있는 곳)만 훨씬 높은 빈도(HOT_PCT)로 발화한다.
// `HOTSPOT_SET으로 hotspot 위치를 CENTER(중심 2x2) 또는 CORNER(네 모서리)로 지정.
// hotspot 셀들의 지연시간만 따로 집계해서, "물체가 중심에 있을 때 vs 주변에 있을 때"
// 우리 설계(fovea)가 어떻게 다르게 반응하는지 확인한다.
// 큐/지연시간 추적은 event_scoreboard(공용 채점기)로 통일함.
module tb_hotspot_bench;
  `ifndef SEED_VAL
  `define SEED_VAL 1
  `endif
  `ifndef HOTSPOT_SET
  `define HOTSPOT_SET CENTER
  `endif
  parameter N = 16;
  parameter CYCLES = 3000;
  parameter QDEPTH = 64;
  parameter BG_PCT  = 3;
  parameter HOT_PCT = 50;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire       valid, addr_type;
  wire [1:0] addr;
  wire       event_valid;
  wire [1:0] event_row, event_col;

  `ifndef TX_PARAMS
  `define TX_PARAMS
  `endif
  `TX `TX_PARAMS tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx16 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer rng_seed = `SEED_VAL;

  // hotspot 셀 4개를 1로 표시하는 마스크
  function is_hotspot(input integer idx_);
`ifdef HOTSPOT_CENTER_SET
    is_hotspot = (idx_==5 || idx_==6 || idx_==9 || idx_==10); // 중심 2x2
`else
    is_hotspot = (idx_==0 || idx_==3 || idx_==12 || idx_==15); // 네 모서리(주변)
`endif
  endfunction

  integer cyc, i, latency, idx;
  integer hot_sum_lat, hot_count, hot_max_lat;
  integer bg_sum_lat, bg_count;

  initial begin
    rst = 1; req = 16'd0;
    hot_sum_lat=0; hot_count=0; hot_max_lat=0; bg_sum_lat=0; bg_count=0;
    score.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < N; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < (is_hotspot(i) ? HOT_PCT : BG_PCT)) begin
          score.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < N; i = i + 1) req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      if (event_valid) begin
        idx = event_row*4 + event_col;
        latency = score.record_departure(idx, cyc);
        if (latency >= 0) begin
          if (is_hotspot(idx)) begin
            hot_sum_lat = hot_sum_lat + latency;
            hot_count = hot_count + 1;
            if (latency > hot_max_lat) hot_max_lat = latency;
          end else begin
            bg_sum_lat = bg_sum_lat + latency;
            bg_count = bg_count + 1;
          end
        end
      end
    end

    $display("[%s / %s] hotspot 평균지연=%0d (최악=%0d, n=%0d), 배경 평균지연=%0d (n=%0d), 전체 Jain fairness=%0d/1000",
      `TX_NAME, `HOTSPOT_NAME,
      (hot_count>0)?hot_sum_lat/hot_count:0, hot_max_lat, hot_count,
      (bg_count>0)?bg_sum_lat/bg_count:0, bg_count, score.jain_fairness_x1000(0));
    $finish;
  end
endmodule
