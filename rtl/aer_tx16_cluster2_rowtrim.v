// cluster2 + rowtrim 인코더를 하나로 묶은 합성용 래퍼. cluster2 단독 기준
// (138.852um²/11.8744uW, critical path 1.21ns @5ns)과 직접 비교해서 rowtrim
// 추가분의 순수 증분 PPA 비용을 확인하려는 목적.
module aer_tx16_cluster2_rowtrim (
  input  wire        clk,
  input  wire        rst,
  input  wire [15:0] req,
  output wire [5:0]  lane0_packed,
  output wire [5:0]  lane1_packed
);
  wire valid0_w; wire [1:0] row0_w; wire [3:0] colmask0_w;
  wire valid1_w; wire [1:0] row1_w; wire [3:0] colmask1_w;

  aer_tx16_trad_rowcol_fovea_cluster2 core(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w));

  aer_cluster2_rowtrim_encode enc(
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w),
    .lane0_packed(lane0_packed), .lane1_packed(lane1_packed));
endmodule
