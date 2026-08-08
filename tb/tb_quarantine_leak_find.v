`timescale 1ns/1ps
module tb_quarantine_leak_find;
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
  integer cyc, i, c, draw, idx;
  integer accepted_total, delivered_total, overrun_total;
  integer rtl_total; // sum(pending) + qcount

  function integer rtl_backlog;
    input dummy;
    integer j, t;
    begin
      t = 0;
      for (j = 0; j < 16; j = j + 1) if (dut.pending[j]) t = t + 1;
      for (j = 0; j < 4; j = j + 1) if (dut.q_valid[j]) t = t + 1;
      rtl_backlog = t;
    end
  endfunction

  initial begin
    rst = 1; arrival = 16'd0;
    accepted_total = 0; delivered_total = 0; overrun_total = 0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < 5000; cyc = cyc + 1) begin
      arrival = 16'd0;
      for (i = 0; i < 16; i = i + 1)
        if ((($random(rng_seed) % 100 + 100) % 100) < 15) arrival[i] = 1'b1;
      #1;
      for (i = 0; i < 16; i = i + 1) begin
        if (overrun_w[i]) overrun_total = overrun_total + 1;
        else if (arrival[i]) accepted_total = accepted_total + 1;
      end
      @(posedge clk); #1;
      if (valid0) for (c=0;c<4;c=c+1) if (col_mask0[c]) delivered_total = delivered_total + 1;
      if (valid1) for (c=0;c<4;c=c+1) if (col_mask1[c]) delivered_total = delivered_total + 1;

      rtl_total = rtl_backlog(1'b0);
      // 기대 backlog = accepted - delivered (아직 안 나간 것들) 이어야 rtl_total과 같아야 함.
      if ((accepted_total - delivered_total) != rtl_total) begin
        $display("LEAK at cyc=%0d: expected_backlog=%0d rtl_backlog=%0d (accepted=%0d delivered=%0d) pending=%b qv=%b%b%b%b qa=%0d,%0d,%0d,%0d",
          cyc, accepted_total-delivered_total, rtl_total, accepted_total, delivered_total,
          {dut.pending[15],dut.pending[14],dut.pending[13],dut.pending[12],dut.pending[11],dut.pending[10],dut.pending[9],dut.pending[8],
           dut.pending[7],dut.pending[6],dut.pending[5],dut.pending[4],dut.pending[3],dut.pending[2],dut.pending[1],dut.pending[0]},
          dut.q_valid[3],dut.q_valid[2],dut.q_valid[1],dut.q_valid[0],
          dut.q_addr[0],dut.q_addr[1],dut.q_addr[2],dut.q_addr[3]);
        $finish;
      end
    end
    $display("NO_LEAK_DETECTED_IN_5000_CYCLES accepted=%0d delivered=%0d overrun=%0d", accepted_total, delivered_total, overrun_total);
    $finish;
  end
endmodule
