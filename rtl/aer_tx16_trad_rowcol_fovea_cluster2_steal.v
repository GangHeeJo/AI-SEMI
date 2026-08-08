// cluster2(2레인, 중심/주변 전용채널)의 다음 단계 -- "전용권은 보장하되, 안 쓰는
// 대역폭은 서로 빌려준다"(work-conserving). cluster2의 약점: 중심(행1,2)/주변(행0,3)
// 각 팀이 자기 레인 안에서는 여전히 "행 2개가 한 레인을 놓고 경쟁"함(팀 내부 경쟁은
// 안 없어짐, arbiter4_tree로 매 사이클 하나만 고름). 그런데 어차피 한쪽 팀이 완전히
// idle이면 그 팀의 레인은 그냥 놀고 있음 -- 그 레인을 상대 팀에게 빌려주면, 상대 팀이
// 자기 행 2개를 동시에(경쟁 없이) 다 내보낼 수 있음.
//
// PERIPH_MASK가 정확히 행 0,3 두 개, CENTER_MASK가 정확히 행 1,2 두 개라서 "레인을
// 빌린다"는 게 곧 "그 팀의 행 2개에 레인 2개를 각각 전담시킨다"는 뜻이 됨 -- 우연이
// 아니라 이 프로젝트의 4x4 토폴로지(팀당 정확히 행 2개) 구조 자체가 만들어주는 성질.
//
// steal_to_periph: 중심 idle + 주변이 행 0,3 둘 다 대기 -> lane0=행0, lane1=행3(경쟁 없음)
// steal_to_center: 주변 idle + 중심이 행 1,2 둘 다 대기 -> lane0=행1, lane1=행2(경쟁 없음)
// 그 외(양쪽 다 뭔가 있거나 양쪽 다 idle)는 cluster2와 완전히 동일하게 동작(각 팀
// 안에서 2개 행이 경쟁하면 arbiter4_tree로 공정하게 하나씩).
module aer_tx16_trad_rowcol_fovea_cluster2_steal (
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg        valid0,
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg        valid1,
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1
);
  wire [3:0] row_req;
  assign row_req[0] = |req[3:0];
  assign row_req[1] = |req[7:4];
  assign row_req[2] = |req[11:8];
  assign row_req[3] = |req[15:12];

  wire center_r1 = row_req[1];
  wire center_r2 = row_req[2];
  wire periph_r0 = row_req[0];
  wire periph_r3 = row_req[3];

  wire center_idle = ~(center_r1 | center_r2);
  wire periph_idle = ~(periph_r0 | periph_r3);

  // 상대 팀이 idle이고 내가 두 행 다 대기중일 때만 훔침 -- 두 조건은 동시에 참일 수
  // 없음(steal_to_center는 center가 idle이 아님을 요구, steal_to_periph는 반대).
  wire steal_to_periph = center_idle & periph_r0 & periph_r3;
  wire steal_to_center = periph_idle & center_r1 & center_r2;

  localparam [3:0] CENTER_MASK = 4'b0110;
  localparam [3:0] PERIPH_MASK = 4'b1001;
  wire [3:0] center_req_in = (row_req & CENTER_MASK);
  wire [3:0] periph_req_in = (row_req & PERIPH_MASK);
  wire [3:0] center_gnt, periph_gnt;

  // 훔치는 사이클엔 두 행을 동시에 내보내므로 이 중재기들의 결과가 필요 없음(내부
  // last_gnt 상태는 req가 안 들어온 사이클엔 안 바뀌므로 다음 "일반" 사이클에 그대로
  // 이어서 공정하게 동작).
  arbiter4_tree center_arb(.clk(clk), .rst(rst), .req(center_req_in), .gnt(center_gnt));
  arbiter4_tree periph_arb(.clk(clk), .rst(rst), .req(periph_req_in), .gnt(periph_gnt));

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0;
    end else begin
      // lane0: 기본은 center 전용, steal_to_center일 땐 행1, steal_to_periph일 땐 행0.
      if (steal_to_center) begin
        valid0 <= 1'b1; row0 <= 2'd1; col_mask0 <= req[7:4];
      end else if (~center_idle) begin
        valid0 <= 1'b1; row0 <= center_gnt[1] ? 2'd1 : 2'd2; col_mask0 <= center_gnt[1] ? req[7:4] : req[11:8];
      end else if (steal_to_periph) begin
        valid0 <= 1'b1; row0 <= 2'd0; col_mask0 <= req[3:0];
      end else begin
        valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0;
      end

      // lane1: 기본은 periph 전용, steal_to_periph일 땐 행3, steal_to_center일 땐 행2.
      if (steal_to_periph) begin
        valid1 <= 1'b1; row1 <= 2'd3; col_mask1 <= req[15:12];
      end else if (~periph_idle) begin
        valid1 <= 1'b1; row1 <= periph_gnt[0] ? 2'd0 : 2'd3; col_mask1 <= periph_gnt[0] ? req[3:0] : req[15:12];
      end else if (steal_to_center) begin
        valid1 <= 1'b1; row1 <= 2'd2; col_mask1 <= req[11:8];
      end else begin
        valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0;
      end
    end
  end
endmodule
