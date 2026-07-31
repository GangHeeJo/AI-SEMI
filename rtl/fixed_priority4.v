// 전통적 방식 ② — 고정 우선순위(fixed priority) 중재기.
// 항상 번호가 낮은 요청자가 이긴다 (Wei 2019가 지적한 "고정 잡음" 문제의 기준선).
module fixed_priority4(
  input        clk,
  input        rst,
  input  [3:0] req,
  output [3:0] gnt
);
  assign gnt = req & (~req + 1'b1); // req 중 최하위(=가장 우선순위 높은) set bit만 통과
endmodule
