// cluster2_steal_buf 활동도 기반(VCD) 전력 측정용 TB. arrival은 펄스 입력이므로
// (레벨 유지 아님) 도착 사이클에만 1로 세움 -- 결합판 native 계약 그대로.
`timescale 1ns/1ps
module tb_steal_buf_vcd;
  parameter CYCLES = 3000;
  parameter ARRIVAL_PCT = 15;
  parameter DUMPFILE = "sim/vcd/steal_buf_l15.vcd";

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

  integer rng_seed = 1;
  integer cyc, i;

  initial begin
    $dumpfile(DUMPFILE);
    $dumpvars(0, tb_steal_buf_vcd);

    rst = 1; arrival = 16'd0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      arrival = 16'd0;
      for (i = 0; i < 16; i = i + 1)
        if ((($random(rng_seed) % 100 + 100) % 100) < ARRIVAL_PCT)
          arrival[i] = 1'b1;

      @(posedge clk); #1;
    end

    $display("VCD 생성 완료: %s (%0d cycles, ARRIVAL_PCT=%0d%%)", DUMPFILE, CYCLES, ARRIVAL_PCT);
    $finish;
  end
endmodule
