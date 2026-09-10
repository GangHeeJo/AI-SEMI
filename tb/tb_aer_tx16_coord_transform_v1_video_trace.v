`timescale 1ns/1ps
// Digital 2차 통합 파이프라인 -- UZH가 아닌 완전히 다른 독립 실제 영상(카카오톡으로 받은
// 이벤트카메라 스타일 시각화 영상, common_traces_video/, scripts에서 왼쪽 흑백 프레임을
// 표준 DVS 온셋 방식(로그 인텐시티 차분 + 문턱값)으로 합성 이벤트화한 트레이스)에 대한
// 견고성(robustness) 검증.
//
// 이 클립은 실제 pose(자세) 데이터가 없어서 좌표변환의 "정답" 여부는 검증할 수 없음
// (theta_idx는 상수 0으로 고정, 구조적 검증 전용) -- 목적은 순전히 "UZH 하나만이 아니라
// 완전히 독립된 실제 영상에서도 AER+변환 파이프라인이 이벤트를 안 잃고, 내용이 일관되게
// 처리되는가"를 보는 일반화(generalization) 테스트. 검증 방법은
// tb_aer_tx16_coord_transform_v1_uzh_trace.v와 동일(content correctness + 무손실).
module tb_aer_tx16_coord_transform_v1_video_trace;
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

  integer fd_ev, scan_ret, next_cycle, next_addr, next_pol, have_next;
  integer fd_th, th_cyc, th_val;
  reg [7:0] theta_by_cyc [0:59871];
  integer cyc, i;
  integer generated;

  initial begin
    rst = 1; arrival = 16'd0; polarity_in = 16'd0; theta_idx = 8'd0;
    generated = 0; push_total = 0; pop_total = 0; overrun_total = 0;
    content_checks = 0; content_mismatches = 0;
    for (i = 0; i < 4096; i = i + 1) begin mem_written[i] = 1'b0; mem_pol[i] = 1'b0; end
    for (i = 0; i < 8; i = i + 1) pend_valid[i] = 1'b0;

    fd_th = $fopen("common_traces_video/kakao_video_patch.cycle_theta.txt", "r");
    if (fd_th == 0) begin $display("CANNOT_OPEN_CYCLE_THETA"); $finish; end
    while (!$feof(fd_th)) begin
      scan_ret = $fscanf(fd_th, "%d %d", th_cyc, th_val);
      if (scan_ret == 2) theta_by_cyc[th_cyc] = th_val[7:0];
    end
    $fclose(fd_th);

    fd_ev = $fopen("common_traces_video/kakao_video_patch.addrpol.txt", "r");
    if (fd_ev == 0) begin $display("CANNOT_OPEN_ADDRPOL"); $finish; end
    scan_ret = $fscanf(fd_ev, "%d %h %h", next_cycle, next_addr, next_pol);
    have_next = (scan_ret == 3);

    @(posedge clk); #1; rst = 0;

    cyc = 0;
    while (have_next) begin
      arrival = 16'd0; polarity_in = 16'd0;
      theta_idx = theta_by_cyc[cyc];
      if (have_next && next_cycle == cyc) begin
        arrival = next_addr[15:0];
        polarity_in = next_pol[15:0];
        for (i = 0; i < 16; i = i + 1) if (arrival[i]) generated = generated + 1;
        scan_ret = $fscanf(fd_ev, "%d %h %h", next_cycle, next_addr, next_pol);
        have_next = (scan_ret == 3);
      end
      @(posedge clk); #1;
      check_and_advance;
      cyc = cyc + 1;
    end
    $fclose(fd_ev);

    arrival = 16'd0; polarity_in = 16'd0;
    for (i = 0; i < 15000; i = i + 1) begin
      theta_idx = 8'd0;
      @(posedge clk); #1;
      check_and_advance;
      cyc = cyc + 1;
    end

    begin : REPORT
      integer filled;
      filled = 0;
      for (i = 0; i < 4096; i = i + 1) if (mem_written[i]) filled = filled + 1;
      $display("generated=%0d push=%0d pop=%0d overrun=%0d content_checks=%0d content_mismatches=%0d world_filled=%0d/4096",
                generated, push_total, pop_total, overrun_total, content_checks, content_mismatches, filled);
      if (push_total == pop_total + overrun_total && overrun_total == 0 && content_mismatches == 0)
        $display("AER_TX16_COORD_TRANSFORM_V1_VIDEO_TRACE_PASS");
      else
        $display("AER_TX16_COORD_TRANSFORM_V1_VIDEO_TRACE_FAIL");
    end
    $finish;
  end
endmodule
