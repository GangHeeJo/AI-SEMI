// 8x8 v2 핫스팟 검증 — 물체가 "중심 4행(2,3,4,5)"에 있을 때 vs "주변 4행(0,1,6,7)"에 있을 때.
`ifndef HOT_ROWS_PERIPH
`define HOT_ROWS_CENTER
`endif
module tb_hotspot64_v2;
  parameter QDEPTH = 64;
  parameter BG_PCT = 2;
  parameter HOT_PCT = 20;
  parameter CYCLES = 6000;

  reg clk = 0;
  reg rst;
  reg [63:0] req;
  reg [63:0] new_event;
  wire       valid, addr_type;
  wire [2:0] addr;
  wire       event_valid;
  wire [2:0] event_row, event_col;

  aer_tx64_adaptive_v2 tx(.clk(clk), .rst(rst), .req(req), .new_event(new_event), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx64 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  always #5 clk = ~clk;

  integer rng_seed = 1;
  event_scoreboard #(.N(64), .QDEPTH(QDEPTH)) score();
  integer cyc, i, idx, latency;
  integer hot_sum_lat, hot_count, hot_max_lat;

  function is_hotspot(input integer idx_);
    integer r;
    begin
    r = idx_ / 8;
`ifdef HOT_ROWS_PERIPH
    is_hotspot = (r==0 || r==1 || r==6 || r==7);
`else
    is_hotspot = (r==2 || r==3 || r==4 || r==5);
`endif
    end
  endfunction

  initial begin
    rst = 1; req = 64'd0; new_event = 64'd0;
    hot_sum_lat=0; hot_count=0; hot_max_lat=0;
    score.init;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      new_event = 64'd0;
      for (i = 0; i < 64; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < (is_hotspot(i) ? HOT_PCT : BG_PCT)) begin
          new_event[i] = 1'b1;
          score.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < 64; i = i + 1) req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      if (event_valid) begin
        idx = event_row*8+event_col;
        latency = score.record_departure(idx, cyc);
        if (latency >= 0) begin
          if (is_hotspot(idx)) begin
            hot_sum_lat = hot_sum_lat + latency;
            hot_count = hot_count + 1;
            if (latency > hot_max_lat) hot_max_lat = latency;
          end
        end
      end
    end
`ifdef HOT_ROWS_PERIPH
    $display("[64/PERIPH-hot] 평균지연=%0d (최악=%0d, n=%0d)", (hot_count>0)?hot_sum_lat/hot_count:0, hot_max_lat, hot_count);
`else
    $display("[64/CENTER-hot] 평균지연=%0d (최악=%0d, n=%0d)", (hot_count>0)?hot_sum_lat/hot_count:0, hot_max_lat, hot_count);
`endif
    $finish;
  end
endmodule
