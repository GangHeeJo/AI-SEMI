// lane stealing의 실제 이득을 보여주는 표적 시나리오: 중심(행1,2)은 완전히 idle,
// 주변(행0,3)은 완전포화(매 사이클 8개 소스 전부 요청). cluster2는 주변 안에서
// 행0/행3이 매 사이클 경쟁하므로 2사이클에 한 행씩(평균 4개/cycle) 나가지만,
// cluster2_steal은 중심이 노는 lane0을 빌려 행0/행3을 매 사이클 동시에(8개/cycle)
// 내보내야 함 -- 이 차이를 직접 측정.
`timescale 1ns/1ps
module tb_cluster2_steal_benefit;
  parameter CYCLES = 2000;

  reg clk = 0;
  reg rst;
  reg [15:0] req;

  wire valid0_a; wire [1:0] row0_a; wire [3:0] col_mask0_a;
  wire valid1_a; wire [1:0] row1_a; wire [3:0] col_mask1_a;
  aer_tx16_trad_rowcol_fovea_cluster2 plain(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_a), .row0(row0_a), .col_mask0(col_mask0_a),
    .valid1(valid1_a), .row1(row1_a), .col_mask1(col_mask1_a));

  wire valid0_b; wire [1:0] row0_b; wire [3:0] col_mask0_b;
  wire valid1_b; wire [1:0] row1_b; wire [3:0] col_mask1_b;
  aer_tx16_trad_rowcol_fovea_cluster2_steal steal(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_b), .row0(row0_b), .col_mask0(col_mask0_b),
    .valid1(valid1_b), .row1(row1_b), .col_mask1(col_mask1_b));

  always #5 clk = ~clk;

  integer cyc;
  integer events_plain, events_steal;

  function integer popcount4(input [3:0] v);
    popcount4 = v[0]+v[1]+v[2]+v[3];
  endfunction

  initial begin
    rst = 1; req = 16'd0; events_plain = 0; events_steal = 0;
    @(posedge clk); #1;
    rst = 0;
    req = 16'b1001_0000_0000_1001; // 행3, 행0 전부 요청(peripheral saturation), 중심(행1,2)은 0

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (valid0_a) events_plain = events_plain + popcount4(col_mask0_a);
      if (valid1_a) events_plain = events_plain + popcount4(col_mask1_a);
      if (valid0_b) events_steal = events_steal + popcount4(col_mask0_b);
      if (valid1_b) events_steal = events_steal + popcount4(col_mask1_b);
    end

    $display("cluster2(plain)       events=%0d avg/cycle=%0d.%0d", events_plain,
      events_plain/CYCLES, (events_plain*10/CYCLES)%10);
    $display("cluster2_steal        events=%0d avg/cycle=%0d.%0d", events_steal,
      events_steal/CYCLES, (events_steal*10/CYCLES)%10);
    $finish;
  end
endmodule
