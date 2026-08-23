// aer_cluster2_rowtrim_encode의 짝 디코더. 순수 조합논리, 상태 없음.
module aer_cluster2_rowtrim_decode (
  input  wire [5:0] lane0_packed,
  input  wire [5:0] lane1_packed,
  output wire        valid0,
  output wire [1:0]  row0,
  output wire [3:0]  col_mask0,
  output wire        valid1,
  output wire [1:0]  row1,
  output wire [3:0]  col_mask1
);
  wire row0_bit = lane0_packed[4];
  wire row1_bit = lane1_packed[4];

  assign valid0    = lane0_packed[5];
  assign row0      = row0_bit ? 2'd2 : 2'd1;
  assign col_mask0 = lane0_packed[3:0];

  assign valid1    = lane1_packed[5];
  assign row1      = row1_bit ? 2'd3 : 2'd0;
  assign col_mask1 = lane1_packed[3:0];
endmodule
