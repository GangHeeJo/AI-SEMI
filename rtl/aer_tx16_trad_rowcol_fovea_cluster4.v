// cluster2(2레인, 중심팀/주변팀)를 논리적 극한까지 밀어붙인 실험 -- 행 4개 전부
// 자기 전용 레인을 갖는다. cluster2도 "팀 내부"에서는 여전히 arbiter4_tree로 두 행이
// 경쟁했는데(중심=행1,2 / 주변=행0,3), 레인이 행마다 하나씩 있으면 그 경쟁 자체가
// 사라진다 -- 매 사이클 요청 있는 행은 무조건 자기 레인으로 나간다. 준영/현수 공용
// 벤치마크에서 준영 DREC(K=4)가 uniform 고부하에서 cluster2를 크게 앞선 것을 보고,
// 현수의 Dir2(4레인 완전분리, payload 기반이라 비쌌음)와 같은 아이디어를 우리
// address-only 인터페이스로도 시도해서 "우리 쪽이 더 싸게 되는지" 확인하기 위한 실험.
//
// 구조: arbiter가 아예 없다 -- 각 행의 열 요청 4비트를 그대로 그 행의 레인으로
// 등록만 한다(組合논리 0단, 레지스터만). 정의상 매 사이클 모든 행의 모든 대기
// 요청이 그대로 나가므로 손실률은 항상 0%.
//
// 대가(예상되는 결론, PPA로 검증 예정): (1) AER의 핵심인 "다중화/압축"이 완전히
// 사라짐 -- 16개 입력을 4개 그룹으로 나눠 그대로 내보내는 병렬 버스와 사실상 동일
// (현수 Dir2에 대한 팀의 비판과 동일한 지적이 우리 쪽에도 그대로 적용됨). (2) 핀 수
// 증가: valid+col_mask[4] 5핀 x 4레인 = 20핀(cluster2는 14핀, fovea는 5핀).
module aer_tx16_trad_rowcol_fovea_cluster4 (
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg        valid0,   // 행0
  output reg [3:0]  col_mask0,
  output reg        valid1,   // 행1
  output reg [3:0]  col_mask1,
  output reg        valid2,   // 행2
  output reg [3:0]  col_mask2,
  output reg        valid3,   // 행3
  output reg [3:0]  col_mask3
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
