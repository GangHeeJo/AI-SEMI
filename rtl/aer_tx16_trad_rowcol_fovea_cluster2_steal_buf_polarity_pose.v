// Digital 2차 전용 변형 -- 1차 제출본(aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity.v,
// 2026-08-28 제출 완료, 원본은 절대 수정하지 않음)에 발생시점 자세(occurrence pose) 태깅을
// 추가한 포크. pol_fifo0/pol_fifo1(소스당 2-deep, 극성 1비트)과 완전히 같은 구조로
// pose_fifo0/pose_fifo1(소스당 2-deep, theta_idx 8비트)을 나란히 둔다 -- "이벤트가 버퍼에
// 대기하는 동안 카메라가 돌아서, 배출 시점 theta를 쓰면 틀린다"는 2차 설계의 실제 문제를
// 근본적으로 해결(v1은 배출 시점의 살아있는 theta를 썼음, progress.md §111의 캐베앗 참고).
//
// 변경점 1: polarity_in과 나란히 theta_idx_in을 입력받아 같은 타이밍(같은 push/pop 조건)으로
// 저장하고, pol_mask0/1(4x1비트)과 같은 방식으로 pose_mask0/1(4x8비트, 열마다 서로 다른
// 발생시점 theta를 가질 수 있음)을 출력한다.
//
// 변경점 2(백프레셔, 병렬 세션(codex/ai-semi-stage2) 제안 반영): `stall` 입력이 1이면 이번
// 사이클 grant를 전부 보류 -- 도착(arrival)/버퍼링(pending_cnt, pol/pose_fifo)은 그대로
// 계속되고, "밖으로 내보내는 것"만 멈춘다. 소스당 2-deep 버퍼가 이미 있어서 순간적인
// 다운스트림 정체를 몇 사이클은 조용히 흡수함(overrun으로 버리는 대신).
module aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  input  [15:0] polarity_in,   // arrival[i]=1인 소스에 대해서만 의미 있음
  input  [127:0] theta_idx_in, // 소스별 8비트(발생 시점의 world theta_idx), 위와 동일 조건에서만 의미 있음
  input          stall,        // 1이면 이번 사이클 grant 보류(도착/버퍼링은 계속됨)
  output [15:0] overrun,
  output reg        valid0,
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg [3:0]  pol_mask0,
  output reg [31:0] pose_mask0,  // 열 0~3의 발생시점 theta_idx, 8비트씩
  output reg        valid1,
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1,
  output reg [3:0]  pol_mask1,
  output reg [31:0] pose_mask1
);
  reg [1:0] pending_cnt [0:15];
  reg pol_fifo0 [0:15];
  reg pol_fifo1 [0:15];
  reg [7:0] pose_fifo0 [0:15];
  reg [7:0] pose_fifo1 [0:15];
  integer pc_k;

  wire [15:0] pending_gt0;
  wire [15:0] pending_full;
  wire [15:0] pol_front_bus;
  wire [127:0] pose_front_bus;
  genvar gk;
  generate
    for (gk = 0; gk < 16; gk = gk + 1) begin: gt0
      assign pending_gt0[gk] = (pending_cnt[gk] != 2'd0);
      assign pending_full[gk] = (pending_cnt[gk] == 2'd2);
      assign pol_front_bus[gk] = pol_fifo0[gk];
      assign pose_front_bus[gk*8 +: 8] = pose_fifo0[gk];
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

  reg lane0_valid_c;
  reg [1:0] lane0_row_c;
  reg [3:0] lane0_cols_c;
  reg [3:0] lane0_pol_c;
  reg [31:0] lane0_pose_c;
  always @(*) begin
    if (steal_to_center) begin
      lane0_valid_c = 1'b1; lane0_row_c = 2'd1;
      lane0_cols_c = pending_gt0[7:4];   lane0_pol_c = pol_front_bus[7:4];   lane0_pose_c = pose_front_bus[63:32];
    end else if (~center_idle) begin
      lane0_valid_c = 1'b1;
      lane0_row_c  = center_gnt[1] ? 2'd1 : 2'd2;
      lane0_cols_c = center_gnt[1] ? pending_gt0[7:4]   : pending_gt0[11:8];
      lane0_pol_c  = center_gnt[1] ? pol_front_bus[7:4] : pol_front_bus[11:8];
      lane0_pose_c = center_gnt[1] ? pose_front_bus[63:32] : pose_front_bus[95:64];
    end else if (steal_to_periph) begin
      lane0_valid_c = 1'b1; lane0_row_c = 2'd0;
      lane0_cols_c = pending_gt0[3:0];   lane0_pol_c = pol_front_bus[3:0];   lane0_pose_c = pose_front_bus[31:0];
    end else begin
      lane0_valid_c = 1'b0; lane0_row_c = 2'd0; lane0_cols_c = 4'd0; lane0_pol_c = 4'd0; lane0_pose_c = 32'd0;
    end
    if (stall) lane0_valid_c = 1'b0;
  end

  reg lane1_valid_c;
  reg [1:0] lane1_row_c;
  reg [3:0] lane1_cols_c;
  reg [3:0] lane1_pol_c;
  reg [31:0] lane1_pose_c;
  always @(*) begin
    if (steal_to_periph) begin
      lane1_valid_c = 1'b1; lane1_row_c = 2'd3;
      lane1_cols_c = pending_gt0[15:12]; lane1_pol_c = pol_front_bus[15:12]; lane1_pose_c = pose_front_bus[127:96];
    end else if (~periph_idle) begin
      lane1_valid_c = 1'b1;
      lane1_row_c  = periph_gnt[0] ? 2'd0 : 2'd3;
      lane1_cols_c = periph_gnt[0] ? pending_gt0[3:0]    : pending_gt0[15:12];
      lane1_pol_c  = periph_gnt[0] ? pol_front_bus[3:0]  : pol_front_bus[15:12];
      lane1_pose_c = periph_gnt[0] ? pose_front_bus[31:0] : pose_front_bus[127:96];
    end else if (steal_to_center) begin
      lane1_valid_c = 1'b1; lane1_row_c = 2'd2;
      lane1_cols_c = pending_gt0[11:8];  lane1_pol_c = pol_front_bus[11:8]; lane1_pose_c = pose_front_bus[95:64];
    end else begin
      lane1_valid_c = 1'b0; lane1_row_c = 2'd0; lane1_cols_c = 4'd0; lane1_pol_c = 4'd0; lane1_pose_c = 32'd0;
    end
    if (stall) lane1_valid_c = 1'b0;
  end

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0; pol_mask0 <= 4'd0; pose_mask0 <= 32'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0; pol_mask1 <= 4'd0; pose_mask1 <= 32'd0;
    end else begin
      valid0 <= lane0_valid_c; row0 <= lane0_row_c; col_mask0 <= lane0_cols_c; pol_mask0 <= lane0_pol_c; pose_mask0 <= lane0_pose_c;
      valid1 <= lane1_valid_c; row1 <= lane1_row_c; col_mask1 <= lane1_cols_c; pol_mask1 <= lane1_pol_c; pose_mask1 <= lane1_pose_c;
    end
  end

  wire [15:0] granted_bitmap =
    (lane0_valid_c ? (lane0_cols_c << (lane0_row_c*4)) : 16'd0) |
    (lane1_valid_c ? (lane1_cols_c << (lane1_row_c*4)) : 16'd0);

  always @(posedge clk) begin
    if (rst) begin
      for (pc_k = 0; pc_k < 16; pc_k = pc_k + 1) begin
        pending_cnt[pc_k] <= 2'd0; pol_fifo0[pc_k] <= 1'b0; pol_fifo1[pc_k] <= 1'b0;
        pose_fifo0[pc_k] <= 8'd0; pose_fifo1[pc_k] <= 8'd0;
      end
    end else begin
      for (pc_k = 0; pc_k < 16; pc_k = pc_k + 1) begin
        case ({arrival[pc_k] && !pending_full[pc_k], granted_bitmap[pc_k]})
          2'b10: begin
            pending_cnt[pc_k] <= pending_cnt[pc_k] + 2'd1;
            if (pending_cnt[pc_k] == 2'd0) begin
              pol_fifo0[pc_k] <= polarity_in[pc_k];
              pose_fifo0[pc_k] <= theta_idx_in[pc_k*8 +: 8];
            end else begin
              pol_fifo1[pc_k] <= polarity_in[pc_k];
              pose_fifo1[pc_k] <= theta_idx_in[pc_k*8 +: 8];
            end
          end
          2'b01: begin
            pending_cnt[pc_k] <= pending_cnt[pc_k] - 2'd1;
            pol_fifo0[pc_k] <= pol_fifo1[pc_k];
            pose_fifo0[pc_k] <= pose_fifo1[pc_k];
          end
          2'b11: begin
            pending_cnt[pc_k] <= pending_cnt[pc_k];
            pol_fifo0[pc_k] <= polarity_in[pc_k];
            pose_fifo0[pc_k] <= theta_idx_in[pc_k*8 +: 8];
          end
          default: pending_cnt[pc_k] <= pending_cnt[pc_k];
        endcase
      end
    end
  end
endmodule
