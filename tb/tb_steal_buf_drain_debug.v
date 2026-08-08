`timescale 1ns/1ps
module tb_steal_buf_drain_debug;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;
  integer i;

  initial begin
    rst = 1; arrival = 16'd0;
    @(posedge clk); #1;
    rst = 0;

    // 강제로 소스 2,12,13만 pending 상태로 만듦(직접 arrival 줘서).
    arrival = 16'd0;
    arrival[2] = 1; arrival[12] = 1; arrival[13] = 1;
    @(posedge clk); #1;
    arrival = 16'd0;

    for (i = 0; i < 20; i = i + 1) begin
      $display("cyc=%0d pending_gt0=%b row_req=%b center_idle=%b periph_idle=%b steal2p=%b steal2c=%b center_gnt=%b periph_gnt=%b",
        i, dut.pending_gt0, dut.row_req, dut.center_idle, dut.periph_idle,
        dut.steal_to_periph, dut.steal_to_center, dut.center_gnt, dut.periph_gnt);
      $display("   lane0_valid_c=%b row0_c=%0d cols0_c=%b lane1_valid_c=%b row1_c=%0d cols1_c=%b",
        dut.lane0_valid_c, dut.lane0_row_c, dut.lane0_cols_c,
        dut.lane1_valid_c, dut.lane1_row_c, dut.lane1_cols_c);
      @(posedge clk); #1;
      $display("   -> valid0=%b row0=%0d cm0=%b valid1=%b row1=%0d cm1=%b pending_cnt2=%0d pending_cnt12=%0d pending_cnt13=%0d",
        valid0, row0, col_mask0, valid1, row1, col_mask1,
        dut.pending_cnt[2], dut.pending_cnt[12], dut.pending_cnt[13]);
    end
    $finish;
  end
endmodule
