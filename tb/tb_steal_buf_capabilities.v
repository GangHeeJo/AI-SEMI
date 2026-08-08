// 결합판이 두 원래 기능(cluster_buf의 재발화 방지, cluster2_steal의 비대칭부하 2배
// 처리량)을 결합 후에도 그대로 갖고 있는지 확인.
`timescale 1ns/1ps
module tb_steal_buf_capabilities;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;
  integer cyc;
  integer overrun0_cnt, generated0, delivered0;
  integer events_asym;

  function integer popcount4;
    input [3:0] v;
    begin
      popcount4 = v[0]+v[1]+v[2]+v[3];
    end
  endfunction

  initial begin
    rst = 1; arrival = 16'd0;
    @(posedge clk); #1;
    rst = 0;

    // --- 시나리오 A: 재발화(cluster_buf 유래 기능) -- 소스0이 매 사이클 재발화 ---
    overrun0_cnt = 0; generated0 = 0; delivered0 = 0;
    for (cyc = 0; cyc < 256; cyc = cyc + 1) begin
      arrival = 16'd1; // 소스0만 매 사이클
      generated0 = generated0 + 1;
      #1;
      if (overrun_w[0]) overrun0_cnt = overrun0_cnt + 1;
      @(posedge clk); #1;
      if (valid0 && row0==0 && col_mask0[0]) delivered0 = delivered0 + 1;
      if (valid1 && row1==0 && col_mask1[0]) delivered0 = delivered0 + 1;
    end
    $display("[retrigger] generated=%0d overrun=%0d delivered=%0d (cluster_buf 원래 결과: 0/256, 2-deep라 매 사이클 재발화도 대부분 안 밀림)",
      generated0, overrun0_cnt, delivered0);

    // --- 시나리오 B: 비대칭 부하(cluster2_steal 유래 기능) -- 중심 idle, 주변 포화 ---
    rst = 1; @(posedge clk); #1; rst = 0;
    events_asym = 0;
    arrival = 16'b1001_0000_0000_1001; // 행3,행0 전부(주변 포화), 중심(행1,2)은 0
    for (cyc = 0; cyc < 2000; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (valid0) events_asym = events_asym + popcount4(col_mask0);
      if (valid1) events_asym = events_asym + popcount4(col_mask1);
    end
    $display("[steal benefit] events=%0d avg/cycle=%0d.%0d (cluster2_steal 원래 결과: plain cluster2 대비 2배)",
      events_asym, events_asym/2000, (events_asym*10/2000)%10);

    $finish;
  end
endmodule
