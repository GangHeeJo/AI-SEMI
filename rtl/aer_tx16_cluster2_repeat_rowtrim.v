// cluster2 + row-trim + repeat-flag 결합 래퍼(합성용). cluster2 단독 기준
// (138.852um²/11.8744uW)과 직접 비교해서 결합판 전체의 증분 PPA를 확인.
module aer_tx16_cluster2_repeat_rowtrim (
  input  wire        clk,
  input  wire        rst,
  input  wire [15:0] req,
  output wire        repeat0,
  output wire        repeat1,
  output wire        row0_bit,
  output wire        row1_bit,
  output wire [3:0]  col_mask0,
  output wire [3:0]  col_mask1
);
  wire valid0_w; wire [1:0] row0_w;
  wire valid1_w; wire [1:0] row1_w;

  aer_tx16_trad_rowcol_fovea_cluster2 core(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(col_mask0),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(col_mask1));

  aer_cluster2_repeat_rowtrim_encode_lean enc(
    .clk(clk), .rst(rst),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(col_mask0),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(col_mask1),
    .repeat0(repeat0), .repeat1(repeat1), .row0_bit(row0_bit), .row1_bit(row1_bit));
endmodule
