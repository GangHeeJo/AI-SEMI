// aer_tx16.v + "중심와(fovea) 우선순위" — 우리만의 개선 아이디어.
// 행(row) 선택 시, 중심 열(1,2)을 담고 있는 1,2번 행에 4번 중 3번꼴로 우선권을 주고,
// 나머지 1번은 0,3번 행(주변)에도 기회를 줘서 완전히 굶기지는 않게 한다(가중치 3:1).
// 중심용/주변용 중재기를 아예 독립된 arbiter4 인스턴스 2개로 분리했다(이유는 아래 주석).
module aer_tx16_fovea #(
  parameter WEIGHT = 3 // 중심:주변 가중치 비율 (WEIGHT:1). round가 0..WEIGHT-1이면 중심우선, WEIGHT이면 주변우선
) (
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg    valid,
  output reg    addr_type,   // 0=ROW, 1=COL
  output reg [1:0] addr
);
  wire [3:0] row_req;
  assign row_req[0] = |req[3:0];
  assign row_req[1] = |req[7:4];
  assign row_req[2] = |req[11:8];
  assign row_req[3] = |req[15:12];

  localparam [3:0] CENTER_MASK = 4'b0110; // 행1,행2 (중심 열을 담고 있는 행)
  localparam [3:0] PERIPH_MASK = 4'b1001; // 행0,행3

  reg [15:0] round; // 0..WEIGHT-1=중심 우선 / WEIGHT=주변 우선 (WEIGHT:1 가중치)
  wire prefer_center = (round != WEIGHT[15:0]);

  reg state; // 0=IDLE(행 중재), 1=BURST(열 순차 전송)

  wire center_avail = |(row_req & CENTER_MASK);
  wire periph_avail = |(row_req & PERIPH_MASK);
  // 이번 사이클에 "실제로 쓸" 쪽만 딱 하나 정한다 (선호하는 쪽에 요청 있으면 그쪽,
  // 없으면 다른 쪽으로 대체) — 이렇게 정해야 그 쪽 중재기만 이번에 상태를 갱신한다.
  wire use_center = (state == 1'b0) && ((prefer_center && center_avail) || (!prefer_center && !periph_avail && center_avail));
  wire use_periph = (state == 1'b0) && ((!prefer_center && periph_avail) || (prefer_center && !center_avail && periph_avail));

  // 중심 전용 중재기와 주변 전용 중재기를 완전히 분리해서 둔다.
  // (하나의 중재기를 매 라운드 다른 후보군으로 마스킹해서 재사용하면, 그 내부 회전
  //  상태가 특정 패턴에 갇혀서 특정 행이 영원히 선택 안 되는 버그가 생김 — 실제로
  //  겪고 확인함: 주변행 중 하나가 계속 선택 안 되는 현상. 그래서 아예 독립된 상태를
  //  갖는 두 개의 중재기로 분리해 각자의 회전이 서로 간섭하지 않게 함.)
  wire [3:0] center_req_in = use_center ? (row_req & CENTER_MASK) : 4'b0000;
  wire [3:0] periph_req_in = use_periph ? (row_req & PERIPH_MASK) : 4'b0000;
  wire [3:0] center_gnt, periph_gnt;

  arbiter4 center_arb(.clk(clk), .rst(rst), .req(center_req_in), .gnt(center_gnt));
  arbiter4 periph_arb(.clk(clk), .rst(rst), .req(periph_req_in), .gnt(periph_gnt));

  wire [3:0] row_gnt = use_center ? center_gnt : (use_periph ? periph_gnt : 4'b0000);
  reg [3:0] col_bitmap;

  function [1:0] idx4;
    input [3:0] bits;
    begin
      if (bits[0]) idx4 = 2'd0;
      else if (bits[1]) idx4 = 2'd1;
      else if (bits[2]) idx4 = 2'd2;
      else idx4 = 2'd3;
    end
  endfunction

  reg [3:0] sel_row_cols;
  always @(*) begin
    case (idx4(row_gnt))
      2'd0: sel_row_cols = req[3:0];
      2'd1: sel_row_cols = req[7:4];
      2'd2: sel_row_cols = req[11:8];
      default: sel_row_cols = req[15:12];
    endcase
  end

  wire [3:0] col_bitmap_next = col_bitmap & (col_bitmap - 4'd1);

  always @(posedge clk) begin
    if (rst) begin
      state <= 1'b0; valid <= 1'b0; addr_type <= 1'b0; addr <= 2'd0; col_bitmap <= 4'd0; round <= 16'd0;
    end else begin
      case (state)
        1'b0: begin // IDLE: 행 중재
          if (|row_gnt) begin
            col_bitmap <= sel_row_cols;
            valid <= 1'b1;
            addr_type <= 1'b0; // ROW
            addr <= idx4(row_gnt);
            state <= 1'b1;
            round <= (round == WEIGHT[15:0]) ? 16'd0 : round + 16'd1; // 이번 행 선택이 끝났으니 다음 라운드로
          end else begin
            valid <= 1'b0;
          end
        end
        1'b1: begin // BURST: 열 순차 전송
          if (col_bitmap != 4'd0) begin
            valid <= 1'b1;
            addr_type <= 1'b1; // COL
            addr <= idx4(col_bitmap);
            col_bitmap <= col_bitmap_next;
            if (col_bitmap_next == 4'd0) state <= 1'b0;
          end else begin
            valid <= 1'b0;
            state <= 1'b0;
          end
        end
      endcase
    end
  end
endmodule
