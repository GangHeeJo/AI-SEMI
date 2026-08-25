// pressure-aware 2-way 중재기 -- arbiter2(순수 round-robin)에 "한쪽만 urgent(꽉 찬
// source가 있음)면 그쪽을 우선"하는 규칙을 얹음. 둘 다 urgent이거나 둘 다 아니면 기존
// round-robin 그대로(제안 그대로). 기아 방지: 같은 쪽을 urgency로 연속 2번 넘게 우선시키면
// 3번째부턴 강제로 RR로 돌아감(consec_override 2비트 포화 카운터) -- 상대 행이 무한정
// 밀리는 걸 막는 fairness guard.
module arbiter2_pressure(
  input        clk,
  input        rst,
  input  [1:0] req,
  input  [1:0] urgent, // req와 같은 비트 순서, "이 후보 안에 pending_cnt==2인 source가 있음"
  output [1:0] gnt
);
  reg last_gnt;
  reg [1:0] consec_override;

  wire prefer1 = last_gnt == 1'b0;
  wire rr_pick1 = req[1] & (prefer1 | ~req[0]);

  wire only0_urgent = req[0] & urgent[0] & ~(req[1] & urgent[1]);
  wire only1_urgent = req[1] & urgent[1] & ~(req[0] & urgent[0]);
  wire force_rr = (consec_override >= 2'd2);

  wire pick1 = force_rr ? rr_pick1
             : only1_urgent ? 1'b1
             : only0_urgent ? 1'b0
             : rr_pick1;

  assign gnt[1] = req[1] & pick1;
  assign gnt[0] = req[0] & ~gnt[1];

  wire is_override = !force_rr && (only0_urgent || only1_urgent);

  always @(posedge clk) begin
    if (rst) begin
      last_gnt <= 1'b1;
      consec_override <= 2'd0;
    end else if (|req) begin
      last_gnt <= gnt[1];
      if (is_override) consec_override <= consec_override + 2'd1;
      else consec_override <= 2'd0;
    end
  end
endmodule
