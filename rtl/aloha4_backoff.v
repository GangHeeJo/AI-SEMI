// 전통적 방식 ①(개선) — 충돌 시 임의 지연 후 재시도하는 ALOHA-with-backoff.
// 매번 무조건 재시도하는 단순 aloha4.v보다 현실적인 "무질서 접근" 재현.
module aloha4_backoff(
  input        clk,
  input        rst,
  input  [3:0] req,
  output [3:0] gnt
);
  reg [2:0] backoff [0:3];
  reg [2:0] entropy; // 진짜 난수 대신 쓰는 자유구동 카운터(합성 가능한 pseudo-random)

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

  always @(posedge clk) begin
    if (rst) begin
      entropy <= 3'd1;
      for (k = 0; k < 4; k = k + 1) backoff[k] <= 3'd0;
    end else begin
      entropy <= entropy + 3'd1;
      for (k = 0; k < 4; k = k + 1) begin
        if (backoff[k] != 0)
          backoff[k] <= backoff[k] - 3'd1;
        else if (collision && eff_req[k])
          backoff[k] <= entropy + k[2:0] + 3'd1; // 충돌한 애들끼리 서로 다른 지연을 갖도록 분산
      end
    end
  end
endmodule
