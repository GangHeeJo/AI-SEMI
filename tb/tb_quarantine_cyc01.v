`timescale 1ns/1ps
module tb_quarantine_cyc01;
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
  integer i;

  initial begin
    rst = 1; arrival = 16'd0;
    @(posedge clk); #1;
    rst = 0;

    // cyc0
    arrival = 16'd0;
    for (i = 0; i < 16; i = i + 1)
      if ((($random(rng_seed) % 100 + 100) % 100) < 15) arrival[i] = 1'b1;
    #1;
    $display("cyc0 arrival=%b overrun=%b accept_one=%b collide=%b picked=%0d qcount=%0d",
      arrival, overrun_w, dut.accept_one, dut.collide, dut.picked, dut.qcount_now(1'b0));
    @(posedge clk); #1;
    $display("  -> post-edge0: pending=%b qv=%b%b%b%b qa=%0d,%0d,%0d,%0d valid0=%b row0=%0d cm0=%b valid1=%b row1=%0d cm1=%b",
      {dut.pending[15],dut.pending[14],dut.pending[13],dut.pending[12],dut.pending[11],dut.pending[10],dut.pending[9],dut.pending[8],
       dut.pending[7],dut.pending[6],dut.pending[5],dut.pending[4],dut.pending[3],dut.pending[2],dut.pending[1],dut.pending[0]},
      dut.q_valid[3],dut.q_valid[2],dut.q_valid[1],dut.q_valid[0],
      dut.q_addr[0],dut.q_addr[1],dut.q_addr[2],dut.q_addr[3],
      valid0, row0, col_mask0, valid1, row1, col_mask1);

    // cyc1
    arrival = 16'd0;
    for (i = 0; i < 16; i = i + 1)
      if ((($random(rng_seed) % 100 + 100) % 100) < 15) arrival[i] = 1'b1;
    #1;
    $display("cyc1 arrival=%b overrun=%b accept_one=%b collide=%b picked=%0d qcount=%0d pending_pre=%b granted_bitmap=%b",
      arrival, overrun_w, dut.accept_one, dut.collide, dut.picked, dut.qcount_now(1'b0),
      dut.pending_bits, dut.granted_bitmap);
    @(posedge clk); #1;
    $display("  -> post-edge1: pending=%b qv=%b%b%b%b qa=%0d,%0d,%0d,%0d valid0=%b row0=%0d cm0=%b valid1=%b row1=%0d cm1=%b",
      {dut.pending[15],dut.pending[14],dut.pending[13],dut.pending[12],dut.pending[11],dut.pending[10],dut.pending[9],dut.pending[8],
       dut.pending[7],dut.pending[6],dut.pending[5],dut.pending[4],dut.pending[3],dut.pending[2],dut.pending[1],dut.pending[0]},
      dut.q_valid[3],dut.q_valid[2],dut.q_valid[1],dut.q_valid[0],
      dut.q_addr[0],dut.q_addr[1],dut.q_addr[2],dut.q_addr[3],
      valid0, row0, col_mask0, valid1, row1, col_mask1);
    $finish;
  end
endmodule
