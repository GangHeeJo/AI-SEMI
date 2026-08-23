`timescale 1ns/1ps
module tb_delay_shadow_debug;
  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid0_w; wire [1:0] row0_w; wire [3:0] colmask0_w;
  wire valid1_w; wire [1:0] row1_w; wire [3:0] colmask1_w;

  aer_tx16_trad_rowcol_fovea_cluster2 dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w));

  wire ov0; wire [1:0] pr0; wire [3:0] ocm0;
  aer_cluster2_delay_shadow_encode enc(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w),
    .out_valid0(ov0), .packed_row0(pr0), .out_col_mask0(ocm0),
    .out_valid1(), .packed_row1(), .out_col_mask1());

  always #5 clk = ~clk;

  reg [15:0] pending, pending_clear_q;
  reg [15:0] result_mask, ack_mask;
  integer c, cyc;

  initial begin
    rst = 1; req = 16'd0; pending = 16'd0; pending_clear_q = 16'd0;
    @(posedge clk); #1; rst = 0;

    // row2(col0)가 row1과 경합해서 밀리는 도중에(row1이 이김), row2의 다른 열(col1)이
    // "나중에" 도착 -- row2가 마침내 이길 때 col0(t=0 도착)과 col1(t=1 도착)이 한
    // grant(col_mask)에 같이 묶임 -- 서로 다른 진짜 도착시각이 섞이는 경우.
    pending[4] = 1'b1; pending[8] = 1'b1; // row1 col0, row2 col0: 경합 유발(row1이 이김)
    req = pending;

    for (cyc = 0; cyc < 6; cyc = cyc + 1) begin
      if (cyc == 1) begin
        pending[9] = 1'b1; // row2 col1, row2가 아직 대기 중일 때 새로 도착
        req = pending;
      end
      @(posedge clk); #1;
      $display("t=%0d req=%b valid0=%b row0=%0d cm0=%b | enc.wait1=%b enc.wait2=%b | pr0=%b(row_sel=%b,q=%b)",
        cyc, req, valid0_w, row0_w, colmask0_w, enc.wait1, enc.wait2, pr0, pr0[1], pr0[0]);
      result_mask = 16'd0;
      if (valid0_w) for (c = 0; c < 4; c = c + 1) if (colmask0_w[c]) result_mask[row0_w*4+c] = 1'b1;
      pending = pending & ~result_mask;
      req = pending;
    end
    $finish;
  end
endmodule
