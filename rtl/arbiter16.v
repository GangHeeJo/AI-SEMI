// 16-input round-robin arbiter (synchronous) — arbiter4.v/arbiter8.v와 동일 패턴을 16비트로 일반화.
// "전통적(naive) AER" 비교용 flat 중재기: 행-열 계층 분해 없이 16개 소스를 한 단계로 직접 중재.
module arbiter16(
  input         clk,
  input         rst,
  input  [15:0] req,
  output [15:0] gnt
);
  reg [3:0] last_gnt;

  wire [15:0] req_rot = {req, req} >> (last_gnt + 1);
  wire [15:0] gnt_rot = req_rot & (~req_rot + 1'b1);
  assign gnt = (gnt_rot << (last_gnt + 1)) | (gnt_rot >> (16 - (last_gnt + 1)));

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
    if (rst)
      last_gnt <= 4'd15;
    else if (|req)
      last_gnt <= idx16(gnt);
  end
endmodule
