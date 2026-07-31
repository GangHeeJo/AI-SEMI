// 전통적 방식 ①(개선판 2) — 요청자별 독립적인 LFSR(Linear Feedback Shift Register)로
// 백오프 지연을 정하는 ALOHA. aloha4_backoff.v의 "카운터+내 번호" 방식은 특정 요청자가
// 계속 불리한 타이밍에 몰리는 부작용이 있었음 — 각자 별도의 4비트 LFSR(주기 15,
// 다항식 x^4+x^3+1)을 두어 요청자 간 상관관계를 줄인다.
module aloha4_lfsr(
  input        clk,
  input        rst,
  input  [3:0] req,
  output [3:0] gnt
);
  reg [3:0] lfsr0, lfsr1, lfsr2, lfsr3;
  reg [2:0] backoff [0:3];
  wire [3:0] eff_req;
  wire [2:0] active_count;
  wire collision;
  integer k;

  assign eff_req[0] = req[0] & (backoff[0] == 0);
  assign eff_req[1] = req[1] & (backoff[1] == 0);
  assign eff_req[2] = req[2] & (backoff[2] == 0);
  assign eff_req[3] = req[3] & (backoff[3] == 0);

  assign active_count = eff_req[0] + eff_req[1] + eff_req[2] + eff_req[3];
  assign collision = (active_count > 3'd1);
  assign gnt = (active_count == 3'd1) ? eff_req : 4'b0000;

  wire [3:0] lfsr0_next = {lfsr0[2:0], lfsr0[3]^lfsr0[2]};
  wire [3:0] lfsr1_next = {lfsr1[2:0], lfsr1[3]^lfsr1[2]};
  wire [3:0] lfsr2_next = {lfsr2[2:0], lfsr2[3]^lfsr2[2]};
  wire [3:0] lfsr3_next = {lfsr3[2:0], lfsr3[3]^lfsr3[2]};

  always @(posedge clk) begin
    if (rst) begin
      lfsr0 <= 4'd1; lfsr1 <= 4'd2; lfsr2 <= 4'd4; lfsr3 <= 4'd8; // 서로 다른 0이 아닌 시드
      for (k = 0; k < 4; k = k + 1) backoff[k] <= 3'd0;
    end else begin
      lfsr0 <= lfsr0_next; lfsr1 <= lfsr1_next; lfsr2 <= lfsr2_next; lfsr3 <= lfsr3_next;

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
