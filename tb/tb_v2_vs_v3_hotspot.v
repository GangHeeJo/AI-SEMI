// 정적 핫스팟(모서리 또는 중심 고정)에서 v2 vs v3 비교 — hot/배경 평균·최악 지연 둘 다 집계.
// v3의 DS(강제 냉각)가 hot 추적 성능을 얼마나 깎아먹는지, 그 대가로 무엇을 얻는지 확인.
`ifndef HOT_PCT_VAL
`define HOT_PCT_VAL 50
`endif
`ifndef HOTSPOT_CORNER
`define HOTSPOT_CENTER
`endif
module tb_v2_vs_v3_hotspot;
  parameter QDEPTH = 64;
  parameter BG_PCT = 3;
  parameter HOT_PCT = `HOT_PCT_VAL;
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

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer q2 [0:15][0:QDEPTH-1]; integer qh2 [0:15]; integer qc2 [0:15];
  integer q3 [0:15][0:QDEPTH-1]; integer qh3 [0:15]; integer qc3 [0:15];
  integer cyc, i, idx, latency;
  integer hs2, hc2, hm2, bs2, bc2, bm2;
  integer hs3, hc3, hm3, bs3, bc3, bm3;

  function is_hotspot(input integer idx_);
`ifdef HOTSPOT_CORNER
    is_hotspot = (idx_==0 || idx_==3 || idx_==12 || idx_==15);
`else
    is_hotspot = (idx_==5 || idx_==6 || idx_==9 || idx_==10);
`endif
  endfunction

  initial begin
    rst = 1; req = 16'd0; new_event = 16'd0;
    hs2=0;hc2=0;hm2=0;bs2=0;bc2=0;bm2=0;
    hs3=0;hc3=0;hm3=0;bs3=0;bc3=0;bm3=0;
    for (i=0;i<16;i=i+1) begin qh2[i]=0; qc2[i]=0; qh3[i]=0; qc3[i]=0; end
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      new_event = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < (is_hotspot(i) ? HOT_PCT : BG_PCT)) begin
          new_event[i] = 1'b1;
          if (qc2[i] < QDEPTH) begin q2[i][(qh2[i]+qc2[i])%QDEPTH] = cyc; qc2[i]=qc2[i]+1; end
          if (qc3[i] < QDEPTH) begin q3[i][(qh3[i]+qc3[i])%QDEPTH] = cyc; qc3[i]=qc3[i]+1; end
        end
      end
      for (i = 0; i < 16; i = i + 1) req[i] = (qc2[i] > 0) || (qc3[i] > 0);

      @(posedge clk); #1;

      if (v2_ev) begin
        idx = v2_row*4+v2_col;
        if (qc2[idx] > 0) begin
          latency = cyc - q2[idx][qh2[idx]];
          qh2[idx]=(qh2[idx]+1)%QDEPTH; qc2[idx]=qc2[idx]-1;
          if (is_hotspot(idx)) begin hs2=hs2+latency; hc2=hc2+1; if(latency>hm2) hm2=latency; end
          else begin bs2=bs2+latency; bc2=bc2+1; if(latency>bm2) bm2=latency; end
        end
      end
      if (v3_ev) begin
        idx = v3_row*4+v3_col;
        if (qc3[idx] > 0) begin
          latency = cyc - q3[idx][qh3[idx]];
          qh3[idx]=(qh3[idx]+1)%QDEPTH; qc3[idx]=qc3[idx]-1;
          if (is_hotspot(idx)) begin hs3=hs3+latency; hc3=hc3+1; if(latency>hm3) hm3=latency; end
          else begin bs3=bs3+latency; bc3=bc3+1; if(latency>bm3) bm3=latency; end
        end
      end
    end

    $display("=== [%s, HOT_PCT=%0d%%] v2 vs v3 ===", `ifdef HOTSPOT_CORNER "CORNER" `else "CENTER" `endif, HOT_PCT);
    $display("v2: hot 평균/최악=%0d/%0d, 배경 평균/최악=%0d/%0d", hs2/hc2, hm2, bs2/bc2, bm2);
    $display("v3: hot 평균/최악=%0d/%0d, 배경 평균/최악=%0d/%0d", hs3/hc3, hm3, bs3/bc3, bm3);
    $finish;
  end
endmodule
