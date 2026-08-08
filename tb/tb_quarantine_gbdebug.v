`timescale 1ns/1ps
module tb_quarantine_gbdebug;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_quarantine #(.Q(4)) dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;
  integer cyc;

  initial begin
    rst = 1; arrival = 16'd0;
    @(posedge clk); #1;
    rst = 0;
    arrival = 16'hFFFF; // 전부 요청 -> row0/row1 각각 최대 4개씩 grant될 것
    @(posedge clk); #1; // pending이 arrival을 반영하도록 엣지 한 번 통과
    arrival = 16'd0;
    for (cyc = 0; cyc < 6; cyc = cyc + 1) begin
      $display("cyc=%0d pending=%b granted_bitmap=%b row0=%0d colmask0=%b row1=%0d colmask1=%b",
        cyc, dut.pending_bits, dut.granted_bitmap, row0, col_mask0, row1, col_mask1);
      @(posedge clk); #1;
    end
    $finish;
  end
endmodule
