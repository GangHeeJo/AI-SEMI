// cluster2의 jitter 진원지(레인 내부 row1-vs-row2, row0-vs-row3 round-robin)를
// "내용 무관 고정 시분할(TDM)"로 교체한 변형. round-robin(arbiter2)은 경합이 있을
// 때만 진 쪽에 다음 차례를 주는 work-conserving 방식이라, 그 결과 지연이
// {기본값, 기본값+1} 사이를 오가며 소스별 latency jitter(avg_timing_error)를 만든다
// (progress.md §67 참고). TDM은 상대가 요청 중이든 아니든 무조건 정해진 사이클에만
// 그 행을 검사하므로 jitter는 구조적으로 0이 되지만, 상대가 놀고 있을 때도 내 차례가
// 아니면 그 사이클을 못 쓰므로 편중된 트래픽에서 처리량 손해를 볼 수 있다 -- 이게
// Ryu가 Gen3(순차 컬럼 스캔)에서 받아들인 것과 같은 트레이드오프. 손해가 실제로
// 얼마인지는 tb_cluster2_tdm_vs_baseline.v로 원본과 나란히 실측한다.
module aer_tx16_trad_rowcol_fovea_cluster2_tdm (
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg        valid0,   // 중심 레인
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg        valid1,   // 주변 레인
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1
);
  wire [3:0] row_req;
  assign row_req[0] = |req[3:0];
  assign row_req[1] = |req[7:4];
  assign row_req[2] = |req[11:8];
  assign row_req[3] = |req[15:12];

  // 자유구동 위상 -- req와 무관하게 매 사이클 뒤집힘. phase=0이면 각 레인의 "낮은
  // 행"(row1/row0) 차례, phase=1이면 "높은 행"(row2/row3) 차례.
  reg phase;
  always @(posedge clk) begin
    if (rst) phase <= 1'b0;
    else phase <= ~phase;
  end

  wire center_sel_row2 = phase;             // 0->row1 차례, 1->row2 차례
  wire center_valid_w  = center_sel_row2 ? row_req[2] : row_req[1];
  wire [1:0] center_row_w = center_sel_row2 ? 2'd2 : 2'd1;
  wire [3:0] center_cols_w = center_sel_row2 ? req[11:8] : req[7:4];

  wire periph_sel_row3 = phase;             // 0->row0 차례, 1->row3 차례
  wire periph_valid_w  = periph_sel_row3 ? row_req[3] : row_req[0];
  wire [1:0] periph_row_w = periph_sel_row3 ? 2'd3 : 2'd0;
  wire [3:0] periph_cols_w = periph_sel_row3 ? req[15:12] : req[3:0];

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0;
    end else begin
      valid0 <= center_valid_w;
      row0 <= center_row_w;
      col_mask0 <= center_valid_w ? center_cols_w : 4'd0;

      valid1 <= periph_valid_w;
      row1 <= periph_row_w;
      col_mask1 <= periph_valid_w ? periph_cols_w : 4'd0;
    end
  end
endmodule
