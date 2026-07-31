// 전통적 방식 ① — 중재기 자체가 없는 무질서(ALOHA-style) 접근.
// 동시에 딱 한 명만 요청하면 성공(gnt), 두 명 이상 겹치면 충돌(collision)로 둘 다 실패.
// Boahen 2000이 비교했던 "unfettered access" 베이스라인(최대 처리량 18%)의 재현.
module aloha4(
  input        clk,
  input        rst,
  input  [3:0] req,
  output [3:0] gnt
);
  wire [2:0] req_count = req[0] + req[1] + req[2] + req[3];
  assign gnt = (req_count == 3'd1) ? req : 4'b0000;
endmodule
