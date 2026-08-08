// Boahen(2000)이 언급한 "탐욕적(greedy)/지역성 활용" 중재기 — 공정 회전 없이 항상
// 고정된 순서(0→1→2→3)로 가장 먼저 활성인 요청을 선택. 공정성은 희생하지만 회로가
// 더 단순해서 더 빠르거나 작을 수 있다는 게 문헌의 주장 — arbiter4.v(회전식)와
// 직접 비교해서 우리 규모(4-way 단일단)에서도 그 이득이 실제로 나타나는지 검증용.
module arbiter4_greedy(
  input        clk,
  input        rst,
  input  [3:0] req,
  output [3:0] gnt
);
  assign gnt = req & (~req + 1'b1); // 최하위 set bit만 선택(고정 우선순위, 회전 없음)
endmodule
