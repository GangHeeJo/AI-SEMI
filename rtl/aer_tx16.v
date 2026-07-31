// Boahen 2004 스타일 계층적(행-열) 중재 + 버스트 전송 송신기 (동기 재구현).
// 4행x4열=16개 이벤트원을 다룸. req[row*4+col] = 그 셀의 이벤트 대기 여부.
// 핀 공유(burst)를 위해 valid/addr_type/addr 버스 하나로 행 주소(1번)→열 주소들(순차) 전송.
module aer_tx16(
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

  reg state; // 0=IDLE(행 중재), 1=BURST(열 순차 전송)
  reg [3:0] row_req_gated;
  wire [3:0] row_gnt;
  reg [3:0] col_bitmap;

  always @(*) row_req_gated = (state == 1'b0) ? row_req : 4'b0000;

  arbiter4 row_arb(.clk(clk), .rst(rst), .req(row_req_gated), .gnt(row_gnt));

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

  wire [3:0] col_bitmap_next = col_bitmap & (col_bitmap - 4'd1); // 최하위 set bit 제거

  always @(posedge clk) begin
    if (rst) begin
      state <= 1'b0; valid <= 1'b0; addr_type <= 1'b0; addr <= 2'd0; col_bitmap <= 4'd0;
    end else begin
      case (state)
        1'b0: begin // IDLE: 행 중재
          if (|row_gnt) begin
            col_bitmap <= sel_row_cols;
            valid <= 1'b1;
            addr_type <= 1'b0; // ROW
            addr <= idx4(row_gnt);
            state <= 1'b1;
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
