`timescale 1ns/1ps
module tb_quarantine_leak_find2;
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
  integer cyc, i, c;
  integer expect_bl [0:15]; // 소스별 기대 backlog(accepted-delivered)

  function integer src_rtl_backlog;
    input integer addr;
    integer j, t;
    begin
      t = dut.pending[addr] ? 1 : 0;
      for (j = 0; j < 4; j = j + 1)
        if (dut.q_valid[j] && dut.q_addr[j] == addr) t = t + 1;
      src_rtl_backlog = t;
    end
  endfunction

  initial begin
    rst = 1; arrival = 16'd0;
    for (i = 0; i < 16; i = i + 1) expect_bl[i] = 0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < 20000; cyc = cyc + 1) begin
      arrival = 16'd0;
      for (i = 0; i < 16; i = i + 1)
        if ((($random(rng_seed) % 100 + 100) % 100) < 15) arrival[i] = 1'b1;
      #1;
      for (i = 0; i < 16; i = i + 1) begin
        if (overrun_w[i]) ; // 드롭 -- expect_bl 변화 없음
        else if (arrival[i]) expect_bl[i] = expect_bl[i] + 1;
      end
      @(posedge clk); #1;
      if (valid0) for (c=0;c<4;c=c+1) if (col_mask0[c]) expect_bl[row0*4+c] = expect_bl[row0*4+c] - 1;
      if (valid1) for (c=0;c<4;c=c+1) if (col_mask1[c]) expect_bl[row1*4+c] = expect_bl[row1*4+c] - 1;

      for (i = 0; i < 16; i = i + 1) begin
        if (expect_bl[i] != src_rtl_backlog(i)) begin
          $display("SRC_LEAK cyc=%0d src=%0d expect=%0d actual=%0d arrival=%b overrun=%b pending=%b qv=%b%b%b%b qa=%0d,%0d,%0d,%0d granted_bitmap=%b",
            cyc, i, expect_bl[i], src_rtl_backlog(i), arrival[i], overrun_w[i], dut.pending[i],
            dut.q_valid[3],dut.q_valid[2],dut.q_valid[1],dut.q_valid[0],
            dut.q_addr[0],dut.q_addr[1],dut.q_addr[2],dut.q_addr[3], dut.granted_bitmap[i]);
          $finish;
        end
      end
    end
    $display("NO_PER_SOURCE_LEAK_IN_20000_CYCLES");
    $finish;
  end
endmodule
