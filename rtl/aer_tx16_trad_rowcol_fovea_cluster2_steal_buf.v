// cluster2_steal(2레인, work-conserving) + cluster_buf(소스별 2-deep 카운터) 결합판.
// inter-source contention(cluster2_steal이 해결)과 intra-source 재발화(cluster_buf가
// 해결)를 동시에 다룸 -- 서로 다른 두 손실 원인을 각자 다른 구조로 푸는 조합.
//
// quarantine(§54)의 CAM류 구조("주소를 값으로 저장해 매번 비교")가 PPA에서 완패한
// 교훈을 반영해서, cluster_buf의 검증된 "위치=신원"(소스 인덱스 = 저장 위치, 비교
// 로직 불필요) 카운터 패턴을 그대로 재사용하고, 그 위에 cluster2_steal의 2레인+steal
// 중재 로직만 얹음 -- 새로운 종류의 상태(연관기억, 공용 큐)를 도입하지 않아서 오늘
// 겪은 동시성 버그들(§48, §54)의 근본 원인(여러 곳에 흩어진 상태를 동기화해야 함)이
// 훨씬 적음.
//
// 인터페이스는 cluster_buf와 동일하게 arrival(펄스) -- pending_cnt(소스별 2비트
// 포화카운터)의 ">0" 여부만 cluster2_steal의 중재 로직에 넣으면 되고, 그 카운터
// 자체는 어느 레인에서 grant됐는지와 무관하게 "감소 1"만 알면 됨(cluster_buf와 동일).
// lane0(중심 전용/steal_to_center)과 lane1(주변 전용/steal_to_periph)은 구조상
// 항상 서로 다른 행을 가리키므로(중심={1,2}, 주변={0,3}, steal도 서로 다른 행끼리만
// 교환) 두 레인의 grant 비트맵을 그냥 OR해도 충돌이 없음.
module aer_tx16_trad_rowcol_fovea_cluster2_steal_buf (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  output [15:0] overrun,       // 이번 사이클 도착했는데 카운터(2개)가 이미 꽉 차서 유실
  output reg        valid0,
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg        valid1,
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1
);
  reg [1:0] pending_cnt [0:15];
  integer pc_k; // pending_cnt 갱신 블록 전용 루프 변수(다른 always와 공유 금지, §54 교훈)

  wire [15:0] pending_gt0;
  wire [15:0] pending_full;
  genvar gk;
  generate
    for (gk = 0; gk < 16; gk = gk + 1) begin: gt0
      assign pending_gt0[gk] = (pending_cnt[gk] != 2'd0);
      assign pending_full[gk] = (pending_cnt[gk] == 2'd2);
    end
  endgenerate
  assign overrun = arrival & pending_full;

  wire [3:0] row_req;
  assign row_req[0] = |pending_gt0[3:0];
  assign row_req[1] = |pending_gt0[7:4];
  assign row_req[2] = |pending_gt0[11:8];
  assign row_req[3] = |pending_gt0[15:12];

  wire center_r1 = row_req[1];
  wire center_r2 = row_req[2];
  wire periph_r0 = row_req[0];
  wire periph_r3 = row_req[3];
  wire center_idle = ~(center_r1 | center_r2);
  wire periph_idle = ~(periph_r0 | periph_r3);
  wire steal_to_periph = center_idle & periph_r0 & periph_r3;
  wire steal_to_center = periph_idle & center_r1 & center_r2;

  localparam [3:0] CENTER_MASK = 4'b0110;
  localparam [3:0] PERIPH_MASK = 4'b1001;
  wire [3:0] center_req_in = row_req & CENTER_MASK;
  wire [3:0] periph_req_in = row_req & PERIPH_MASK;
  wire [3:0] center_gnt, periph_gnt;

  arbiter4_tree center_arb(.clk(clk), .rst(rst), .req(center_req_in), .gnt(center_gnt));
  arbiter4_tree periph_arb(.clk(clk), .rst(rst), .req(periph_req_in), .gnt(periph_gnt));

  // lane0: 기본은 center 전용, steal_to_center일 땐 행1, steal_to_periph일 땐 행0.
  reg lane0_valid_c;
  reg [1:0] lane0_row_c;
  reg [3:0] lane0_cols_c;
  always @(*) begin
    if (steal_to_center) begin
      lane0_valid_c = 1'b1; lane0_row_c = 2'd1; lane0_cols_c = pending_gt0[7:4];
    end else if (~center_idle) begin
      lane0_valid_c = 1'b1;
      lane0_row_c  = center_gnt[1] ? 2'd1 : 2'd2;
      lane0_cols_c = center_gnt[1] ? pending_gt0[7:4] : pending_gt0[11:8];
    end else if (steal_to_periph) begin
      lane0_valid_c = 1'b1; lane0_row_c = 2'd0; lane0_cols_c = pending_gt0[3:0];
    end else begin
      lane0_valid_c = 1'b0; lane0_row_c = 2'd0; lane0_cols_c = 4'd0;
    end
  end

  // lane1: 기본은 periph 전용, steal_to_periph일 땐 행3, steal_to_center일 땐 행2.
  reg lane1_valid_c;
  reg [1:0] lane1_row_c;
  reg [3:0] lane1_cols_c;
  always @(*) begin
    if (steal_to_periph) begin
      lane1_valid_c = 1'b1; lane1_row_c = 2'd3; lane1_cols_c = pending_gt0[15:12];
    end else if (~periph_idle) begin
      lane1_valid_c = 1'b1;
      lane1_row_c  = periph_gnt[0] ? 2'd0 : 2'd3;
      lane1_cols_c = periph_gnt[0] ? pending_gt0[3:0] : pending_gt0[15:12];
    end else if (steal_to_center) begin
      lane1_valid_c = 1'b1; lane1_row_c = 2'd2; lane1_cols_c = pending_gt0[11:8];
    end else begin
      lane1_valid_c = 1'b0; lane1_row_c = 2'd0; lane1_cols_c = 4'd0;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0;
    end else begin
      valid0 <= lane0_valid_c; row0 <= lane0_row_c; col_mask0 <= lane0_cols_c;
      valid1 <= lane1_valid_c; row1 <= lane1_row_c; col_mask1 <= lane1_cols_c;
    end
  end

  // 두 레인이 이번 사이클에 실제로 grant하는 소스들의 합쳐진 16비트 비트맵. lane0/lane1은
  // 구조상(center={1,2} vs periph={0,3}, steal도 서로 다른 행끼리만) 항상 서로 다른
  // 행을 가리키므로 겹칠 수 없어 단순 OR로 충분(§54 quarantine처럼 같은 주소 동시타격을
  // 걱정할 필요 없음).
  wire [15:0] granted_bitmap =
    (lane0_valid_c ? (lane0_cols_c << (lane0_row_c*4)) : 16'd0) |
    (lane1_valid_c ? (lane1_cols_c << (lane1_row_c*4)) : 16'd0);

  // 소스별 pending 카운터 갱신: cluster_buf(§44)와 완전히 동일한 패턴 -- 도착하면
  // +1(꽉 찼으면 무시=overrun), 이번 사이클에 그 소스가 어느 레인에서든 grant됐으면
  // -1. 같은 사이클에 도착+서비스가 겹치면 순증감(+1-1=0)으로 자연스럽게 처리됨.
  always @(posedge clk) begin
    if (rst) begin
      for (pc_k = 0; pc_k < 16; pc_k = pc_k + 1) pending_cnt[pc_k] <= 2'd0;
    end else begin
      for (pc_k = 0; pc_k < 16; pc_k = pc_k + 1) begin
        case ({arrival[pc_k] && !pending_full[pc_k], granted_bitmap[pc_k]})
          2'b10: pending_cnt[pc_k] <= pending_cnt[pc_k] + 2'd1;
          2'b01: pending_cnt[pc_k] <= pending_cnt[pc_k] - 2'd1;
          2'b11: pending_cnt[pc_k] <= pending_cnt[pc_k]; // +1-1 상쇄
          default: pending_cnt[pc_k] <= pending_cnt[pc_k];
        endcase
      end
    end
  end
endmodule
