// aer_tx16_trad_rowcol.v를 8x8(64셀)로 확장한 버전 — Boahen(2000)의 "N이 커질수록
// 큐잉 지연의 상대적 타이밍 오차가 오히려 작아진다"는 반직관적 스케일링 주장을
// N=16과 N=64에서 같은 소스당 부하로 비교해 검증하기 위함.
module aer_tx64_trad_rowcol(
  input         clk,
  input         rst,
  input  [63:0] req,
  output reg    valid,
  output reg [5:0] addr   // {row[2:0], col[2:0]}
);
  wire [7:0] row_req;
  genvar gr;
  generate
    for (gr = 0; gr < 8; gr = gr + 1) begin: rowreq
      assign row_req[gr] = |req[gr*8+7 : gr*8];
    end
  endgenerate

  wire [7:0] row_gnt;
  arbiter8 row_arb(.clk(clk), .rst(rst), .req(row_req), .gnt(row_gnt));

  function [2:0] idx8;
    input [7:0] bits;
    begin
      if (bits[0]) idx8 = 3'd0;
      else if (bits[1]) idx8 = 3'd1;
      else if (bits[2]) idx8 = 3'd2;
      else if (bits[3]) idx8 = 3'd3;
      else if (bits[4]) idx8 = 3'd4;
      else if (bits[5]) idx8 = 3'd5;
      else if (bits[6]) idx8 = 3'd6;
      else idx8 = 3'd7;
    end
  endfunction

  reg [7:0] sel_row_cols;
  always @(*) sel_row_cols = req[idx8(row_gnt)*8 +: 8];

  wire [7:0] col_gnt;
  arbiter8 col_arb(.clk(clk), .rst(rst), .req(sel_row_cols), .gnt(col_gnt));

  always @(posedge clk) begin
    if (rst) begin
      valid <= 1'b0;
      addr  <= 6'd0;
    end else begin
      valid <= |row_gnt;
      addr  <= {idx8(row_gnt), idx8(col_gnt)};
    end
  end
endmodule
