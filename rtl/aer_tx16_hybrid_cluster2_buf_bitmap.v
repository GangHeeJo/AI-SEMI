// cluster2_buf(소스별 2-deep 카운터, 재발화 생존) + dense bitmap 전환(§69~72, 고부하
// 비트비용/동시부하 대응)을 결합. buf의 pending_cnt/pending_gt0를 그대로 row 중재의
// 근거로 쓰고, 그 위에 "활성 행 3개 이상"이면 bitmap 모드로 전환하는 §70의 로직을
// 얹는다. bitmap도 pending_gt0(1비트/소스, "밀린 게 있다"만 표현)를 그대로 내보내므로
// 카운터가 2까지 쌓인 소스도 한 번의 bitmap 전송으로는 1개만 비워짐(addressed 모드의
// col_mask와 동일한 한계) -- 카운터는 재발화 "생존"(손실 방지)을 위한 것이지 한 번에
// 여러 개를 배출하는 게 아님.
//
// 주의: 공용 하네스(aer_clean_tb.sv)의 소스당 1-entry admission 게이트는 이 DUT가
// 두 번째 이상 재발화를 볼 기회 자체를 안 주므로, 이 buf의 재발화 생존 이득은 그
// 게이트로는 안 보임(§65/§72에서 이미 확인된 하네스 자체의 한계) -- 우리 자체
// 다중-pending TB(event_scoreboard 기반)로만 검증 가능.
module aer_tx16_hybrid_cluster2_buf_bitmap #(
  parameter ROW_THRESHOLD = 2   // active_rows > ROW_THRESHOLD 이면 bitmap 전환
) (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  output [15:0] overrun,
  output reg        mode,
  output reg        valid0,
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg        valid1,
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1,
  output reg [15:0] bitmap
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

  wire [2:0] active_rows = row_req[0] + row_req[1] + row_req[2] + row_req[3];
  wire use_bitmap = (active_rows > ROW_THRESHOLD[2:0]);

  // 이번 사이클에 실제로 비워질 소스(다음 edge에 카운터 감소 대상) -- 모드에 따라 다름.
  wire [15:0] granted_bitmap = use_bitmap ? pending_gt0 :
    ((|center_gnt ? (sel_center_cols << (idx4(center_gnt)*4)) : 16'd0) |
     (|periph_gnt ? (sel_periph_cols << (idx4(periph_gnt)*4)) : 16'd0));

  always @(posedge clk) begin
    if (rst) begin
      mode <= 1'b0;
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0;
      bitmap <= 16'd0;
    end else begin
      mode <= use_bitmap;
      if (use_bitmap) begin
        bitmap <= pending_gt0;
        valid0 <= 1'b0;
        valid1 <= 1'b0;
      end else begin
        bitmap <= 16'd0;
        valid0 <= |center_gnt; row0 <= idx4(center_gnt); col_mask0 <= sel_center_cols;
        valid1 <= |periph_gnt; row1 <= idx4(periph_gnt); col_mask1 <= sel_periph_cols;
      end
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
