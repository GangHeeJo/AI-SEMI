// aer_tx16_coord_transform_v1 + world_mem_ff: 월드 메모리를 포함한 P&R/PPA 측정용 top. 기능 변경 없음(저장소만 안으로 들어옴), world_we/addr/pol은 내부 연결.
module aer_tx16_coord_transform_v1_mem (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  input  [15:0] polarity_in,
  input  [7:0]  theta_idx,
  output [15:0] overrun,
  output [7:0]  wmem_overrun,
  input  [11:0] rd_addr,
  output        rd_valid,
  output        rd_pol
);
  wire        world_we, world_pol;
  wire [11:0] world_addr;
  aer_tx16_coord_transform_v1 u_core (
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .theta_idx(theta_idx),
    .overrun(overrun), .wmem_overrun(wmem_overrun),
    .world_we(world_we), .world_addr(world_addr), .world_pol(world_pol)
  );
  world_mem_ff #(.ADDR_BITS(12)) u_mem (
    .clk(clk), .rst(rst), .we(world_we), .addr(world_addr), .pol(world_pol),
    .rd_addr(rd_addr), .rd_valid(rd_valid), .rd_pol(rd_pol)
  );
endmodule
