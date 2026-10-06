`timescale 1ns/1ps
// §216: 실제 DELTA 이벤트(tb/delta_events_64.txt)를 프레임 단위(32,000개)로 월드 쓰기 경로+메모리에 넣고 VCD를 덤프(Genus 활동도 전력용). 사용: -DTOPMOD=wmw_top_base|wmw_top_c64|wmw_top_c256 -DVCDF=\"x.vcd\" +T=8000
module tb_power_real;
  localparam NL = 8, E = 32000, NFR = 3;
  reg clk = 0, rst = 1; always #2.5 clk = ~clk;
  reg [NL-1:0] valid = 0; reg [47:0] wx = 0, wy = 0; reg [NL-1:0] wp = 0; reg [11:0] rd_addr = 0; wire [NL-1:0] ov; wire rv, rpol;
  `TOPMOD dut (.clk(clk), .rst(rst), .wr_valid(valid), .wr_x(wx), .wr_y(wy), .wr_pol(wp), .rd_addr(rd_addr), .wr_overrun(ov), .rd_valid(rv), .rd_pol(rpol));
  integer rx [0:NFR*E-1]; integer ry [0:NFR*E-1]; integer rp [0:NFR*E-1]; integer fd, i, fr, c, j, T, nw;
  initial begin
    if (!$value$plusargs("T=%d", T)) T = 8000;
    fd = $fopen("tb/delta_events_64.txt", "r");
    for (i = 0; i < NFR*E; i = i + 1) if ($fscanf(fd, "%d %d %d", rx[i], ry[i], rp[i]) != 3) begin $display("READ_FAIL"); $finish; end
    $fclose(fd);
    $dumpfile(`VCDF); $dumpvars(0, dut);
    repeat (4) @(posedge clk); #1 rst = 0;
    for (fr = 0; fr < NFR; fr = fr + 1) for (c = 0; c < T; c = c + 1) begin
      @(negedge clk); valid = 0;
      if (c < E / NL) for (j = 0; j < NL; j = j + 1) begin valid[j] = 1; wx[j*6 +: 6] = rx[fr*E + c*NL + j]; wy[j*6 +: 6] = ry[fr*E + c*NL + j]; wp[j] = rp[fr*E + c*NL + j]; end
    end
    @(negedge clk); valid = 0; repeat (200) @(posedge clk); $display("DONE"); $finish;
  end
endmodule
