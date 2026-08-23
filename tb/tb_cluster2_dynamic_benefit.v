// cluster2_dynamic의 진짜 이득 지점: steal은 반대팀이 "완전히" idle이어야만 작동함.
// 여기선 주변팀이 완전 idle이 아니라 "가끔"(낮은 빈도)만 활동하는, steal이 거의
// 못 돕는 현실적인 상황을 만들어서, 중심팀(계속 포화)의 실제 처리량을 고정레인
// cluster2 vs cluster2_dynamic으로 비교한다.
`timescale 1ns/1ps
module tb_cluster2_dynamic_benefit;
  parameter CYCLES = 20000;
  parameter PERIPH_ARRIVAL_PCT = 3; // 주변팀은 가끔만(3%) -- steal 조건(완전 idle) 거의 안 만족

  reg clk = 0;
  reg rst;
  reg [15:0] req_fixed, req_dyn;

  wire valid0_f; wire [1:0] row0_f; wire [3:0] colmask0_f;
  wire valid1_f; wire [1:0] row1_f; wire [3:0] colmask1_f;
  wire valid0_d; wire [1:0] row0_d; wire [3:0] colmask0_d;
  wire valid1_d; wire [1:0] row1_d; wire [3:0] colmask1_d;

  aer_tx16_trad_rowcol_fovea_cluster2 tx_fixed(
    .clk(clk), .rst(rst), .req(req_fixed),
    .valid0(valid0_f), .row0(row0_f), .col_mask0(colmask0_f),
    .valid1(valid1_f), .row1(row1_f), .col_mask1(colmask1_f));
  aer_tx16_trad_rowcol_fovea_cluster2_dynamic tx_dyn(
    .clk(clk), .rst(rst), .req(req_dyn),
    .valid0(valid0_d), .row0(row0_d), .col_mask0(colmask0_d),
    .valid1(valid1_d), .row1(row1_d), .col_mask1(colmask1_d));

  always #5 clk = ~clk;

  integer rng_seed = 7;
  integer cyc, i, c, draw;
  // 중심행(1,2)=소스4~11 계속 포화(항상 요청 유지, 소스 자체가 무한 backlog라고 가정).
  // 주변행(0,3)=소스0~3,12~15는 낮은 빈도로 단발 이벤트.
  reg [15:0] periph_pending_f, periph_pending_d;
  integer center_delivered_f, center_delivered_d;
  integer periph_delivered_f, periph_delivered_d;

  initial begin
    rst = 1;
    req_fixed = 16'd0; req_dyn = 16'd0;
    periph_pending_f = 16'd0; periph_pending_d = 16'd0;
    center_delivered_f = 0; center_delivered_d = 0;
    periph_delivered_f = 0; periph_delivered_d = 0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      // 주변행 소스(0~3,12~15)에 낮은 빈도 단발 이벤트 추가
      for (i = 0; i < 16; i = i + 1) begin
        if (i < 4 || i >= 12) begin
          draw = (($random(rng_seed) % 100 + 100) % 100);
          if (draw < PERIPH_ARRIVAL_PCT) begin
            periph_pending_f[i] = 1'b1;
            periph_pending_d[i] = 1'b1;
          end
        end
      end
      // 중심행(4~11)은 항상 요청(무한 backlog), 주변행은 pending 상태 그대로 반영
      req_fixed = {periph_pending_f[15:12], 8'hFF, periph_pending_f[3:0]};
      req_dyn   = {periph_pending_d[15:12], 8'hFF, periph_pending_d[3:0]};

      @(posedge clk); #1;

      if (valid0_f) begin
        for (c = 0; c < 4; c = c + 1) if (colmask0_f[c]) begin
          if (row0_f == 1 || row0_f == 2) center_delivered_f = center_delivered_f + 1;
          else begin periph_delivered_f = periph_delivered_f + 1; periph_pending_f[row0_f*4+c] = 1'b0; end
        end
      end
      if (valid1_f) begin
        for (c = 0; c < 4; c = c + 1) if (colmask1_f[c]) begin
          if (row1_f == 1 || row1_f == 2) center_delivered_f = center_delivered_f + 1;
          else begin periph_delivered_f = periph_delivered_f + 1; periph_pending_f[row1_f*4+c] = 1'b0; end
        end
      end
      if (valid0_d) begin
        for (c = 0; c < 4; c = c + 1) if (colmask0_d[c]) begin
          if (row0_d == 1 || row0_d == 2) center_delivered_d = center_delivered_d + 1;
          else begin periph_delivered_d = periph_delivered_d + 1; periph_pending_d[row0_d*4+c] = 1'b0; end
        end
      end
      if (valid1_d) begin
        for (c = 0; c < 4; c = c + 1) if (colmask1_d[c]) begin
          if (row1_d == 1 || row1_d == 2) center_delivered_d = center_delivered_d + 1;
          else begin periph_delivered_d = periph_delivered_d + 1; periph_pending_d[row1_d*4+c] = 1'b0; end
        end
      end
    end

    $display("CYCLES=%0d PERIPH_ARRIVAL_PCT=%0d%%", CYCLES, PERIPH_ARRIVAL_PCT);
    $display("[cluster2 고정레인]  center_delivered=%0d (%.3f/cycle)  periph_delivered=%0d",
      center_delivered_f, center_delivered_f*1.0/CYCLES, periph_delivered_f);
    $display("[cluster2_dynamic]   center_delivered=%0d (%.3f/cycle)  periph_delivered=%0d",
      center_delivered_d, center_delivered_d*1.0/CYCLES, periph_delivered_d);
    $display("center throughput ratio(dynamic/fixed) = %.3f", center_delivered_d*1.0/center_delivered_f);
    $finish;
  end
endmodule
