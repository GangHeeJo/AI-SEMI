// cluster2의 "중심팀/주변팀 고정 레인" 대신, 매 사이클 4개 행 중 우선순위 top-2를
// 동적으로 골라 레인 2개에 배정 -- steal(한쪽 팀이 "완전히" idle일 때만 작동하는
// 좁은 조건)보다 훨씬 넓은 조건에서 두 레인을 다 채울 수 있음(예: 중심팀 행1만
// 바쁘고 주변팀 행0만 바쁜 흔한 상황도 cluster2/steal은 레인0=행1, 레인1=행0으로
// 우연히 팀 배정과 맞아떨어져야 둘 다 나가는데, 만약 중심팀 두 행(1,2)이 동시에
// 바쁘고 주변팀은 조용하면 cluster2/steal 둘 다 팀당 1레인 제약 때문에 한 사이클에
// 하나만 나감 -- 이 설계는 그 제약 자체가 없어서 두 레인 다 나감).
//
// 현수의 multilane_rotation_arbiter(isolate-lowest-bit K회 연쇄)와 같은 원리를
// 행 레벨(4개)에 적용: 1등을 arbiter4_tree_A로 뽑고, 그 행을 마스킹한 나머지에서
// 2등을 독립된 arbiter4_tree_B로 뽑음(§26/73 교훈대로 두 역할에 상태 공유 없는
// 별도 인스턴스 사용 -- 안 그러면 회전상태가 얽혀서 편중 버그가 남).
module aer_tx16_trad_rowcol_fovea_cluster2_dynamic (
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

  wire [3:0] winner1_gnt;
  arbiter4_tree arb_winner1(.clk(clk), .rst(rst), .req(row_req), .gnt(winner1_gnt));

  wire [3:0] remainder_req = row_req & ~winner1_gnt;
  wire [3:0] winner2_gnt;
  arbiter4_tree arb_winner2(.clk(clk), .rst(rst), .req(remainder_req), .gnt(winner2_gnt));

  function [1:0] idx4;
    input [3:0] bits;
    begin
      if (bits[0]) idx4 = 2'd0;
      else if (bits[1]) idx4 = 2'd1;
      else if (bits[2]) idx4 = 2'd2;
      else idx4 = 2'd3;
    end
  endfunction

  reg [3:0] sel_winner1_cols, sel_winner2_cols;
  always @(*) begin
    case (idx4(winner1_gnt))
      2'd0: sel_winner1_cols = req[3:0];
      2'd1: sel_winner1_cols = req[7:4];
      2'd2: sel_winner1_cols = req[11:8];
      default: sel_winner1_cols = req[15:12];
    endcase
    case (idx4(winner2_gnt))
      2'd0: sel_winner2_cols = req[3:0];
      2'd1: sel_winner2_cols = req[7:4];
      2'd2: sel_winner2_cols = req[11:8];
      default: sel_winner2_cols = req[15:12];
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0;
    end else begin
      valid0 <= |winner1_gnt; row0 <= idx4(winner1_gnt); col_mask0 <= sel_winner1_cols;
      valid1 <= |winner2_gnt; row1 <= idx4(winner2_gnt); col_mask1 <= sel_winner2_cols;
    end
  end
endmodule
