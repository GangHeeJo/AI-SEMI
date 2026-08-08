`timescale 1ns/1ps
module tb_quarantine_trace;
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
  integer cyc, i, shadow0;

  initial begin
    rst = 1; arrival = 16'd0; shadow0 = 0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < 400; cyc = cyc + 1) begin
      arrival = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < 15) arrival[i] = 1'b1;
      end
      #1;
      if (arrival[0] && !overrun_w[0]) shadow0 = shadow0 + 1;
      if (arrival[0] || overrun_w[0] || dut.pending[0])
        $display("cyc=%0d arrival0=%b overrun0=%b pending0=%b shadow0=%0d qv=%b%b%b%b qa=%0d,%0d,%0d,%0d",
          cyc, arrival[0], overrun_w[0], dut.pending[0], shadow0,
          dut.q_valid[3],dut.q_valid[2],dut.q_valid[1],dut.q_valid[0],
          dut.q_addr[0],dut.q_addr[1],dut.q_addr[2],dut.q_addr[3]);
      @(posedge clk); #1;
      if (valid0 && row0==0 && col_mask0[0]) begin shadow0 = shadow0 - 1; $display("   -> GRANT0 lane0 shadow0=%0d", shadow0); end
      if (valid1 && row1==0 && col_mask1[0]) begin shadow0 = shadow0 - 1; $display("   -> GRANT0 lane1 shadow0=%0d", shadow0); end
    end
    $display("FINAL shadow0=%0d pending0=%b", shadow0, dut.pending[0]);
    $finish;
  end
endmodule
