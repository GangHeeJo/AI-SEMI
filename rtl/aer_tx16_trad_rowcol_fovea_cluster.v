// fovea(중심와 가중치 행선택)는 그대로 두고, 열 중재 단계를 없앤 변형 — 한 행이
// 이기면 그 행에서 대기 중인 열 요청을 "하나만 골라 보내는" 대신 col_mask[3:0]
// 비트맵으로 한꺼번에 통째로 보낸다. 같은 행에서 여러 열이 동시에 대기 중이던
// 이벤트(클러스터, 예: 국소 hotspot/움직이는 물체)를 한 사이클에 최대 4개까지
// "실제로 배출"시킨다 — fovea/사카드억제는 정해진 대역폭 예산을 재분배할 뿐
// 총 손실률(§29, 항상 57.6%로 고정)은 못 줄였는데, 이건 한 번의 grant로 나가는
// 정보량 자체를 늘려서 총 손실률 자체를 낮추는 걸 노린 실험(progress.md 참고).
// col 중재기가 아예 필요 없어져서 하드웨어도 그만큼 줄어듦.
module aer_tx16_trad_rowcol_fovea_cluster #(
  parameter WEIGHT = 5
) (
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg        valid,
  output reg [1:0]  row,
  output reg [3:0]  col_mask
);
  wire [3:0] row_req;
  assign row_req[0] = |req[3:0];
  assign row_req[1] = |req[7:4];
  assign row_req[2] = |req[11:8];
  assign row_req[3] = |req[15:12];

  localparam [3:0] CENTER_MASK = 4'b0110; // 행1,행2
  localparam [3:0] PERIPH_MASK = 4'b1001; // 행0,행3

  localparam RW = (WEIGHT == 0) ? 1 : $clog2(WEIGHT + 1);
  reg [RW-1:0] round;
  wire prefer_center = (round != WEIGHT[RW-1:0]);

  wire center_avail = |(row_req & CENTER_MASK);
  wire periph_avail = |(row_req & PERIPH_MASK);
  wire use_center = (prefer_center && center_avail) || (!prefer_center && !periph_avail && center_avail);
  wire use_periph = (!prefer_center && periph_avail) || (prefer_center && !center_avail && periph_avail);

  wire [3:0] center_req_in = use_center ? (row_req & CENTER_MASK) : 4'b0000;
  wire [3:0] periph_req_in = use_periph ? (row_req & PERIPH_MASK) : 4'b0000;
  wire [3:0] center_gnt, periph_gnt;

  arbiter4_tree center_arb(.clk(clk), .rst(rst), .req(center_req_in), .gnt(center_gnt));
  arbiter4_tree periph_arb(.clk(clk), .rst(rst), .req(periph_req_in), .gnt(periph_gnt));

  wire [3:0] row_gnt = use_center ? center_gnt : (use_periph ? periph_gnt : 4'b0000);

  function [1:0] idx4;
    input [3:0] bits;
    begin
      if (bits[0]) idx4 = 2'd0;
      else if (bits[1]) idx4 = 2'd1;
      else if (bits[2]) idx4 = 2'd2;
      else idx4 = 2'd3;
    end
  endfunction

  // 이긴 행의 열 요청 4비트를 그대로 뽑아옴 -- 열 중재 없이 이 4비트 전부가 이번
  // grant의 payload가 된다(col 중재기 자체가 없어짐).
  reg [3:0] sel_row_cols;
  always @(*) begin
    case (idx4(row_gnt))
      2'd0: sel_row_cols = req[3:0];
      2'd1: sel_row_cols = req[7:4];
      2'd2: sel_row_cols = req[11:8];
      default: sel_row_cols = req[15:12];
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      round <= {RW{1'b0}};
    end else if (|row_gnt) begin
      round <= (round == WEIGHT[RW-1:0]) ? {RW{1'b0}} : round + 1'b1;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      valid    <= 1'b0;
      row      <= 2'd0;
      col_mask <= 4'd0;
    end else begin
      valid    <= |row_gnt;
      row      <= idx4(row_gnt);
      col_mask <= sel_row_cols;
    end
  end
endmodule
