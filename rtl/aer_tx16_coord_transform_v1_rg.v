// 기준선: aer_tx16_coord_transform_v1 + world_mem_ff_rg(행 게이팅 메모리), 코어 클록은 항상 켬. blink 버전과 포트 동일(core_clk_on은 항상 1).
module aer_tx16_coord_transform_v1_rg (
  input clk, rst, input [15:0] arrival, polarity_in, input [7:0] theta_idx, output [15:0] overrun, output [7:0] wmem_overrun,
  input [11:0] rd_addr, output rd_valid, rd_pol, output core_clk_on
);
  wire we, pol; wire [11:0] ad; assign core_clk_on = 1'b1;
  aer_tx16_coord_transform_v1 u_core (.clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .theta_idx(theta_idx), .overrun(overrun), .wmem_overrun(wmem_overrun), .world_we(we), .world_addr(ad), .world_pol(pol));
  world_mem_ff_rg #(.ADDR_BITS(12)) u_mem (.clk(clk), .rst(rst), .we(we), .addr(ad), .pol(pol), .rd_addr(rd_addr), .rd_valid(rd_valid), .rd_pol(rd_pol));
endmodule
