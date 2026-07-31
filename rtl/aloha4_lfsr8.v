// 전통적 방식 ①(개선판 3) — 8비트 LFSR(주기 255, 다항식 x^8+x^6+x^5+x^4+1) 기반 백오프.
// 이전 시도(aloha4_lfsr.v)의 문제: 4개 LFSR을 1,2,4,8로 시딩했더니 모두 "같은 순환열의
// 1~3스텝 차이" 위상이라 사실상 서로 강하게 상관돼 있었음(req2가 계속 불리한 결과로 확인됨).
// 이번엔 255주기를 4등분한 지점(0,63,127,191번째 상태값)을 시드로 써서 위상을 최대한 벌림.
module aloha4_lfsr8(
  input        clk,
  input        rst,
  input  [3:0] req,
  output [3:0] gnt
);
  reg [7:0] lfsr0, lfsr1, lfsr2, lfsr3;
  reg [2:0] backoff [0:3];
  wire [3:0] eff_req;
  wire [2:0] active_count;
  wire collision;

  assign eff_req[0] = req[0] & (backoff[0] == 0);
  assign eff_req[1] = req[1] & (backoff[1] == 0);
  assign eff_req[2] = req[2] & (backoff[2] == 0);
  assign eff_req[3] = req[3] & (backoff[3] == 0);

  assign active_count = eff_req[0] + eff_req[1] + eff_req[2] + eff_req[3];
  assign collision = (active_count > 3'd1);
  assign gnt = (active_count == 3'd1) ? eff_req : 4'b0000;

  function [7:0] lfsr_next;
    input [7:0] s;
    begin
      lfsr_next = {s[6:0], s[7] ^ s[5] ^ s[4] ^ s[3]};
    end
  endfunction

  always @(posedge clk) begin
    if (rst) begin
      // 255주기를 4등분한 위치의 상태값(파이썬으로 계산해 검증함) — 서로 최대한 위상이 먼 시드
      lfsr0 <= 8'd1; lfsr1 <= 8'd172; lfsr2 <= 8'd197; lfsr3 <= 8'd70;
      backoff[0] <= 0; backoff[1] <= 0; backoff[2] <= 0; backoff[3] <= 0;
    end else begin
      lfsr0 <= lfsr_next(lfsr0);
      lfsr1 <= lfsr_next(lfsr1);
      lfsr2 <= lfsr_next(lfsr2);
      lfsr3 <= lfsr_next(lfsr3);

      if (backoff[0] != 0) backoff[0] <= backoff[0] - 3'd1;
      else if (collision && eff_req[0]) backoff[0] <= lfsr0[2:0] + 3'd1;

      if (backoff[1] != 0) backoff[1] <= backoff[1] - 3'd1;
      else if (collision && eff_req[1]) backoff[1] <= lfsr1[2:0] + 3'd1;

      if (backoff[2] != 0) backoff[2] <= backoff[2] - 3'd1;
      else if (collision && eff_req[2]) backoff[2] <= lfsr2[2:0] + 3'd1;

      if (backoff[3] != 0) backoff[3] <= backoff[3] - 3'd1;
      else if (collision && eff_req[3]) backoff[3] <= lfsr3[2:0] + 3'd1;
    end
  end
endmodule
