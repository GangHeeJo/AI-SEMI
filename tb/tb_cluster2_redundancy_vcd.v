// cluster2+Dir7(redundancy suppression) 활동도(VCD) 전력 측정용 TB.
// tb_cluster2_vcd.v와 동일 방법론(timescale 1ns/1ps 필수) -- 같은 ARRIVAL_PCT/seed로
// 돌려서 순정 cluster2의 VCD 실측(8.580uW@15%, 4.687uW@3%)과 직접 비교 가능하게 함.
`timescale 1ns/1ps
module tb_cluster2_redundancy_vcd;
  parameter CYCLES = 3000;
  parameter ARRIVAL_PCT = 15;
  parameter DUMPFILE = "sim/vcd/cluster2_redundancy_l15.vcd";

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0; wire repeat0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1; wire repeat1;

  aer_tx16_trad_rowcol_fovea_cluster2_redundancy dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0), .repeat0(repeat0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1), .repeat1(repeat1));

  event_scoreboard #(.N(16), .QDEPTH(64)) score();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, c, idx, lat;

  initial begin
    $dumpfile(DUMPFILE);
    $dumpvars(0, tb_cluster2_redundancy_vcd);

    rst = 1; req = 16'd0;
    score.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < 16; i = i + 1)
        if ((($random(rng_seed) % 100 + 100) % 100) < ARRIVAL_PCT)
          score.record_arrival(i, cyc);
      for (i = 0; i < 16; i = i + 1)
        req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      if (dut.raw_valid0) for (c = 0; c < 4; c = c + 1)
        if (dut.raw_col_mask0[c]) begin idx = dut.raw_row0*4 + c; if (score.qcount[idx] > 0) lat = score.record_departure(idx, cyc); end
      if (dut.raw_valid1) for (c = 0; c < 4; c = c + 1)
        if (dut.raw_col_mask1[c]) begin idx = dut.raw_row1*4 + c; if (score.qcount[idx] > 0) lat = score.record_departure(idx, cyc); end
    end

    $display("VCD 생성 완료: %s (%0d cycles, ARRIVAL_PCT=%0d%%)", DUMPFILE, CYCLES, ARRIVAL_PCT);
    $finish;
  end
endmodule
