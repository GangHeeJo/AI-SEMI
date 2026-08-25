// cluster2_steal_buf + pressure-aware arbiter. 원본(무수정 steal_buf, arbiter4_tree 기반
// 순수 round-robin)과 다른 부분은 딱 하나: 레인 안 두 행 중 하나가 urgent(그 행 안에
// pending_cnt==2인 source가 있음, 다음 사이클에 또 도착하면 바로 overrun)일 때 그 행을
// 우선 서비스(arbiter2_pressure). 나머지(steal 로직, pending_cnt 갱신, 출력 레지스터)는
// 원본과 완전히 동일 -- 중재 승자를 고르는 부분만 다르므로 arbiter4_tree 2개를
// arbiter2_pressure 2개로 교체(각 레인은 애초에 실제 후보가 2개뿐이라 4-way 트리가
// 항상 부분적으로만 쓰이고 있었음, §100에서 이미 확인).
module aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_pressure (
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

  // 행별 urgency: 그 행 안에 pending_cnt==2(꽉 참)인 source가 하나라도 있으면 1.
  wire [3:0] row_urgent;
  assign row_urgent[0] = |pending_full[3:0];
  assign row_urgent[1] = |pending_full[7:4];
  assign row_urgent[2] = |pending_full[11:8];
  assign row_urgent[3] = |pending_full[15:12];

  wire center_r1 = row_req[1];
  wire center_r2 = row_req[2];
  wire periph_r0 = row_req[0];
  wire periph_r3 = row_req[3];
  wire center_idle = ~(center_r1 | center_r2);
  wire periph_idle = ~(periph_r0 | periph_r3);
  wire steal_to_periph = center_idle & periph_r0 & periph_r3;
  wire steal_to_center = periph_idle & center_r1 & center_r2;

  // center_gnt[1]=row1 승리, center_gnt[0]=row2 승리(원본 arbiter4_tree 사용 시의
  // center_gnt[1]/[2] 의미와 정확히 동일하게 맞춤). {A,B}는 A가 bit1(MSB)이므로
  // req[1]=row_req[1]을 만들려면 row_req[1]을 먼저 써야 함(처음엔 반대로 써서
  // row1/row2가 뒤바뀌는 버그가 있었음 -- row2의 pending이 영원히 안 지워지는
  // DRAIN_INCOMPLETE로 발현, 수정함).
  wire [1:0] center_gnt;
  arbiter2_pressure center_arb(.clk(clk), .rst(rst),
    .req({row_req[1], row_req[2]}), .urgent({row_urgent[1], row_urgent[2]}), .gnt(center_gnt));
  // periph_gnt[0]=row0 승리, periph_gnt[1]=row3 승리(원본 periph_gnt[0]/[3] 의미와 동일).
  wire [1:0] periph_gnt;
  arbiter2_pressure periph_arb(.clk(clk), .rst(rst),
    .req({row_req[3], row_req[0]}), .urgent({row_urgent[3], row_urgent[0]}), .gnt(periph_gnt));

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

  wire [15:0] granted_bitmap =
    (lane0_valid_c ? (lane0_cols_c << (lane0_row_c*4)) : 16'd0) |
    (lane1_valid_c ? (lane1_cols_c << (lane1_row_c*4)) : 16'd0);

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
