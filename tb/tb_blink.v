`timescale 1ns/1ps
// §217: blink(유휴 클록 차단) 코어가 항상-켬 코어와 같은 결과를 내는지 + 클록이 켜진 비율. 프레임 = 버스트 BURST사이클(무작위 arrival) + 유휴 IDLE사이클, 10프레임.
// 비교: 매 사이클 overrun/wmem_overrun, 마지막에 월드 메모리 4096칸 스캔. 사용: +IDLE=1200 (기본)
module tb_blink;
  reg clk = 0, rst = 1; always #2.5 clk = ~clk;
  reg [15:0] arrival = 0, polarity_in = 0; reg [7:0] theta_idx = 0; reg [11:0] rd_addr = 0;
  wire [15:0] ov_a, ov_b; wire [7:0] wo_a, wo_b; wire rv_a, rp_a, rv_b, rp_b, on_a, on_b;
  aer_tx16_coord_transform_v1_rg    A (.clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .theta_idx(theta_idx), .overrun(ov_a), .wmem_overrun(wo_a), .rd_addr(rd_addr), .rd_valid(rv_a), .rd_pol(rp_a), .core_clk_on(on_a));
  aer_tx16_coord_transform_v1_blink B (.clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .theta_idx(theta_idx), .overrun(ov_b), .wmem_overrun(wo_b), .rd_addr(rd_addr), .rd_valid(rv_b), .rd_pol(rp_b), .core_clk_on(on_b));
  integer seed = 5, fr, c, n, IDLE, cyc_total, cyc_on, mism_ov, mism_mem, valid_cells;
  localparam BURST = 300; integer NFR;
  initial begin
    if (!$value$plusargs("IDLE=%d", IDLE)) IDLE = 1200;
    if (!$value$plusargs("NFR=%d", NFR)) NFR = 10;
`ifdef VCDF
    $dumpfile(`VCDF); $dumpvars(0, tb_blink);
`endif
    cyc_total = 0; cyc_on = 0; mism_ov = 0; mism_mem = 0; valid_cells = 0;
    repeat (4) @(posedge clk); #1 rst = 0;
    for (fr = 0; fr < NFR; fr = fr + 1) begin
      
      for (c = 0; c < BURST + IDLE; c = c + 1) begin
        @(posedge clk); #0.5;
        arrival = (c < BURST && (($random(seed) & 3) != 0)) ? ($random(seed) & $random(seed)) : 16'd0;
        polarity_in = $random(seed); if (c == 0) theta_idx = $random(seed);
        #4; cyc_total = cyc_total + 1; if (on_b) cyc_on = cyc_on + 1;
        if (ov_a !== ov_b || wo_a !== wo_b) mism_ov = mism_ov + 1;
      end
    end
    arrival = 0; repeat (700) @(posedge clk);
    for (n = 0; n < 4096; n = n + 1) begin
      @(posedge clk); #0.5 rd_addr = n; #3;
      if (rv_a !== rv_b || (rv_a && rp_a !== rp_b)) mism_mem = mism_mem + 1;
      if (rv_a) valid_cells = valid_cells + 1;
    end
    $display("IDLE=%0d  core clock on %0.1f%% of cycles | overrun mismatches %0d | memory mismatches %0d (written cells %0d)", IDLE, cyc_on * 100.0 / cyc_total, mism_ov, mism_mem, valid_cells);
    $finish;
  end
endmodule
