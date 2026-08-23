// aer_cluster2_repeat_rowtrim_encode의 제품용(계측용 bits_out 제거). §88에서 bits_out은
// 이미 PPA에 영향 없음을 확인했지만, 합성 대상은 일관되게 lean판으로 통일.
module aer_cluster2_repeat_rowtrim_encode_lean (
  input  wire        clk,
  input  wire        rst,
  input  wire        valid0,
  input  wire [1:0]  row0,
  input  wire [3:0]  col_mask0,
  input  wire        valid1,
  input  wire [1:0]  row1,
  input  wire [3:0]  col_mask1,
  output wire        repeat0,
  output wire        repeat1,
  output wire        row0_bit,
  output wire        row1_bit
);
  reg [1:0] last_row0; reg [3:0] last_cm0; reg last_row0_valid;
  reg [1:0] last_row1; reg [3:0] last_cm1; reg last_row1_valid;

  assign repeat0 = valid0 && last_row0_valid && (row0 == last_row0) && (col_mask0 == last_cm0);
  assign repeat1 = valid1 && last_row1_valid && (row1 == last_row1) && (col_mask1 == last_cm1);
  assign row0_bit = (row0 == 2'd2);
  assign row1_bit = (row1 == 2'd3);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      last_row0 <= 2'd0; last_cm0 <= 4'd0; last_row0_valid <= 1'b0;
      last_row1 <= 2'd0; last_cm1 <= 4'd0; last_row1_valid <= 1'b0;
    end else begin
      if (valid0) begin last_row0 <= row0; last_cm0 <= col_mask0; last_row0_valid <= 1'b1; end
      if (valid1) begin last_row1 <= row1; last_cm1 <= col_mask1; last_row1_valid <= 1'b1; end
    end
  end
endmodule
