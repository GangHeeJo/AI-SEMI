// cluster2(2레인, 전용채널) + buf(소스별 2-deep 카운터)만 결합 -- steal 없음.
// cluster2의 유일한 잔여 손실은 "같은 소스 재발화"(§44, 다른 소스 간 경쟁은 이미
// 0%)이고, steal이 다루는 "한쪽 팀이 완전 idle일 때의 비대칭부하"는 부하가 125%
// 이상일 때만 실제로 발생하는 엣지케이스(§43)라 현실적 부하에선 불필요할 수 있음.
// steal_buf(결합판)의 Fmax 붕괴(1052->333MHz)가 steal과 buf 중 어느 쪽 책임인지
// 가려보기 위한 실험 -- steal_buf에서 steal_to_center/steal_to_periph 분기만
// 제거하고 cluster2의 원래 center_gnt/periph_gnt 기반 레인 배정으로 되돌림.
module aer_tx16_trad_rowcol_fovea_cluster2_buf (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  output [15:0] overrun,
  output reg        valid0,
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg        valid1,
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1
);
  reg [1:0] pending_cnt [0:15];
  integer pc_k;

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

  localparam [3:0] CENTER_MASK = 4'b0110; // 행1,행2
  localparam [3:0] PERIPH_MASK = 4'b1001; // 행0,행3
  wire [3:0] center_req_in = row_req & CENTER_MASK;
  wire [3:0] periph_req_in = row_req & PERIPH_MASK;
  wire [3:0] center_gnt, periph_gnt;

  arbiter4_tree center_arb(.clk(clk), .rst(rst), .req(center_req_in), .gnt(center_gnt));
  arbiter4_tree periph_arb(.clk(clk), .rst(rst), .req(periph_req_in), .gnt(periph_gnt));

  function [1:0] idx4;
    input [3:0] bits;
    begin
      if (bits[0]) idx4 = 2'd0;
      else if (bits[1]) idx4 = 2'd1;
      else if (bits[2]) idx4 = 2'd2;
      else idx4 = 2'd3;
    end
  endfunction

  reg [3:0] sel_center_cols, sel_periph_cols;
  always @(*) begin
    case (idx4(center_gnt))
      2'd0: sel_center_cols = pending_gt0[3:0];
      2'd1: sel_center_cols = pending_gt0[7:4];
      2'd2: sel_center_cols = pending_gt0[11:8];
      default: sel_center_cols = pending_gt0[15:12];
    endcase
    case (idx4(periph_gnt))
      2'd0: sel_periph_cols = pending_gt0[3:0];
      2'd1: sel_periph_cols = pending_gt0[7:4];
      2'd2: sel_periph_cols = pending_gt0[11:8];
      default: sel_periph_cols = pending_gt0[15:12];
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0;
    end else begin
      valid0 <= |center_gnt; row0 <= idx4(center_gnt); col_mask0 <= sel_center_cols;
      valid1 <= |periph_gnt; row1 <= idx4(periph_gnt); col_mask1 <= sel_periph_cols;
    end
  end

  // center={1,2}/periph={0,3}는 구조상 항상 다른 행이라 OR로 충분(steal_buf와 동일 근거).
  wire [15:0] granted_bitmap =
    (|center_gnt ? (sel_center_cols << (idx4(center_gnt)*4)) : 16'd0) |
    (|periph_gnt ? (sel_periph_cols << (idx4(periph_gnt)*4)) : 16'd0);

  always @(posedge clk) begin
    if (rst) begin
      for (pc_k = 0; pc_k < 16; pc_k = pc_k + 1) pending_cnt[pc_k] <= 2'd0;
    end else begin
      for (pc_k = 0; pc_k < 16; pc_k = pc_k + 1) begin
        case ({arrival[pc_k] && !pending_full[pc_k], granted_bitmap[pc_k]})
          2'b10: pending_cnt[pc_k] <= pending_cnt[pc_k] + 2'd1;
          2'b01: pending_cnt[pc_k] <= pending_cnt[pc_k] - 2'd1;
          2'b11: pending_cnt[pc_k] <= pending_cnt[pc_k];
          default: pending_cnt[pc_k] <= pending_cnt[pc_k];
        endcase
      end
    end
  end
endmodule
