`timescale 1ns/1ps
// aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose_w #(W=8)가 원본(_pose, 8비트)과 사이클 단위로 모든 출력이 같은지 확인.
module tb_pose_w_equiv;
  reg clk = 0, rst = 1;
  reg [15:0] arrival, polarity_in;
  reg [127:0] theta_in;
  reg stall;
  wire [15:0] ov_a, ov_b;
  wire va0, vb0, va1, vb1;
  wire [1:0] ra0, rb0, ra1, rb1;
  wire [3:0] ca0, cb0, ca1, cb1, pa0, pb0, pa1, pb1;
  wire [31:0] qa0, qb0, qa1, qb1;
  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose a (.clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .theta_idx_in(theta_in), .stall(stall), .overrun(ov_a),
    .valid0(va0), .row0(ra0), .col_mask0(ca0), .pol_mask0(pa0), .pose_mask0(qa0), .valid1(va1), .row1(ra1), .col_mask1(ca1), .pol_mask1(pa1), .pose_mask1(qa1));
  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose_w #(.W(8)) b (.clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .theta_idx_in(theta_in), .stall(stall), .overrun(ov_b),
    .valid0(vb0), .row0(rb0), .col_mask0(cb0), .pol_mask0(pb0), .pose_mask0(qb0), .valid1(vb1), .row1(rb1), .col_mask1(cb1), .pol_mask1(pb1), .pose_mask1(qb1));
  always #5 clk = ~clk;
  integer cyc, i, mism;
  initial begin
    mism = 0; arrival = 0; polarity_in = 0; theta_in = 0; stall = 0;
    repeat (3) @(posedge clk); #1 rst = 0;
    for (cyc = 0; cyc < 30000; cyc = cyc + 1) begin
      arrival = 0; polarity_in = $random; stall = (($random % 100) < 15);
      for (i = 0; i < 16; i = i + 1) if (($random % 100) < 25) arrival[i] = 1;
      theta_in = {$random, $random, $random, $random};
      @(posedge clk); #1;
      if ({ov_a,va0,ra0,ca0,pa0,qa0,va1,ra1,ca1,pa1,qa1} !== {ov_b,vb0,rb0,cb0,pb0,qb0,vb1,rb1,cb1,pb1,qb1}) mism = mism + 1;
    end
    $display("cycles=30000 mismatches=%0d", mism);
    if (mism == 0) $display("POSE_W_EQUIV_PASS"); else $display("POSE_W_EQUIV_FAIL");
    $finish;
  end
endmodule
