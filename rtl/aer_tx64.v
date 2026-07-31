// Boahen 2004 스타일 계층적 중재 + 버스트 전송 송신기 — 8x8(64셀)로 확장한 버전.
// aer_tx16.v와 구조는 동일, 행/열이 4개에서 8개로, 주소 폭이 2비트에서 3비트로 늘어남.
module aer_tx64(
  input         clk,
  input         rst,
  input  [63:0] req,
  output reg    valid,
  output reg    addr_type,   // 0=ROW, 1=COL
  output reg [2:0] addr
);
  wire [7:0] row_req;
  genvar gr;
  generate
    for (gr = 0; gr < 8; gr = gr + 1) begin: rowreq
      assign row_req[gr] = |req[gr*8+7 : gr*8];
    end
  endgenerate

  reg state; // 0=IDLE, 1=BURST
  reg [7:0] row_req_gated;
  wire [7:0] row_gnt;
  reg [7:0] col_bitmap;

  always @(*) row_req_gated = (state == 1'b0) ? row_req : 8'b0;

  arbiter8 row_arb(.clk(clk), .rst(rst), .req(row_req_gated), .gnt(row_gnt));

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

  wire [7:0] col_bitmap_next = col_bitmap & (col_bitmap - 8'd1);

  always @(posedge clk) begin
    if (rst) begin
      state <= 1'b0; valid <= 1'b0; addr_type <= 1'b0; addr <= 3'd0; col_bitmap <= 8'd0;
    end else begin
      case (state)
        1'b0: begin
          if (|row_gnt) begin
            col_bitmap <= sel_row_cols;
            valid <= 1'b1;
            addr_type <= 1'b0;
            addr <= idx8(row_gnt);
            state <= 1'b1;
          end else begin
            valid <= 1'b0;
          end
        end
        1'b1: begin
          if (col_bitmap != 8'd0) begin
            valid <= 1'b1;
            addr_type <= 1'b1;
            addr <= idx8(col_bitmap);
            col_bitmap <= col_bitmap_next;
            if (col_bitmap_next == 8'd0) state <= 1'b0;
          end else begin
            valid <= 1'b0;
            state <= 1'b0;
          end
        end
      endcase
    end
  end
endmodule
