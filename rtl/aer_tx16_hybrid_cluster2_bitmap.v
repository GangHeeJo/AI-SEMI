// cluster2(주소기반, 저부하에 강함)와 dense bitmap(위치기반, 고부하에 강함, §69)을
// 사이클마다 전환하는 하이브리드. 전환 기준은 "이번 사이클에 활성 행이 3개 이상"
// (row_req popcount > 2) -- cluster2는 물리적으로 레인이 2개뿐이라 한 사이클에 최대
// 2개 행만 덮을 수 있으므로, 그걸 넘어서는 순간(3~4개 행이 동시에 활성) 주소기반으로는
// 반드시 밀림(백로그)이 생긴다. 그 임계를 넘으면 bitmap으로 전환해 그 사이클의 모든
// 활성 소스를 한 번에(16b 고정비용) 비운다.
module aer_tx16_hybrid_cluster2_bitmap #(
  parameter ROW_THRESHOLD = 2   // active_rows > ROW_THRESHOLD 이면 bitmap 전환
) (
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg        mode,       // 0=addressed(레인그랜트 유효), 1=dense bitmap 유효
  output reg        valid0,     // 중심 레인(mode=0일 때만 유효)
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg        valid1,     // 주변 레인(mode=0일 때만 유효)
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1,
  output reg [15:0] bitmap      // mode=1일 때만 유효
);
  wire [3:0] row_req;
  assign row_req[0] = |req[3:0];
  assign row_req[1] = |req[7:4];
  assign row_req[2] = |req[11:8];
  assign row_req[3] = |req[15:12];

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
      2'd0: sel_center_cols = req[3:0];
      2'd1: sel_center_cols = req[7:4];
      2'd2: sel_center_cols = req[11:8];
      default: sel_center_cols = req[15:12];
    endcase
    case (idx4(periph_gnt))
      2'd0: sel_periph_cols = req[3:0];
      2'd1: sel_periph_cols = req[7:4];
      2'd2: sel_periph_cols = req[11:8];
      default: sel_periph_cols = req[15:12];
    endcase
  end

  // 활성 행 개수(0~4) -- 3개 이상이면 2레인으로 못 덮으므로 bitmap 전환
  wire [2:0] active_rows = row_req[0] + row_req[1] + row_req[2] + row_req[3];
  wire use_bitmap = (active_rows > ROW_THRESHOLD[2:0]);

  always @(posedge clk) begin
    if (rst) begin
      mode <= 1'b0;
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0;
      bitmap <= 16'd0;
    end else begin
      mode <= use_bitmap;
      if (use_bitmap) begin
        bitmap <= req;
        valid0 <= 1'b0;
        valid1 <= 1'b0;
      end else begin
        bitmap <= 16'd0;
        valid0 <= |center_gnt;
        row0 <= idx4(center_gnt);
        col_mask0 <= sel_center_cols;
        valid1 <= |periph_gnt;
        row1 <= idx4(periph_gnt);
        col_mask1 <= sel_periph_cols;
      end
    end
  end
endmodule
