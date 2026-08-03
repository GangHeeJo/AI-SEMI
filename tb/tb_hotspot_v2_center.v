// v2(도착률기반)로 정적 핫스팟(중심 고정) 재검증.
module tb_hotspot_v2_center;
  parameter QDEPTH = 64;
  parameter BG_PCT = 3;
  parameter HOT_PCT = 50;
  parameter CYCLES = 3000;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  reg [15:0] new_event;
  wire       valid, addr_type;
  wire [1:0] addr;
  wire       event_valid;
  wire [1:0] event_row, event_col;

  aer_tx16_adaptive_v2 tx(.clk(clk), .rst(rst), .req(req), .new_event(new_event), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx16 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  always #5 clk = ~clk;

  integer rng_seed = 1;
  event_scoreboard #(.N(16), .QDEPTH(QDEPTH)) score();
  integer cyc, i, idx, latency;
  integer hot_sum_lat, hot_count, hot_max_lat;

  function is_hotspot(input integer idx_);
    is_hotspot = (idx_==5 || idx_==6 || idx_==9 || idx_==10);
  endfunction

  initial begin
    rst = 1; req = 16'd0; new_event = 16'd0;
    hot_sum_lat=0; hot_count=0; hot_max_lat=0;
    score.init;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      new_event = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < (is_hotspot(i) ? HOT_PCT : BG_PCT)) begin
          new_event[i] = 1'b1;
          score.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < 16; i = i + 1) req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      if (event_valid) begin
        idx = event_row*4+event_col;
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
    $display("[v2/CENTER] hotspot 평균지연=%0d (최악=%0d, n=%0d)", (hot_count>0)?hot_sum_lat/hot_count:0, hot_max_lat, hot_count);
    $finish;
  end
endmodule
