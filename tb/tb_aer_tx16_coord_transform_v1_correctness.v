`timescale 1ns/1ps
// aer_tx16_coord_transform_v1 무작위 스트레스 검증(v3, progress.md §113/§114) -- 20%/source
// 도착률(사이클당 평균 0.14개인 실트래픽보다 훨씬 높음)로 world_mem_writer의 FIFO+arbiter8이
// 높은 부하에서 어떻게 견디는지 본다(무손실/overrun 실측이 핵심 -- 이 스트레스 부하에선
// overrun>0이 나올 수 있음, FAIL 기준 아니라 깊이의 실측 한계로 보고만 함).
//
// 검증 방법은 tb_aer_tx16_coord_transform_v1_uzh_trace.v와 동일: 도착 시점에 관찰한
// (row,col,pose)로 coord_transform_rmcm_lut가 계산한 기대값이 1클럭 뒤 world_mem_writer
// push 입력과 일치하는지(content), push=pop+overrun(무손실), world_we 관찰로 만든 최종
// world memory 모델(저장소가 RTL 밖에 있음).
module tb_aer_tx16_coord_transform_v1_correctness;
  `include "rtl/coord_transform_rmcm_lut.vh"

  reg clk = 0;
  reg rst;
  reg [15:0] arrival, polarity_in;
  reg [7:0]  theta_idx;
  wire [15:0] overrun;
  wire [7:0]  wmem_overrun;
  wire        world_we;
  wire [11:0] world_addr;
  wire        world_pol;

  aer_tx16_coord_transform_v1 dut (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in), .theta_idx(theta_idx),
    .overrun(overrun), .wmem_overrun(wmem_overrun),
    .world_we(world_we), .world_addr(world_addr), .world_pol(world_pol)
  );

  always #5 clk = ~clk;

  reg mem_written [0:4095];
  reg mem_pol     [0:4095];
  integer push_total, pop_total, overrun_total, content_checks, content_mismatches;

  reg        pend_valid [0:7];
  reg [5:0]  pend_x [0:7];
  reg [5:0]  pend_y [0:7];
  reg        pend_pol [0:7];

  task automatic check_and_advance;
    integer c, g;
    reg [11:0] xy;
    begin
      for (g = 0; g < 8; g = g + 1) begin
        if (pend_valid[g]) begin
          content_checks = content_checks + 1;
          if (!dut.u_wmem.wr_valid[g] ||
              dut.u_wmem.wr_x[g*6 +: 6] !== pend_x[g] ||
              dut.u_wmem.wr_y[g*6 +: 6] !== pend_y[g] ||
              dut.u_wmem.wr_pol[g]      !== pend_pol[g]) begin
            content_mismatches = content_mismatches + 1;
            if (content_mismatches <= 10)
              $display("CONTENT_MISMATCH lane=%0d expected=(%0d,%0d,%b) got_valid=%b got=(%0d,%0d,%b)",
                        g, pend_x[g], pend_y[g], pend_pol[g], dut.u_wmem.wr_valid[g],
                        dut.u_wmem.wr_x[g*6 +: 6], dut.u_wmem.wr_y[g*6 +: 6], dut.u_wmem.wr_pol[g]);
          end
        end
      end

      for (g = 0; g < 8; g = g + 1) pend_valid[g] = 1'b0;
      if (dut.u_tx.valid0)
        for (c = 0; c < 4; c = c + 1)
          if (dut.u_tx.col_mask0[c]) begin
            xy = coord_transform_rmcm_lut(dut.u_tx.row0, c[1:0], dut.u_tx.pose_mask0[c*8 +: 8]);
            pend_valid[c] = 1'b1; pend_x[c] = xy[11:6]; pend_y[c] = xy[5:0]; pend_pol[c] = dut.u_tx.pol_mask0[c];
          end
      if (dut.u_tx.valid1)
        for (c = 0; c < 4; c = c + 1)
          if (dut.u_tx.col_mask1[c]) begin
            xy = coord_transform_rmcm_lut(dut.u_tx.row1, c[1:0], dut.u_tx.pose_mask1[c*8 +: 8]);
            pend_valid[4+c] = 1'b1; pend_x[4+c] = xy[11:6]; pend_y[4+c] = xy[5:0]; pend_pol[4+c] = dut.u_tx.pol_mask1[c];
          end

      for (g = 0; g < 8; g = g + 1) begin
        if (dut.u_wmem.wr_valid[g])   push_total    = push_total + 1;
        if (dut.u_wmem.wr_overrun[g]) overrun_total = overrun_total + 1;
      end
      if (world_we) begin
        pop_total = pop_total + 1;
        mem_written[world_addr] = 1'b1;
        mem_pol[world_addr] = world_pol;
      end
    end
  endtask

  integer i, cyc;
  integer N_CYCLES;
  reg [7:0] th_pending;

  initial begin
    N_CYCLES = 20000;
    rst = 1; arrival = 16'd0; polarity_in = 16'd0; theta_idx = 8'd0;
    push_total = 0; pop_total = 0; overrun_total = 0; content_checks = 0; content_mismatches = 0;
    for (i = 0; i < 4096; i = i + 1) begin mem_written[i] = 1'b0; mem_pol[i] = 1'b0; end
    for (i = 0; i < 8; i = i + 1) pend_valid[i] = 1'b0;

    @(posedge clk); #1; rst = 0;

    th_pending = $random;
    for (cyc = 0; cyc < N_CYCLES; cyc = cyc + 1) begin
      arrival = 16'd0; polarity_in = $random;
      for (i = 0; i < 16; i = i + 1)
        if (($random % 100) < 20) arrival[i] = 1'b1;
      theta_idx = th_pending;
      @(posedge clk); #1;
      th_pending = $random;
      check_and_advance;
    end

    // 드레인 -- FIFO 최대 잔량(8레인 x 깊이32=256) + steal_buf 자체 drain 몫 대비 넉넉하게.
    arrival = 16'd0; polarity_in = 16'd0;
    for (i = 0; i < 400; i = i + 1) begin
      theta_idx = th_pending;
      @(posedge clk); #1;
      th_pending = $random;
      check_and_advance;
    end

    begin : REPORT
      integer filled;
      filled = 0;
      for (i = 0; i < 4096; i = i + 1) if (mem_written[i]) filled = filled + 1;
      $display("N_CYCLES=%0d push=%0d pop=%0d overrun=%0d content_checks=%0d content_mismatches=%0d world_filled=%0d/4096",
                N_CYCLES, push_total, pop_total, overrun_total, content_checks, content_mismatches, filled);
      if (push_total == pop_total + overrun_total && content_mismatches == 0)
        $display("AER_TX16_COORD_TRANSFORM_V1_CORRECTNESS_PASS");
      else
        $display("AER_TX16_COORD_TRANSFORM_V1_CORRECTNESS_FAIL");
    end
    $finish;
  end
endmodule
