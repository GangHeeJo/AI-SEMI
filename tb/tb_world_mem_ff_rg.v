`timescale 1ns/1ps
// world_mem_ff 랜덤 쓰기 20000회 vs 동작 모델, 끝에 4096칸 전부 읽어 대조.
module tb_world_mem_ff_rg;
  reg clk = 0, rst = 1, we = 0, pol = 0; reg [11:0] addr = 0, rd_addr = 0; wire rd_valid, rd_pol;
  world_mem_ff_rg dut(.clk(clk), .rst(rst), .we(we), .addr(addr), .pol(pol), .rd_addr(rd_addr), .rd_valid(rd_valid), .rd_pol(rd_pol));
  always #2.5 clk = ~clk;
  reg mv [0:4095]; reg mp [0:4095]; integer i, errs = 0, seed = 7;
  initial begin
    for (i = 0; i < 4096; i = i + 1) begin mv[i] = 0; mp[i] = 0; end
    repeat (3) @(posedge clk); #1 rst = 0;
    for (i = 0; i < 20000; i = i + 1) begin
      @(negedge clk); we = ($random(seed) & 3) != 0; addr = $random(seed); pol = $random(seed);
      if (we) begin mv[addr] = 1; mp[addr] = pol; end
    end
    @(negedge clk); we = 0;
    for (i = 0; i < 4096; i = i + 1) begin
      rd_addr = i; #1;
      if (rd_valid !== mv[i] || (mv[i] && rd_pol !== mp[i])) errs = errs + 1;
    end
    if (errs == 0) $display("WORLD_MEM_FF_RG_PASS"); else $display("WORLD_MEM_FF_RG_FAIL errs=%0d", errs);
    $finish;
  end
endmodule
