// "전통적(naive) AER" 송신기 — base(aer_tx16.v)의 개선(행-열 계층 + 버스트)을 적용하기 전 버전.
// 16개 이벤트원을 계층 분해 없이 arbiter16 하나로 직접 중재하고, 매 사이클 전체 주소(4bit)를
// 한 번에 보낸다(버스트 없음). base 대비 "우리가 실제로 채택한 개선"의 효과를 PPA로 비교하는 용도.
module aer_tx16_naive(
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg    valid,
  output reg [3:0] addr
);
  wire [15:0] gnt;
  arbiter16 arb(.clk(clk), .rst(rst), .req(req), .gnt(gnt));

  function [3:0] idx16;
    input [15:0] bits;
    begin
      if (bits[0]) idx16 = 4'd0;
      else if (bits[1]) idx16 = 4'd1;
      else if (bits[2]) idx16 = 4'd2;
      else if (bits[3]) idx16 = 4'd3;
      else if (bits[4]) idx16 = 4'd4;
      else if (bits[5]) idx16 = 4'd5;
      else if (bits[6]) idx16 = 4'd6;
      else if (bits[7]) idx16 = 4'd7;
      else if (bits[8]) idx16 = 4'd8;
      else if (bits[9]) idx16 = 4'd9;
      else if (bits[10]) idx16 = 4'd10;
      else if (bits[11]) idx16 = 4'd11;
      else if (bits[12]) idx16 = 4'd12;
      else if (bits[13]) idx16 = 4'd13;
      else if (bits[14]) idx16 = 4'd14;
      else idx16 = 4'd15;
    end
  endfunction

  always @(posedge clk) begin
    if (rst) begin
      valid <= 1'b0;
      addr  <= 4'd0;
    end else begin
      valid <= |gnt;
      addr  <= idx16(gnt);
    end
  end
endmodule
