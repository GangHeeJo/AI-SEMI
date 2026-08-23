// aer_cluster2_delay_shadow_encode의 짝 디코더. packed_row(2비트, {row_select,q})에서
// 실제 row와 delay shadow q를 복원. col_mask/valid는 native 그대로라 손댈 게 없음.
module aer_cluster2_delay_shadow_decode (
  input  wire        in_valid0,
  input  wire [1:0]  packed_row0,
  input  wire        in_valid1,
  input  wire [1:0]  packed_row1,
  output wire        valid0,
  output wire [1:0]  row0,
  output wire        q0,
  output wire        valid1,
  output wire [1:0]  row1,
  output wire        q1
);
  assign valid0 = in_valid0;
  assign row0 = packed_row0[1] ? 2'd2 : 2'd1;
  assign q0 = packed_row0[0];

  assign valid1 = in_valid1;
  assign row1 = packed_row1[1] ? 2'd3 : 2'd0;
  assign q1 = packed_row1[0];
endmodule
