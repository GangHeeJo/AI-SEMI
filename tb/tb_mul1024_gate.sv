`timescale 1ns/1ps
// run_sim.sh용 (aer_tx16_coord_transform_mul1024, 외부 SRAM 쓰기 포트 버전): RTL 실행과 게이트(+SDF) 실행이 같은 출력 파일을 내는지 diff로 확인한다.
// 무작위 이벤트 6000사이클(소스 16개, 극성, 10비트 회전각이 가끔 바뀜) 동안 overrun과 월드 쓰기 포트(we, {y,x}, pol)를 매 사이클 기록, 이어서 400사이클 드레인.
`ifndef PERV
`define PERV 5.2
`endif
module tb;
  parameter real PER = `PERV;
  reg clk = 0; always #(PER/2) clk = ~clk;
  reg rst = 1; reg [15:0] arrival = 0, polarity_in = 0; reg [9:0] theta_idx = 0;
  wire [15:0] overrun; wire [7:0] wmem_overrun; wire world_we; wire [19:0] world_addr; wire world_pol;
  aer_tx16_coord_transform_mul1024 dut(.clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .theta_idx(theta_idx),
      .overrun(overrun), .wmem_overrun(wmem_overrun), .world_we(world_we), .world_addr(world_addr), .world_pol(world_pol));
`ifdef SDF
  initial $sdf_annotate(`SDF, dut, , "sdf.log", "MAXIMUM");
`endif
  integer fd, n, seed, nw;
  initial begin
    seed = 4242; nw = 0; fd = $fopen(`OUTF, "w");
    repeat (4) @(posedge clk); #(0.1*PER) rst = 0;
    for (n = 0; n < 6400; n = n + 1) begin
      @(posedge clk); #(0.1*PER);
      if (n < 6000) begin
        arrival = (($random(seed) & 7) == 0) ? ($random(seed) & $random(seed) & $random(seed)) : 16'd0;
        polarity_in = $random(seed); if ((n & 63) == 0) theta_idx = $random(seed);
      end else arrival = 0;
      #(0.8*PER);
      if (world_we === 1'b1) begin nw = nw + 1; $fdisplay(fd, "%0d w %h %b ov=%h wo=%h", n, world_addr, world_pol, overrun, wmem_overrun); end
      else if (overrun !== 16'h0000 || wmem_overrun !== 8'h00) $fdisplay(fd, "%0d - ov=%h wo=%h", n, overrun, wmem_overrun);
    end
    $fdisplay(fd, "writes=%0d", nw);
    $display("TB_DONE valid_cells=%0d", nw);
    $fclose(fd); $finish;
  end
endmodule
