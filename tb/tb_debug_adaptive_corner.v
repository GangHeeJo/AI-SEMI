// 모서리(주변) 핫스팟 시나리오에서 activity/hot_mask 내부 상태를 추적하는 디버그 벤치.
module tb_debug_adaptive_corner;
  parameter CYCLES = 3000;
  parameter QDEPTH = 64;
  parameter BG_PCT = 3;
  parameter HOT_PCT = 50;
  parameter LATENCY_THRESHOLD = 700;

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

  integer rng_seed = 5;
  integer queue [0:15][0:QDEPTH-1];
  integer qhead [0:15];
  integer qcount [0:15];
  integer cyc, i, idx, latency;

  function is_hotspot(input integer idx_);
    is_hotspot = (idx_==0 || idx_==3 || idx_==12 || idx_==15); // 모서리
  endfunction

  integer last_visit [0:3];
  real gap_sum [0:3];
  real gap_sumsq [0:3];
  integer gap_count [0:3];

  initial begin
    rst = 1; req = 16'd0;
    for (i=0;i<16;i=i+1) begin qhead[i]=0; qcount[i]=0; end
    for (i=0;i<4;i=i+1) begin last_visit[i]=-1; gap_sum[i]=0.0; gap_sumsq[i]=0.0; gap_count[i]=0; end
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < 16; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < (is_hotspot(i) ? HOT_PCT : BG_PCT)) begin
          if (qcount[i] < QDEPTH) begin
            queue[i][(qhead[i]+qcount[i])%QDEPTH] = cyc;
            qcount[i] = qcount[i] + 1;
          end
        end
      end
      for (i = 0; i < 16; i = i + 1) req[i] = (qcount[i] > 0);

      @(posedge clk); #1;

      if (valid && addr_type==1'b0) begin
        if (last_visit[addr] >= 0) begin
          gap_sum[addr]   = gap_sum[addr]   + (cyc - last_visit[addr]);
          gap_sumsq[addr] = gap_sumsq[addr] + (cyc - last_visit[addr]) * (cyc - last_visit[addr]);
          gap_count[addr] = gap_count[addr] + 1;
        end
        last_visit[addr] = cyc;
      end

      if (valid && addr_type==1'b0 && cyc > 700 && cyc < 900)
        $display("  [row-select] cyc=%0d row=%0d hot_mask=%b use_hot=%b use_cold=%b hot_arb.req=%b hot_arb.gnt=%b hot_arb.last_gnt=%0d cold_arb.req=%b cold_arb.last_gnt=%0d round=%0d",
          cyc, addr, tx.hot_mask, tx.use_hot, tx.use_cold,
          tx.hot_arb.req, tx.hot_arb.gnt, tx.hot_arb.last_gnt,
          tx.cold_arb.req, tx.cold_arb.last_gnt, tx.round);

      if (event_valid) begin
        idx = event_row*4+event_col;
        if (qcount[idx] > 0) begin
          latency = cyc - queue[idx][qhead[idx]];
          qhead[idx] = (qhead[idx]+1)%QDEPTH;
          qcount[idx] = qcount[idx]-1;
          if (is_hotspot(idx) && latency > LATENCY_THRESHOLD) begin
            $display("cycle=%0d row=%0d col=%0d latency=%0d | activity=[%0d,%0d,%0d,%0d] hot_mask=%b round=%0d hot_arb.last_gnt=%0d",
              cyc, event_row, event_col, latency,
              tx.activity[0], tx.activity[1], tx.activity[2], tx.activity[3],
              tx.hot_mask, tx.round, tx.hot_arb.last_gnt);
          end
        end
      end
    end
    for (i=0;i<4;i=i+1) begin
      if (gap_count[i]>0)
        $display("row%0d: visits=%0d mean_gap=%f var_gap=%f", i, gap_count[i],
          gap_sum[i]/gap_count[i], (gap_sumsq[i]/gap_count[i]) - (gap_sum[i]/gap_count[i])*(gap_sum[i]/gap_count[i]));
    end
    $display("done");
    $finish;
  end
endmodule
