// aer_tx16_fovea.v를 8x8(64셀)로 확장 — 가운데 4행(2,3,4,5)을 중심, 나머지 4행(0,1,6,7)을
// 주변으로 삼아 WEIGHT:1 가중치를 준다. E번(규모 확장 검증)용.
module aer_tx64_fovea #(
  parameter WEIGHT = 3
) (
  input         clk,
  input         rst,
  input  [63:0] req,
  output reg    valid,
  output reg    addr_type,
  output reg [2:0] addr
);
  wire [7:0] row_req;
  genvar gr;
  generate
    for (gr = 0; gr < 8; gr = gr + 1) begin: rowreq
      assign row_req[gr] = |req[gr*8+7 : gr*8];
    end
  endgenerate

  localparam [7:0] CENTER_MASK = 8'b00111100; // 행 2,3,4,5
  localparam [7:0] PERIPH_MASK = 8'b11000011; // 행 0,1,6,7

  reg [15:0] round;
  wire prefer_center = (round != WEIGHT[15:0]);

  reg state;
  wire center_avail = |(row_req & CENTER_MASK);
  wire periph_avail = |(row_req & PERIPH_MASK);
  wire use_center = (state==1'b0) && ((prefer_center && center_avail) || (!prefer_center && !periph_avail && center_avail));
  wire use_periph = (state==1'b0) && ((!prefer_center && periph_avail) || (prefer_center && !center_avail && periph_avail));

  wire [7:0] center_req_in = use_center ? (row_req & CENTER_MASK) : 8'b0;
  wire [7:0] periph_req_in = use_periph ? (row_req & PERIPH_MASK) : 8'b0;
  wire [7:0] center_gnt, periph_gnt;

  arbiter8 center_arb(.clk(clk), .rst(rst), .req(center_req_in), .gnt(center_gnt));
  arbiter8 periph_arb(.clk(clk), .rst(rst), .req(periph_req_in), .gnt(periph_gnt));

  wire [7:0] row_gnt = use_center ? center_gnt : (use_periph ? periph_gnt : 8'b0);
  reg [7:0] col_bitmap;

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
      state <= 1'b0; valid <= 1'b0; addr_type <= 1'b0; addr <= 3'd0; col_bitmap <= 8'd0; round <= 16'd0;
    end else begin
      case (state)
        1'b0: begin
          if (|row_gnt) begin
            col_bitmap <= sel_row_cols;
            valid <= 1'b1;
            addr_type <= 1'b0;
            addr <= idx8(row_gnt);
            state <= 1'b1;
            round <= (round == WEIGHT[15:0]) ? 16'd0 : round + 16'd1;
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
