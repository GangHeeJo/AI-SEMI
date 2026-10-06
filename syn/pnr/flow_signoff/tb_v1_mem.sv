`timescale 1ns/1ps
// run_sim.sh용: RTL 실행과 게이트(+SDF) 실행이 같은 출력 파일을 내는지 diff로 확인한다.
// 1단계: 무작위 이벤트 6000사이클(소스 16개, 극성, 회전각 변화) -> overrun 관찰. 2단계: 읽기 포트로 월드 메모리 4096칸 전부 스캔.
module tb;
  parameter real PER = 5.0;
  reg clk = 0; always #(PER/2) clk = ~clk;
  reg rst = 1; reg [15:0] arrival = 0, polarity_in = 0; reg [7:0] theta_idx = 0; reg [11:0] rd_addr = 0;
  wire [15:0] overrun; wire [7:0] wmem_overrun; wire rd_valid, rd_pol;
  aer_tx16_coord_transform_v1_mem dut(.clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .theta_idx(theta_idx),
      .overrun(overrun), .wmem_overrun(wmem_overrun), .rd_addr(rd_addr), .rd_valid(rd_valid), .rd_pol(rd_pol));
`ifdef SDF
  initial $sdf_annotate(`SDF, dut, , "sdf.log", "MAXIMUM");
`endif
  integer fd, n, seed, nvalid;
  initial begin
    seed = 4242; nvalid = 0; fd = $fopen(`OUTF, "w");
    repeat (4) @(posedge clk); #(0.1*PER) rst = 0;
    for (n = 0; n < 6000; n = n + 1) begin
      @(posedge clk); #(0.1*PER);
      arrival = (($random(seed) & 7) == 0) ? ($random(seed) & $random(seed) & $random(seed)) : 16'd0;
      polarity_in = $random(seed); if ((n & 63) == 0) theta_idx = $random(seed);
      #(0.8*PER); $fdisplay(fd, "%0d ov=%h wo=%h", n, overrun, wmem_overrun);
    end
    arrival = 0;
    repeat (200) @(posedge clk);
    for (n = 0; n < 4096; n = n + 1) begin
      @(posedge clk); #(0.1*PER); rd_addr = n; #(0.8*PER);
      if (rd_valid === 1'b1) begin nvalid = nvalid + 1; $fdisplay(fd, "m%0d 1 %b", n, rd_pol); end
      else $fdisplay(fd, "m%0d %b", n, rd_valid);
    end
    $fdisplay(fd, "valid_cells=%0d", nvalid);
    $display("TB_DONE valid_cells=%0d", nvalid);
    $fclose(fd); $finish;
  end
endmodule
