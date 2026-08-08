`timescale 1ns/1ps
module tb_quarantine_trace2;
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
  integer rng_seed = 31;
  integer i, cyc;
  integer shadow2;

  initial begin
    rst = 1; arrival = 16'd0; shadow2 = 0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < 205; cyc = cyc + 1) begin
      arrival = 16'd0;
      for (i = 0; i < 16; i = i + 1)
        if ((($random(rng_seed) % 100 + 100) % 100) < 15) arrival[i] = 1'b1;
      #1;
      if (arrival[2] && !overrun_w[2]) shadow2 = shadow2 + 1;
      if (arrival[2] || overrun_w[2] || dut.pending[2] || (dut.q_valid[0]&&dut.q_addr[0]==2) ||
          (dut.q_valid[1]&&dut.q_addr[1]==2) || (dut.q_valid[2]&&dut.q_addr[2]==2) || (dut.q_valid[3]&&dut.q_addr[3]==2))
        $display("cyc=%0d arr12=%b ovr12=%b coll12=%b acc12=%b picked=%0d shadow2=%0d pend12=%b qv=%b%b%b%b qa=%0d,%0d,%0d,%0d gbmap12=%b",
          cyc, arrival[2], overrun_w[2], dut.collide[2], dut.accept_one[2], dut.picked, shadow2, dut.pending[2],
          dut.q_valid[3],dut.q_valid[2],dut.q_valid[1],dut.q_valid[0],
          dut.q_addr[0],dut.q_addr[1],dut.q_addr[2],dut.q_addr[3], dut.granted_bitmap[12]);
      @(posedge clk); #1;
      if (valid0 && row0==0 && col_mask0[2]) begin shadow2=shadow2-1; $display("   GRANT12 lane0 shadow2=%0d",shadow2); end
      if (valid1 && row1==0 && col_mask1[2]) begin shadow2=shadow2-1; $display("   GRANT12 lane1 shadow2=%0d",shadow2); end
    end
    $display("FINAL shadow2=%0d pending12=%b", shadow2, dut.pending[2]);
    $finish;
  end
endmodule
