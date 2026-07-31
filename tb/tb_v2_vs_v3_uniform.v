// v2(STD만)와 v3(STD+DS)를 완전히 동일한 무작위(균일, 핫스팟 없음) 트래픽으로
// 동시에 구동해 평균/최악 지연시간과 공정성(행별 방문횟수 max-min)을 직접 비교.
// v2의 알려진 트레이드오프(균일 트래픽에서 평균지연 악화)를 v3의 DS(강제 냉각)가
// 완화하는지, 혹은 오히려 hot 추적 성능을 깎아먹기만 하는지 확인하는 게 목적.
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

  always #5 clk = ~clk;

  integer rng_seed = 1;
  // v2/v3는 각자 독립된 큐 상태를 가져야 공정하게 비교됨(같은 도착 이벤트를 각자 own queue에 넣음)
  integer q2 [0:15][0:QDEPTH-1]; integer qh2 [0:15]; integer qc2 [0:15];
  integer q3 [0:15][0:QDEPTH-1]; integer qh3 [0:15]; integer qc3 [0:15];
  integer cyc, i, idx, latency;
  integer sum2, cnt2, max2, visits2 [0:15];
  integer sum3, cnt3, max3, visits3 [0:15];

  initial begin
    rst = 1; req = 16'd0; new_event = 16'd0;
    sum2=0; cnt2=0; max2=0; sum3=0; cnt3=0; max3=0;
    for (i=0;i<16;i=i+1) begin
      qh2[i]=0; qc2[i]=0; visits2[i]=0;
      qh3[i]=0; qc3[i]=0; visits3[i]=0;
    end
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      new_event = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < PCT) begin
          new_event[i] = 1'b1;
          if (qc2[i] < QDEPTH) begin q2[i][(qh2[i]+qc2[i])%QDEPTH] = cyc; qc2[i] = qc2[i]+1; end
          if (qc3[i] < QDEPTH) begin q3[i][(qh3[i]+qc3[i])%QDEPTH] = cyc; qc3[i] = qc3[i]+1; end
        end
      end
      for (i = 0; i < 16; i = i + 1) req[i] = (qc2[i] > 0) || (qc3[i] > 0);
      // 주의: req는 v2/v3 공통 입력이라 OR로 묶되, 실제 소비는 각자 own qc로 판단.
      // 한쪽 큐가 먼저 비면 그 셀의 req는 다른쪽 큐 때문에 계속 1일 수 있으나,
      // idx8 매칭 시 qc==0이면 latency 집계에서 자연히 제외되므로 통계엔 영향 없음.

      @(posedge clk); #1;

      if (v2_ev) begin
        idx = v2_row*4+v2_col;
        if (qc2[idx] > 0) begin
          latency = cyc - q2[idx][qh2[idx]];
          qh2[idx]=(qh2[idx]+1)%QDEPTH; qc2[idx]=qc2[idx]-1;
          sum2=sum2+latency; cnt2=cnt2+1; if (latency>max2) max2=latency;
          visits2[idx]=visits2[idx]+1;
        end
      end
      if (v3_ev) begin
        idx = v3_row*4+v3_col;
        if (qc3[idx] > 0) begin
          latency = cyc - q3[idx][qh3[idx]];
          qh3[idx]=(qh3[idx]+1)%QDEPTH; qc3[idx]=qc3[idx]-1;
          sum3=sum3+latency; cnt3=cnt3+1; if (latency>max3) max3=latency;
          visits3[idx]=visits3[idx]+1;
        end
      end
    end

    begin : fairness
      integer vmax2, vmin2, vmax3, vmin3;
      vmax2=visits2[0]; vmin2=visits2[0]; vmax3=visits3[0]; vmin3=visits3[0];
      for (i=1;i<16;i=i+1) begin
        if (visits2[i]>vmax2) vmax2=visits2[i]; if (visits2[i]<vmin2) vmin2=visits2[i];
        if (visits3[i]>vmax3) vmax3=visits3[i]; if (visits3[i]<vmin3) vmin3=visits3[i];
      end
      $display("=== 균일 트래픽(PCT=%0d%%) v2 vs v3 ===", PCT);
      $display("v2: 평균지연=%0d 최악지연=%0d max-min(공정성)=%0d", sum2/cnt2, max2, vmax2-vmin2);
      $display("v3: 평균지연=%0d 최악지연=%0d max-min(공정성)=%0d", sum3/cnt3, max3, vmax3-vmin3);
    end
    $finish;
  end
endmodule
