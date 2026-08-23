// aer_tx16_steal_buf_repeat의 계측로직 제거판(순수 PPA 측정용). §88 참고.
module aer_tx16_steal_buf_repeat_lean (
  input  wire        clk,
  input  wire        rst,
  input  wire [15:0] arrival,
  output wire [15:0] overrun,
  output wire        repeat0,
  output wire        repeat1,
  output wire [1:0]  row0_link,
  output wire [3:0]  col_mask0_link,
  output wire [1:0]  row1_link,
  output wire [3:0]  col_mask1_link
);
  wire valid0_w; wire [1:0] row0_w; wire [3:0] colmask0_w;
  wire valid1_w; wire [1:0] row1_w; wire [3:0] colmask1_w;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf core(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w));

  aer_cluster2_repeat_encode_lean enc(
    .clk(clk), .rst(rst),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w),
    .repeat0(repeat0), .repeat1(repeat1));

  assign row0_link = repeat0 ? 2'd0 : row0_w;
  assign col_mask0_link = repeat0 ? 4'd0 : colmask0_w;
  assign row1_link = repeat1 ? 2'd0 : row1_w;
  assign col_mask1_link = repeat1 ? 4'd0 : colmask1_w;
endmodule
