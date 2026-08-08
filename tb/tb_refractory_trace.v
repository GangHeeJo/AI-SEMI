`timescale 1ns/1ps
module tb_refractory_trace;
  parameter R = 2;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] suppressed_w, retrigger_drop_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_refractory #(.R(R)) dut(
    .clk(clk), .rst(rst), .arrival(arrival),
    .suppressed(suppressed_w), .retrigger_drop(retrigger_drop_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;

  integer rng_seed = 3;
  integer cyc, i, draw;

  initial begin
    rst = 1; arrival = 16'd0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < 15; cyc = cyc + 1) begin
      arrival = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < 15) arrival[i] = 1'b1;
      end
      #1;
      $display("cyc=%0d arrival=%b pending9=%b refr9=%0d supp9=%b retrig9=%b",
        cyc, arrival, dut.pending[9], dut.refractory_cnt[9], suppressed_w[9], retrigger_drop_w[9]);
      @(posedge clk); #1;
      $display("   -> valid0=%b row0=%0d col_mask0=%b valid1=%b row1=%0d col_mask1=%b pending9_after=%b",
        valid0, row0, col_mask0, valid1, row1, col_mask1, dut.pending[9]);
    end
    $finish;
  end
endmodule
