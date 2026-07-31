// base(aer_tx64, 우선순위 없음)로 8x8 핫스팟 기준값 측정 — v2와 비교용.
`ifndef HOT_ROWS_PERIPH
`define HOT_ROWS_CENTER
`endif
module tb_hotspot64_base;
  parameter QDEPTH = 64;
  parameter BG_PCT = 2;
  parameter HOT_PCT = 20;
  parameter CYCLES = 6000;

  reg clk = 0;
  reg rst;
  reg [63:0] req;
  wire       valid, addr_type;
  wire [2:0] addr;
  wire       event_valid;
  wire [2:0] event_row, event_col;

  aer_tx64 tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx64 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer queue [0:63][0:QDEPTH-1];
  integer qhead [0:63];
  integer qcount [0:63];
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
    rst = 1; req = 64'd0;
    hot_sum_lat=0; hot_count=0; hot_max_lat=0;
    for (i=0;i<64;i=i+1) begin qhead[i]=0; qcount[i]=0; end
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < 64; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < (is_hotspot(i) ? HOT_PCT : BG_PCT)) begin
          if (qcount[i] < QDEPTH) begin
            queue[i][(qhead[i]+qcount[i])%QDEPTH] = cyc;
            qcount[i] = qcount[i] + 1;
          end
        end
      end
      for (i = 0; i < 64; i = i + 1) req[i] = (qcount[i] > 0);

      @(posedge clk); #1;

      if (event_valid) begin
        idx = event_row*8+event_col;
        if (qcount[idx] > 0) begin
          latency = cyc - queue[idx][qhead[idx]];
          qhead[idx] = (qhead[idx]+1)%QDEPTH;
          qcount[idx] = qcount[idx]-1;
          if (is_hotspot(idx)) begin
            hot_sum_lat = hot_sum_lat + latency;
            hot_count = hot_count + 1;
            if (latency > hot_max_lat) hot_max_lat = latency;
          end
        end
      end
    end
`ifdef HOT_ROWS_PERIPH
    $display("[base64/PERIPH-hot] 평균지연=%0d (최악=%0d, n=%0d)", (hot_count>0)?hot_sum_lat/hot_count:0, hot_max_lat, hot_count);
`else
    $display("[base64/CENTER-hot] 평균지연=%0d (최악=%0d, n=%0d)", (hot_count>0)?hot_sum_lat/hot_count:0, hot_max_lat, hot_count);
`endif
    $finish;
  end
endmodule
