// Mahowald(1992) 3장의 경고를 실제로 재현하는 "잘못된" 설계: 행과 열을 서로 독립적으로
// (그랜트된 행에 종속시키지 않고) 중재하면 존재하지 않는 (row,col) 조합이 나온다는
// "유령 이벤트(ghost event)" 주장을 검증하기 위한 반면교사용 데모. 실사용 금지 —
// true_traditional(aer_tx16_trad_rowcol.v)의 "열 중재를 그랜트된 행에 종속시킨다"는
// 설계가 왜 필요한지 보여주는 대조군.
module aer_tx16_ghost_demo(
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg    valid,
  output reg [3:0] addr
);
  wire [3:0] row_req;
  assign row_req[0] = |req[3:0];
  assign row_req[1] = |req[7:4];
  assign row_req[2] = |req[11:8];
  assign row_req[3] = |req[15:12];

  // 잘못된 부분: 열 요청을 "그랜트된 행"이 아니라 전체 행에 걸쳐 독립적으로 OR함.
  wire [3:0] col_req;
  assign col_req[0] = req[0] | req[4] | req[8]  | req[12];
  assign col_req[1] = req[1] | req[5] | req[9]  | req[13];
  assign col_req[2] = req[2] | req[6] | req[10] | req[14];
  assign col_req[3] = req[3] | req[7] | req[11] | req[15];

  wire [3:0] row_gnt, col_gnt;
  arbiter4 row_arb(.clk(clk), .rst(rst), .req(row_req), .gnt(row_gnt));
  arbiter4 col_arb(.clk(clk), .rst(rst), .req(col_req), .gnt(col_gnt));

  function [1:0] idx4;
    input [3:0] bits;
    begin
      if (bits[0]) idx4 = 2'd0;
      else if (bits[1]) idx4 = 2'd1;
      else if (bits[2]) idx4 = 2'd2;
      else idx4 = 2'd3;
    end
  endfunction

  always @(posedge clk) begin
    if (rst) begin
      valid <= 1'b0;
      addr  <= 4'd0;
    end else begin
      valid <= |row_gnt & |col_gnt;
      addr  <= {idx4(row_gnt), idx4(col_gnt)}; // 이 조합이 실제로 req에 있었는지는 보장 안 됨!
    end
  end
endmodule
