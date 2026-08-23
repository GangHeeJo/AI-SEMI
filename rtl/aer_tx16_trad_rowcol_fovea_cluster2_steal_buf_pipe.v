// cluster2_steal_buf의 파이프라인 버전 -- 중재 결정과 pending_cnt 갱신을 두 사이클로
// 분리해서 critical path를 줄이려는 시도(§64 논의). 단순히 레지스터만 끊으면 되먹임
// 위험이 생김: 이번 사이클 중재(center_gnt/periph_gnt)가 아직 반영 안 된
// pending_cnt를 보고 결정되므로, 바로 다음 사이클이 "방금 grant된 바로 그 행"을
// 또 뽑아버릴 수 있음(중복 grant). 이를 막기 위해 "방금 grant된 행"을 1사이클만
// 마스킹하는 최소한의 하자드 방지 로직(just_granted, 행 단위 4비트)을 추가함 --
// 전체 정지(stall) 대신 그 행만 한 박자 쉬게 해서 다른 행/레인은 매 사이클 그대로
// 진행 가능.
module aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_pipe (
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

  // === 1단계: 중재만(레지스터로 결과 고정) ===
  reg [3:0] just_granted_row_q; // 지난 사이클에 실제로 grant된 행(1사이클만 마스킹)

  wire [3:0] row_req_raw;
  assign row_req_raw[0] = |pending_gt0[3:0];
  assign row_req_raw[1] = |pending_gt0[7:4];
  assign row_req_raw[2] = |pending_gt0[11:8];
  assign row_req_raw[3] = |pending_gt0[15:12];
  wire [3:0] row_req = row_req_raw & ~just_granted_row_q;

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

  // 1단계 결과 레지스터 -- 다음 사이클(2단계)에서 씀
  reg        s1_steal_to_center_q, s1_steal_to_periph_q;
  reg        s1_center_idle_q, s1_periph_idle_q;
  reg [3:0]  s1_center_gnt_q, s1_periph_gnt_q;
  reg [15:0] s1_pending_gt0_q; // 2단계에서 실제로 나갈 열 비트맵을 뽑을 때 필요

  always @(posedge clk) begin
    if (rst) begin
      s1_steal_to_center_q <= 1'b0; s1_steal_to_periph_q <= 1'b0;
      s1_center_idle_q <= 1'b0; s1_periph_idle_q <= 1'b0;
      s1_center_gnt_q <= 4'd0; s1_periph_gnt_q <= 4'd0;
      s1_pending_gt0_q <= 16'd0;
    end else begin
      s1_steal_to_center_q <= steal_to_center;
      s1_steal_to_periph_q <= steal_to_periph;
      s1_center_idle_q <= center_idle;
      s1_periph_idle_q <= periph_idle;
      s1_center_gnt_q <= center_gnt;
      s1_periph_gnt_q <= periph_gnt;
      s1_pending_gt0_q <= pending_gt0;
    end
  end

  // === 2단계: 1단계 결과로 실제 열 비트맵/레인 배정 + pending_cnt 갱신 ===
  function [1:0] idx4;
    input [3:0] bits;
    begin
      if (bits[0]) idx4 = 2'd0;
      else if (bits[1]) idx4 = 2'd1;
      else if (bits[2]) idx4 = 2'd2;
      else idx4 = 2'd3;
    end
  endfunction

  reg lane0_valid_c;
  reg [1:0] lane0_row_c;
  reg [3:0] lane0_cols_c;
  always @(*) begin
    if (s1_steal_to_center_q) begin
      lane0_valid_c = 1'b1; lane0_row_c = 2'd1; lane0_cols_c = s1_pending_gt0_q[7:4];
    end else if (~s1_center_idle_q) begin
      lane0_valid_c = 1'b1;
      lane0_row_c  = s1_center_gnt_q[1] ? 2'd1 : 2'd2;
      lane0_cols_c = s1_center_gnt_q[1] ? s1_pending_gt0_q[7:4] : s1_pending_gt0_q[11:8];
    end else if (s1_steal_to_periph_q) begin
      lane0_valid_c = 1'b1; lane0_row_c = 2'd0; lane0_cols_c = s1_pending_gt0_q[3:0];
    end else begin
      lane0_valid_c = 1'b0; lane0_row_c = 2'd0; lane0_cols_c = 4'd0;
    end
  end

  reg lane1_valid_c;
  reg [1:0] lane1_row_c;
  reg [3:0] lane1_cols_c;
  always @(*) begin
    if (s1_steal_to_periph_q) begin
      lane1_valid_c = 1'b1; lane1_row_c = 2'd3; lane1_cols_c = s1_pending_gt0_q[15:12];
    end else if (~s1_periph_idle_q) begin
      lane1_valid_c = 1'b1;
      lane1_row_c  = s1_periph_gnt_q[0] ? 2'd0 : 2'd3;
      lane1_cols_c = s1_periph_gnt_q[0] ? s1_pending_gt0_q[3:0] : s1_pending_gt0_q[15:12];
    end else if (s1_steal_to_center_q) begin
      lane1_valid_c = 1'b1; lane1_row_c = 2'd2; lane1_cols_c = s1_pending_gt0_q[11:8];
    end else begin
      lane1_valid_c = 1'b0; lane1_row_c = 2'd0; lane1_cols_c = 4'd0;
    end
  end

  wire [15:0] granted_bitmap =
    (lane0_valid_c ? (lane0_cols_c << (lane0_row_c*4)) : 16'd0) |
    (lane1_valid_c ? (lane1_cols_c << (lane1_row_c*4)) : 16'd0);

  // just_granted_row_q 갱신: 이번 2단계에서 실제로 나간 행들을 다음 1단계에서 1사이클
  // 마스킹. lane0/lane1이 가리키는 행을 원핫으로 변환.
  reg [3:0] next_just_granted;
  always @(*) begin
    next_just_granted = 4'd0;
    if (lane0_valid_c) next_just_granted[lane0_row_c] = 1'b1;
    if (lane1_valid_c) next_just_granted[lane1_row_c] = 1'b1;
  end

  always @(posedge clk) begin
    if (rst) just_granted_row_q <= 4'd0;
    else     just_granted_row_q <= next_just_granted;
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
