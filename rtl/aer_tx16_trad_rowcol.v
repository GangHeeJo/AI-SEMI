// "진짜 전통적 AER" — Mahowald(1992) 3장 + Boahen(2000) 6절이 기술한 원조 방식:
// 행을 먼저 중재하고 그 안에서 열을 중재하는 2단계(hierarchical) 구조(유령 이벤트
// 방지)이며, 특히 Boahen(2000)이 명시한 "중재기/인코더 개수가 N개에서 √N개로
// 준다"는 면적절감 주장을 그대로 반영해 **열 중재기를 모든 행이 공유(1개)**한다
// (처음엔 행마다 독립 중재기 4개로 짰다가, 그러면 중재기 총수가 오히려 늘어나서
// 논문의 √N 주장과 안 맞는 걸 발견해 이 버전으로 수정함 — progress.md #16 참고).
// Boahen(2004)의 burst 최적화(같은 행에서 여러 열을 묶어 보내는 것)는 없음 —
// 매 이벤트마다 행+열 주소를 한 번에(1사이클) 통으로 전송하고 바로 재중재한다.
module aer_tx16_trad_rowcol(
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg    valid,
  output reg [3:0] addr   // {row[1:0], col[1:0]} 통합 주소, 매 grant마다 1사이클에 전송
);
  wire [3:0] row_req;
  assign row_req[0] = |req[3:0];
  assign row_req[1] = |req[7:4];
  assign row_req[2] = |req[11:8];
  assign row_req[3] = |req[15:12];

  wire [3:0] row_gnt;
  arbiter4 row_arb(.clk(clk), .rst(rst), .req(row_req), .gnt(row_gnt));

  function [1:0] idx4;
    input [3:0] bits;
    begin
      if (bits[0]) idx4 = 2'd0;
      else if (bits[1]) idx4 = 2'd1;
      else if (bits[2]) idx4 = 2'd2;
      else idx4 = 2'd3;
    end
  endfunction

  // 그랜트된 행의 열 요청만 뽑아 공유 열 중재기 1개에 넣음(유령 이벤트 방지 —
  // 그랜트 안 된 행의 열 비트는 안 섞임).
  reg [3:0] sel_row_cols;
  always @(*) begin
    case (idx4(row_gnt))
      2'd0: sel_row_cols = req[3:0];
      2'd1: sel_row_cols = req[7:4];
      2'd2: sel_row_cols = req[11:8];
      default: sel_row_cols = req[15:12];
    endcase
  end

  wire [3:0] col_gnt;
  arbiter4 col_arb(.clk(clk), .rst(rst), .req(sel_row_cols), .gnt(col_gnt));

  always @(posedge clk) begin
    if (rst) begin
      valid <= 1'b0;
      addr  <= 4'd0;
    end else begin
      valid <= |row_gnt;
      addr  <= {idx4(row_gnt), idx4(col_gnt)};
    end
  end
endmodule
