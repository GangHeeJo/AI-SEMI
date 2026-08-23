// cluster2 활동도 기반(VCD) 전력 측정용 TB. tb_aer16_base_vcd.v와 같은 방법론
// (timescale 1ns/1ps 명시 필수 -- Genus VCD 파서가 기본 1s 단위를 거부함, STIM-1010).
// ARRIVAL_PCT를 매개변수로 받아 저부하/기존부하 두 지점을 각각 다른 VCD 파일로 생성.
`timescale 1ns/1ps
module tb_cluster2_vcd;
  parameter CYCLES = 3000;
  parameter ARRIVAL_PCT = 15;
  parameter DUMPFILE = "sim/vcd/cluster2_l15.vcd";

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2 dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  event_scoreboard #(.N(16), .QDEPTH(64)) score();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, c, idx, lat;

  initial begin
    $dumpfile(DUMPFILE);
    $dumpvars(0, tb_cluster2_vcd);

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

      if (valid0) for (c = 0; c < 4; c = c + 1)
        if (col_mask0[c]) begin idx = row0*4 + c; if (score.qcount[idx] > 0) lat = score.record_departure(idx, cyc); end
      if (valid1) for (c = 0; c < 4; c = c + 1)
        if (col_mask1[c]) begin idx = row1*4 + c; if (score.qcount[idx] > 0) lat = score.record_departure(idx, cyc); end
    end

    $display("VCD 생성 완료: %s (%0d cycles, ARRIVAL_PCT=%0d%%)", DUMPFILE, CYCLES, ARRIVAL_PCT);
    $finish;
  end
endmodule
