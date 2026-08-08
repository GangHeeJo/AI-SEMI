// aer_tx16_trad_rowcol_fovea.v + "사카드 억제(Saccadic Suppression)" — 사람이 눈을
// 빠르게 움직일 때(사카드) 그 순간의 시각입력을 의식적으로 억제하는 것의 저비용
// 아날로그. 반응형으로 "지금 시끄러운가"를 추측하는 게 아니라(측면억제/사카드스냅/
// 예측부호화가 약했던 이유), Digital 2차의 회전 모터 제어 신호에서 "지금 회전
// 중이다"라는 사실을 **이미 확실히 아는 정보**로 그대로 받아씀 — fovea의 "중심이
// 중요하다"는 가정과 같은 부류(구조적으로 참인 정보, 반응형 추측 아님).
//
// `rotating`=1이면 내부 req를 전부 0으로 게이팅해서 버스 중재/전송을 멈춘다(회전
// 중엔 어차피 전 화면이 모션블러라 의미 없는 이벤트 폭주이므로, 그걸 큐에 담아
// 버스를 막아두지 않고 아예 무시). RTL 변경은 req 게이팅 한 줄뿐이라 사실상 공짜.
module aer_tx16_trad_rowcol_fovea_saccsup #(
  parameter WEIGHT = 5
) (
  input         clk,
  input         rst,
  input         rotating, // 1=센서가 빠르게 회전 중(모터 제어 신호에서 직접 옴)
  input  [15:0] req,
  output        valid,
  output [3:0]  addr
);
  wire [15:0] req_gated = rotating ? 16'd0 : req;
  aer_tx16_trad_rowcol_fovea #(.WEIGHT(WEIGHT)) core(
    .clk(clk), .rst(rst), .req(req_gated), .valid(valid), .addr(addr));
endmodule
