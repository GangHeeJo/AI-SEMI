`timescale 1ns/1ps
// Digital 2차 1단계 통합 파이프라인(steal_buf_polarity_pose -> coord_transform_rmcm x8 ->
// world_mem_writer, SRAM 스타일 단일 포트) 실트래픽 검증.
//
// v3(2026-09-10, progress.md §113/§114): pose가 이제 TX에서 "도착 시점"에 캡처되어
// pose_mask0/1로 그대로 배출되므로(더 이상 "다음 edge 시점 theta"를 추측할 필요 없음 --
// v1/v2에서 두 번이나 버그를 냈던 바로 그 지점이 근본적으로 사라짐), 여기서는:
//   (1) 커밋 내용 정확성 -- 도착 시점 관찰한 (row,col,pose)로 coord_transform_rmcm_lut가
//       계산한 기대값이, 1사이클 뒤 world_mem_writer의 push 입력(wr_x/wr_y/wr_pol)과
//       정확히 일치하는지(레인별로 1클럭 지연 페어링).
//   (2) 무손실 -- push = pop(world_we 커밋 횟수) + overrun, 이 실트래픽에선 overrun=0.
//   (3) 최종 world memory 내용 -- world_we/world_addr/world_pol을 그대로 관찰해서 만든
//       테스트벤치 쪽 메모리 모델(저장소가 이제 RTL 밖에 있으므로 이게 "진짜" 최종 상태).
module tb_aer_tx16_coord_transform_v1_uzh_trace;
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

  // 최종 world memory (RTL 밖 저장소 역할 -- world_we 관찰로 채움)
  reg mem_written [0:4095];
  reg mem_pol     [0:4095];
  integer push_total, pop_total, overrun_total, content_checks, content_mismatches;

  // 레인별 "1클럭 뒤 push에서 이 값이 나와야 한다"는 기대값 파이프라인
  reg        pend_valid [0:7];
  reg [5:0]  pend_x [0:7];
  reg [5:0]  pend_y [0:7];
  reg        pend_pol [0:7];

  task automatic check_and_advance;
    integer c, g;
    reg [11:0] xy;
    begin
      // 1) 지난 사이클에 예약해둔 기대값을 지금 world_mem_writer 입력과 대조
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

      // 2) 이번 사이클 도착(row/col/pose)으로 다음 사이클 기대값 새로 예약
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

      // 3) push/pop/overrun 집계 + world memory 반영
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
  reg [7:0] theta_by_cyc [0:60000];
  integer cyc, i;
  integer generated;

  initial begin
    rst = 1; arrival = 16'd0; polarity_in = 16'd0; theta_idx = 8'd0;
    generated = 0; push_total = 0; pop_total = 0; overrun_total = 0;
    content_checks = 0; content_mismatches = 0;
    for (i = 0; i < 4096; i = i + 1) begin mem_written[i] = 1'b0; mem_pol[i] = 1'b0; end
    for (i = 0; i < 8; i = i + 1) pend_valid[i] = 1'b0;

    fd_th = $fopen("common_traces_uzh/uzh_shapes_rotation_patch.cycle_theta.txt", "r");
    if (fd_th == 0) begin $display("CANNOT_OPEN_CYCLE_THETA"); $finish; end
    while (!$feof(fd_th)) begin
      scan_ret = $fscanf(fd_th, "%d %d", th_cyc, th_val);
      if (scan_ret == 2) theta_by_cyc[th_cyc] = th_val[7:0];
    end
    $fclose(fd_th);

    fd_ev = $fopen("common_traces_uzh/uzh_shapes_rotation_patch.addrpol.txt", "r");
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
      theta_idx = (cyc <= 60000) ? theta_by_cyc[cyc] : theta_by_cyc[60000];
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
      if (generated == 8503 && push_total == pop_total + overrun_total && overrun_total == 0 && content_mismatches == 0)
        $display("AER_TX16_COORD_TRANSFORM_V1_UZH_TRACE_PASS");
      else
        $display("AER_TX16_COORD_TRANSFORM_V1_UZH_TRACE_FAIL");
    end
    $finish;
  end
endmodule
