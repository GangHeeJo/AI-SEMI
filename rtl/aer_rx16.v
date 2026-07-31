// Boahen 2004 스타일 수신기 — 버스트로 온 (행 주소 1번 + 열 주소들)을 받아
// 원래 이벤트 (row, col) 쌍으로 복원한다.
module aer_rx16(
  input        clk,
  input        rst,
  input        valid,
  input        addr_type, // 0=ROW, 1=COL
  input  [1:0] addr,
  output reg       event_valid,
  output reg [1:0] event_row,
  output reg [1:0] event_col
);
  reg [1:0] current_row;

  always @(posedge clk) begin
    if (rst) begin
      current_row <= 2'd0;
      event_valid <= 1'b0;
      event_row <= 2'd0;
      event_col <= 2'd0;
    end else begin
      event_valid <= 1'b0;
      if (valid) begin
        if (addr_type == 1'b0) begin
          current_row <= addr; // ROW 패킷: 현재 행으로 저장
        end else begin
          event_valid <= 1'b1;  // COL 패킷: 이벤트 하나 복원 완료
          event_row   <= current_row;
          event_col   <= addr;
        end
      end
    end
  end
endmodule
