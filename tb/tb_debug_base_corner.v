// base(aer_tx16)에서도 모서리 핫스팟 트래픽에서 row0/row3 방문 횟수가 비대칭인지 교차 확인.
module tb_debug_base_corner;
  parameter CYCLES = 3000;
  parameter QDEPTH = 64;
  parameter BG_PCT = 3;
  parameter HOT_PCT = 50;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire       valid, addr_type;
  wire [1:0] addr;
  wire       event_valid;
  wire [1:0] event_row, event_col;

  aer_tx16 tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx16 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer queue [0:15][0:QDEPTH-1];
  integer qhead [0:15];
  integer qcount [0:15];
  integer cyc, i, idx, latency;

  function is_hotspot(input integer idx_);
    is_hotspot = (idx_==0 || idx_==3 || idx_==12 || idx_==15);
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

      if (event_valid) begin
        idx = event_row*4+event_col;
        if (qcount[idx] > 0) begin
          latency = cyc - queue[idx][qhead[idx]];
          qhead[idx] = (qhead[idx]+1)%QDEPTH;
          qcount[idx] = qcount[idx]-1;
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
