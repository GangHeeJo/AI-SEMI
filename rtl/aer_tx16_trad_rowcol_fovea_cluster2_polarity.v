// 교수님 Q&A(professor_qna_20260819.md L80) 재확인: "intensity는 빼도 되지만 이벤트의
// 극성(polarity, ON/OFF)만 다룬다"는 스코프 정의 -- 우리가 §fa41278에서 극성까지 통째로
// 뺐던 게 원문과 안 맞았음(§81 기록도 이 구분을 놓쳤던 오독). 순정 cluster2에 극성 1비트를
// 얹는 최소 확장.
//
// cluster2 원본은 내부에 pending 저장소가 없다(req가 그 자체로 "지금 대기 중"인 레벨
// 신호, pending 관리는 TB/상위 시스템 몫) -- 그래서 극성도 상위 시스템이 이미 들고 있는
// polarity_in[15:0](req[i]=1인 소스에 대해서만 유효)을 그대로 받아, col_mask를 뽑을 때와
// 완전히 같은 방식으로 이긴 행의 4개 열에 대한 극성만 함께 선택해서 내보내면 된다 --
// 새 저장소(FF) 추가 없이 순수 조합논리 mux 하나 더 얹는 것.
module aer_tx16_trad_rowcol_fovea_cluster2_polarity (
  input         clk,
  input         rst,
  input  [15:0] req,
  input  [15:0] polarity_in, // req[i]=1인 소스에 대해서만 의미 있음(그 외는 don't-care)
  output reg        valid0,   // 중심 레인
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg [3:0]  pol_mask0, // col_mask0[c]=1인 비트에서만 의미 있음
  output reg        valid1,   // 주변 레인
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1,
  output reg [3:0]  pol_mask1
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
  reg [3:0] sel_center_pol,  sel_periph_pol;
  always @(*) begin
    case (idx4(center_gnt))
      2'd0: begin sel_center_cols = req[3:0];   sel_center_pol = polarity_in[3:0];   end
      2'd1: begin sel_center_cols = req[7:4];   sel_center_pol = polarity_in[7:4];   end
      2'd2: begin sel_center_cols = req[11:8];  sel_center_pol = polarity_in[11:8];  end
      default: begin sel_center_cols = req[15:12]; sel_center_pol = polarity_in[15:12]; end
    endcase
    case (idx4(periph_gnt))
      2'd0: begin sel_periph_cols = req[3:0];   sel_periph_pol = polarity_in[3:0];   end
      2'd1: begin sel_periph_cols = req[7:4];   sel_periph_pol = polarity_in[7:4];   end
      2'd2: begin sel_periph_cols = req[11:8];  sel_periph_pol = polarity_in[11:8];  end
      default: begin sel_periph_cols = req[15:12]; sel_periph_pol = polarity_in[15:12]; end
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0; pol_mask0 <= 4'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0; pol_mask1 <= 4'd0;
    end else begin
      valid0 <= |center_gnt;
      row0 <= idx4(center_gnt);
      col_mask0 <= sel_center_cols;
      pol_mask0 <= sel_center_pol;

      valid1 <= |periph_gnt;
      row1 <= idx4(periph_gnt);
      col_mask1 <= sel_periph_cols;
      pol_mask1 <= sel_periph_pol;
    end
  end
endmodule
