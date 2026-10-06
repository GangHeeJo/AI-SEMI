// 월드 메모리(world_mem_ff, FF 배열)까지 포함한 쓰기 경로 전력 비교용 top 3종(FIFO 깊이 8 고정). 포트 동일.
module wmw_top_base (input clk, rst, input [7:0] wr_valid, input [47:0] wr_x, wr_y, input [7:0] wr_pol, input [11:0] rd_addr, output [7:0] wr_overrun, output rd_valid, rd_pol);
  wire we, pol; wire [11:0] ad; wire stall;
  world_mem_writer #(.FIFO_DEPTH(8)) w (.clk(clk), .rst(rst), .wr_valid(wr_valid), .wr_x(wr_x), .wr_y(wr_y), .wr_pol(wr_pol), .wr_overrun(wr_overrun), .stall(stall), .world_we(we), .world_addr(ad), .world_pol(pol));
  world_mem_ff m (.clk(clk), .rst(rst), .we(we), .addr(ad), .pol(pol), .rd_addr(rd_addr), .rd_valid(rd_valid), .rd_pol(rd_pol));
endmodule
module wmw_top_c64 (input clk, rst, input [7:0] wr_valid, input [47:0] wr_x, wr_y, input [7:0] wr_pol, input [11:0] rd_addr, output [7:0] wr_overrun, output rd_valid, rd_pol);
  wire we, pol, dd, stall; wire [11:0] ad; wire [7:0] shed;
  world_mem_writer_gain #(.FIFO_DEPTH(8), .GAIN_EN(0), .CACHE_N(64)) w (.clk(clk), .rst(rst), .wr_valid(wr_valid), .wr_x(wr_x), .wr_y(wr_y), .wr_pol(wr_pol), .wr_overrun(wr_overrun), .wr_shed(shed), .wr_dedup(dd), .stall(stall), .world_we(we), .world_addr(ad), .world_pol(pol));
  world_mem_ff m (.clk(clk), .rst(rst), .we(we), .addr(ad), .pol(pol), .rd_addr(rd_addr), .rd_valid(rd_valid), .rd_pol(rd_pol));
endmodule
module wmw_top_c256 (input clk, rst, input [7:0] wr_valid, input [47:0] wr_x, wr_y, input [7:0] wr_pol, input [11:0] rd_addr, output [7:0] wr_overrun, output rd_valid, rd_pol);
  wire we, pol, dd, stall; wire [11:0] ad; wire [7:0] shed;
  world_mem_writer_gain #(.FIFO_DEPTH(8), .GAIN_EN(0), .CACHE_N(256)) w (.clk(clk), .rst(rst), .wr_valid(wr_valid), .wr_x(wr_x), .wr_y(wr_y), .wr_pol(wr_pol), .wr_overrun(wr_overrun), .wr_shed(shed), .wr_dedup(dd), .stall(stall), .world_we(we), .world_addr(ad), .world_pol(pol));
  world_mem_ff m (.clk(clk), .rst(rst), .we(we), .addr(ad), .pol(pol), .rd_addr(rd_addr), .rd_valid(rd_valid), .rd_pol(rd_pol));
endmodule

// ---- 행 단위 클록 게이팅 메모리(world_mem_ff_rg) 버전 ----
// 월드 메모리(world_mem_ff, FF 배열)까지 포함한 쓰기 경로 전력 비교용 top 3종(FIFO 깊이 8 고정). 포트 동일.
module wmw_rg_base (input clk, rst, input [7:0] wr_valid, input [47:0] wr_x, wr_y, input [7:0] wr_pol, input [11:0] rd_addr, output [7:0] wr_overrun, output rd_valid, rd_pol);
  wire we, pol; wire [11:0] ad; wire stall;
  world_mem_writer #(.FIFO_DEPTH(8)) w (.clk(clk), .rst(rst), .wr_valid(wr_valid), .wr_x(wr_x), .wr_y(wr_y), .wr_pol(wr_pol), .wr_overrun(wr_overrun), .stall(stall), .world_we(we), .world_addr(ad), .world_pol(pol));
  world_mem_ff_rg m (.clk(clk), .rst(rst), .we(we), .addr(ad), .pol(pol), .rd_addr(rd_addr), .rd_valid(rd_valid), .rd_pol(rd_pol));
endmodule
module wmw_rg_c64 (input clk, rst, input [7:0] wr_valid, input [47:0] wr_x, wr_y, input [7:0] wr_pol, input [11:0] rd_addr, output [7:0] wr_overrun, output rd_valid, rd_pol);
  wire we, pol, dd, stall; wire [11:0] ad; wire [7:0] shed;
  world_mem_writer_gain #(.FIFO_DEPTH(8), .GAIN_EN(0), .CACHE_N(64)) w (.clk(clk), .rst(rst), .wr_valid(wr_valid), .wr_x(wr_x), .wr_y(wr_y), .wr_pol(wr_pol), .wr_overrun(wr_overrun), .wr_shed(shed), .wr_dedup(dd), .stall(stall), .world_we(we), .world_addr(ad), .world_pol(pol));
  world_mem_ff_rg m (.clk(clk), .rst(rst), .we(we), .addr(ad), .pol(pol), .rd_addr(rd_addr), .rd_valid(rd_valid), .rd_pol(rd_pol));
endmodule
module wmw_rg_c256 (input clk, rst, input [7:0] wr_valid, input [47:0] wr_x, wr_y, input [7:0] wr_pol, input [11:0] rd_addr, output [7:0] wr_overrun, output rd_valid, rd_pol);
  wire we, pol, dd, stall; wire [11:0] ad; wire [7:0] shed;
  world_mem_writer_gain #(.FIFO_DEPTH(8), .GAIN_EN(0), .CACHE_N(256)) w (.clk(clk), .rst(rst), .wr_valid(wr_valid), .wr_x(wr_x), .wr_y(wr_y), .wr_pol(wr_pol), .wr_overrun(wr_overrun), .wr_shed(shed), .wr_dedup(dd), .stall(stall), .world_we(we), .world_addr(ad), .world_pol(pol));
  world_mem_ff_rg m (.clk(clk), .rst(rst), .we(we), .addr(ad), .pol(pol), .rd_addr(rd_addr), .rd_valid(rd_valid), .rd_pol(rd_pol));
endmodule
