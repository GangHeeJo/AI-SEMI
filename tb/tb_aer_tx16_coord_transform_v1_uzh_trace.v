`timescale 1ns/1ps
// Digital 2차 1단계 통합 파이프라인(steal_buf_polarity -> coord_transform_rmcm x8 ->
// world_mem_writer) 실트래픽 검증. steal_buf_polarity의 배출(valid0/row0/col_mask0/pol_mask0,
// lane1도 동일)을 계층참조로 관찰해서, "그 사이클에 살아있는 theta_idx"로 기대값을
// coord_transform_rmcm_lut(이미 4096가지 전수 검증됨)로 직접 계산 -- 8레인 우선순위(0~7,
// 뒤가 이김)까지 그대로 재현한 shadow world_mem과, 시뮬레이션 종료 후 RTL의 rd 포트로
// 4096칸 전체를 읽어와 한 칸도 안 틀리는지 비교한다.
module tb_aer_tx16_coord_transform_v1_uzh_trace;
  `include "rtl/coord_transform_rmcm_lut.vh"

  reg clk = 0;
  reg rst;
  reg [15:0] arrival, polarity_in;
  reg [7:0]  theta_idx;
  wire [15:0] overrun;
  reg         rd_en;
  reg  [5:0]  rd_x, rd_y;
  wire        rd_written, rd_pol;

  aer_tx16_coord_transform_v1 dut (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in), .theta_idx(theta_idx),
    .overrun(overrun),
    .rd_en(rd_en), .rd_x(rd_x), .rd_y(rd_y),
    .rd_written(rd_written), .rd_pol(rd_pol)
  );

  always #5 clk = ~clk;

  reg shadow_written [0:4095];
  reg shadow_pol     [0:4095];

  task automatic shadow_write(input [1:0] row, input [1:0] col, input pol, input [7:0] th);
    reg [11:0] xy;
    reg [5:0] X, Y;
    integer addr;
    begin
      xy  = coord_transform_rmcm_lut(row, col, th);
      X = xy[11:6]; Y = xy[5:0];
      addr = Y*64 + X;
      shadow_written[addr] = 1'b1;
      shadow_pol[addr] = pol;
    end
  endtask

  // coord_transform_rmcm이 등록형(registered)이라, ev_valid/row/col이 이 사이클에 보이더라도
  // 실제로 latch되는 theta_idx는 "다음" edge 시점의 theta_idx다(top의 theta_idx도 매 사이클
  // testbench가 갱신하는 등록값이라 항상 1클럭 늦게 반영됨) -- 그래서 여기서 쓰는 theta는
  // theta_by_cyc[cyc]가 아니라 theta_by_cyc[cyc+1]이어야 RTL의 실제 캡처 시점과 일치한다.
  task automatic shadow_check_cycle(input integer cyc_now);
    integer c;
    reg [7:0] th_next;
    begin
      th_next = (cyc_now + 1 <= 60000) ? theta_by_cyc[cyc_now + 1] : theta_by_cyc[60000];
      if (dut.u_tx.valid0)
        for (c = 0; c < 4; c = c + 1)
          if (dut.u_tx.col_mask0[c]) shadow_write(dut.u_tx.row0, c[1:0], dut.u_tx.pol_mask0[c], th_next);
      if (dut.u_tx.valid1)
        for (c = 0; c < 4; c = c + 1)
          if (dut.u_tx.col_mask1[c]) shadow_write(dut.u_tx.row1, c[1:0], dut.u_tx.pol_mask1[c], th_next);
    end
  endtask

  // 입력 트레이스 -- 실제 UZH shapes_rotation 4x4 patch(addrpol.txt) + 실제 pose에서 뽑은
  // 사이클별 살아있는 theta(cycle_theta.txt, build_uzh_pose_theta.export_cycle_theta()).
  integer fd_ev, scan_ret, next_cycle, next_addr, next_pol, have_next;
  integer fd_th, th_cyc, th_val;
  reg [7:0] theta_by_cyc [0:60000];
  integer cyc, i;
  integer generated;

  initial begin
    rst = 1; arrival = 16'd0; polarity_in = 16'd0; theta_idx = 8'd0;
    rd_en = 0; rd_x = 0; rd_y = 0;
    generated = 0;
    for (i = 0; i < 4096; i = i + 1) begin shadow_written[i] = 1'b0; shadow_pol[i] = 1'b0; end

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
      shadow_check_cycle(cyc);
      cyc = cyc + 1;
    end
    $fclose(fd_ev);

    arrival = 16'd0; polarity_in = 16'd0;
    for (i = 0; i < 15000; i = i + 1) begin
      theta_idx = (cyc <= 60000) ? theta_by_cyc[cyc] : theta_by_cyc[60000];
      @(posedge clk); #1;
      shadow_check_cycle(cyc);
      cyc = cyc + 1;
    end

    begin : COMPARE
      integer x, y, addr, mismatches, filled_rtl, filled_shadow;
      mismatches = 0; filled_rtl = 0; filled_shadow = 0;
      for (y = 0; y < 64; y = y + 1) begin
        for (x = 0; x < 64; x = x + 1) begin
          rd_en = 1; rd_x = x[5:0]; rd_y = y[5:0];
          @(posedge clk); #1;
          addr = y*64 + x;
          if (shadow_written[addr]) filled_shadow = filled_shadow + 1;
          if (rd_written) filled_rtl = filled_rtl + 1;
          if (rd_written !== shadow_written[addr] ||
              (shadow_written[addr] && rd_pol !== shadow_pol[addr])) begin
            mismatches = mismatches + 1;
            if (mismatches <= 10)
              $display("MISMATCH x=%0d y=%0d rtl(written=%b pol=%b) shadow(written=%b pol=%b)",
                        x, y, rd_written, rd_pol, shadow_written[addr], shadow_pol[addr]);
          end
        end
      end
      $display("generated=%0d filled_rtl=%0d/4096 filled_shadow=%0d/4096 mismatches=%0d",
                generated, filled_rtl, filled_shadow, mismatches);
      if (mismatches == 0 && generated == 8503)
        $display("AER_TX16_COORD_TRANSFORM_V1_UZH_TRACE_PASS");
      else
        $display("AER_TX16_COORD_TRANSFORM_V1_UZH_TRACE_FAIL");
    end
    $finish;
  end
endmodule
