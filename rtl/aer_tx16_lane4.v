// lane count 스윕(1=cluster, 2=cluster2, 4=이거)의 극단값. 행마다 전용 출력 레인을
// 주면 "어느 행이 이길지"를 다툴 대상 자체가 없어져서 row 중재기(center_arb/
// periph_arb, round/prefer_center)가 전부 필요 없어짐 -- cluster의 col_mask 비트맵
// 아이디어를 행 4개 전부에 동시 적용한 것뿐이라, 중재기가 하나도 안 남는다.
// fovea의 중심 가중치도 의미가 없어짐(모든 행이 매 사이클 무조건 서비스되므로 우선
//순위를 다툴 필요가 없음) -- 그래서 WEIGHT 파라미터도 없음.
// 대가는 핀 수: valid+col_mask 4비트 세트가 4개(레인당 5핀) = 20핀. cluster2(14핀)
// 보다도 훨씬 넓음 -- pin/area/power vs lane count 스윕의 한쪽 끝.
module aer_tx16_lane4 (
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg        valid0,
  output reg [3:0]  col_mask0, // 행0
  output reg        valid1,
  output reg [3:0]  col_mask1, // 행1
  output reg        valid2,
  output reg [3:0]  col_mask2, // 행2
  output reg        valid3,
  output reg [3:0]  col_mask3  // 행3
);
  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; col_mask0 <= 4'd0;
      valid1 <= 1'b0; col_mask1 <= 4'd0;
      valid2 <= 1'b0; col_mask2 <= 4'd0;
      valid3 <= 1'b0; col_mask3 <= 4'd0;
    end else begin
      valid0 <= |req[3:0];   col_mask0 <= req[3:0];
      valid1 <= |req[7:4];   col_mask1 <= req[7:4];
      valid2 <= |req[11:8];  col_mask2 <= req[11:8];
      valid3 <= |req[15:12]; col_mask3 <= req[15:12];
    end
  end
endmodule
