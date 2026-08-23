// row-trim(§86)이 cluster2_steal_buf에도 무수정으로 적용된다는 이전 주장을 검증하려고
// 만듦. steal 메커니즘(코드 직독)이 row0/row1의 값 범위를 CENTER_MASK/PERIPH_MASK
// 제한(row0∈{1,2}, row1∈{0,3})보다 넓힐 수 있는지 실제로 도달하는지 확인.
`timescale 1ns/1ps
module tb_steal_buf_row_reachability;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;

  integer rng_seed = 3;
  integer cyc, s, draw;
  reg [3:0] row0_seen, row1_seen; // 비트0~3 = row값 0~3 관측여부
  integer steal_to_center_cnt, steal_to_periph_cnt;

  initial begin
    row0_seen = 4'd0; row1_seen = 4'd0;
    steal_to_center_cnt = 0; steal_to_periph_cnt = 0;
    rst = 1; arrival = 16'd0;
    @(posedge clk); #1; rst = 0;

    // 일부러 편중된 트래픽도 섞어서 steal 조건(한쪽 완전유휴+반대쪽 양쪽행 동시활성)을
    // 적극적으로 유발 -- 순수 균등 랜덤이면 이 조건이 거의 안 나올 수 있음.
    for (cyc = 0; cyc < 30000; cyc = cyc + 1) begin
      arrival = 16'd0;
      if (cyc % 3 == 0) begin
        // 주변만 강하게(중심 유휴 유도)
        for (s = 0; s < 16; s = s + 1) begin
          draw = (($random(rng_seed) % 100 + 100) % 100);
          if ((s < 4 || s >= 12) && draw < 40) arrival[s] = 1'b1; // row0,row3 소스만
        end
      end else if (cyc % 3 == 1) begin
        // 중심만 강하게(주변 유휴 유도)
        for (s = 0; s < 16; s = s + 1) begin
          draw = (($random(rng_seed) % 100 + 100) % 100);
          if ((s >= 4 && s < 12) && draw < 40) arrival[s] = 1'b1; // row1,row2 소스만
        end
      end else begin
        for (s = 0; s < 16; s = s + 1) begin
          draw = (($random(rng_seed) % 100 + 100) % 100);
          if (draw < 15) arrival[s] = 1'b1;
        end
      end
      @(posedge clk); #1;
      if (valid0) row0_seen[row0] = 1'b1;
      if (valid1) row1_seen[row1] = 1'b1;
      if (dut.steal_to_center) steal_to_center_cnt = steal_to_center_cnt + 1;
      if (dut.steal_to_periph) steal_to_periph_cnt = steal_to_periph_cnt + 1;
    end

    $display("row0_seen(bitmap, bit_i=row i observed)=%b row1_seen=%b", row0_seen, row1_seen);
    $display("steal_to_center_cnt=%0d steal_to_periph_cnt=%0d (out of 30000 cycles)",
      steal_to_center_cnt, steal_to_periph_cnt);
    $finish;
  end
endmodule
