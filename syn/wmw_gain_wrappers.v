// Genus 비교 합성용: world_mem_writer_gain의 FIFO 깊이만 바꾼 얇은 래퍼(포트 동일).
module wmw_gain_d8 (input clk, rst, input [7:0] wr_valid, input [47:0] wr_x, wr_y, input [7:0] wr_pol, output [7:0] wr_overrun, wr_shed, output stall, world_we, output [11:0] world_addr, output world_pol);
  world_mem_writer_gain #(.FIFO_DEPTH(8)) u (.*);
endmodule
module wmw_gain_d16 (input clk, rst, input [7:0] wr_valid, input [47:0] wr_x, wr_y, input [7:0] wr_pol, output [7:0] wr_overrun, wr_shed, output stall, world_we, output [11:0] world_addr, output world_pol);
  world_mem_writer_gain #(.FIFO_DEPTH(16)) u (.*);
endmodule
