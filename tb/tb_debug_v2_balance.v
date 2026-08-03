// v2에서도 row0/row3 균형이 유지되는지 확인 (모서리 핫스팟, gap 측정).
module tb_debug_v2_balance;
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

  aer_tx16_adaptive_v2 tx(.clk(clk), .rst(rst), .req(req), .new_event(new_event), .valid(valid), .addr_type(addr_type), .addr(addr));

  always #5 clk = ~clk;

  integer rng_seed = 1;
  event_scoreboard #(.N(16), .QDEPTH(QDEPTH)) score();
  integer cyc, i;

  integer last_visit [0:3];
  real gap_sum [0:3];
  integer gap_count [0:3];

  function is_hotspot(input integer idx_);
    is_hotspot = (idx_==0 || idx_==3 || idx_==12 || idx_==15);
  endfunction

  initial begin
    rst = 1; req = 16'd0; new_event = 16'd0;
    score.init;
    for (i=0;i<4;i=i+1) begin last_visit[i]=-1; gap_sum[i]=0.0; gap_count[i]=0; end
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

      if (valid && addr_type==1'b0) begin
        if (last_visit[addr] >= 0) begin
          gap_sum[addr] = gap_sum[addr] + (cyc - last_visit[addr]);
          gap_count[addr] = gap_count[addr] + 1;
        end
        last_visit[addr] = cyc;
      end

      if (valid && addr_type==1'b1) begin
        // 열 소비는 별도 수신기 없이 그냥 큐만 비워준다(균형 측정 목적이라 단순화)
      end
    end

    for (i=0;i<4;i=i+1)
      if (gap_count[i]>0) $display("row%0d: visits=%0d", i, gap_count[i]);
    $finish;
  end
endmodule
