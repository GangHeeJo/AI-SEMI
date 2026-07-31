// aer_rx16.v를 8x8(64셀)로 확장한 수신기.
module aer_rx64(
  input        clk,
  input        rst,
  input        valid,
  input        addr_type,
  input  [2:0] addr,
  output reg       event_valid,
  output reg [2:0] event_row,
  output reg [2:0] event_col
);
  reg [2:0] current_row;

  always @(posedge clk) begin
    if (rst) begin
      current_row <= 3'd0;
      event_valid <= 1'b0;
      event_row <= 3'd0;
      event_col <= 3'd0;
    end else begin
      event_valid <= 1'b0;
      if (valid) begin
        if (addr_type == 1'b0) begin
          current_row <= addr;
        end else begin
          event_valid <= 1'b1;
          event_row   <= current_row;
          event_col   <= addr;
        end
      end
    end
  end
endmodule
